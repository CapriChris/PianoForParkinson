package com.pianoforparkinson.piano_practice

import android.content.Context
import android.media.*
import android.os.*
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.view.MotionEvent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import android.widget.Toast
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.security.MessageDigest
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val emulatorDevice: Boolean
        get() = Build.HARDWARE.contains("ranchu") || Build.HARDWARE.contains("goldfish") ||
            Build.MODEL.startsWith("sdk_gphone") || Build.FINGERPRINT.startsWith("generic")
    override fun getFlutterShellArgs(): FlutterShellArgs = super.getFlutterShellArgs().apply {
        // Previous isolated M1 comparison completed with Skia on this emulator.
        // Physical devices retain the configured Flutter renderer.
        if (emulatorDevice) {
            remove("--enable-impeller")
            remove("--enable-impeller=true")
            add("--enable-impeller=false")
        }
    }
    private val handler = Handler(Looper.getMainLooper())
    private val audioThread = HandlerThread("PianoAudio").apply { start() }
    private val audioHandler = Handler(audioThread.looper)
    private var focusGranted = false
    @Volatile private var generation = 0L
    private var speechEpoch = 0L
    private var verifiedTouchPoints = 0
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        verifiedTouchPoints = maxOf(verifiedTouchPoints, event.pointerCount)
        return super.dispatchTouchEvent(event)
    }
    private val piano = NativePiano()
    private var pieceBackingOwner: String? = null
    private var pieceBackingStarted = false
    private var voiceToken = 0
    private var gain = 850
    @Volatile private var ready = false
    @Volatile private var foreground = true
    private var trainingFullscreen = false
    private var sink: EventChannel.EventSink? = null
    private lateinit var audioManager: AudioManager
    private var tts: TextToSpeech? = null
    @Volatile private var ttsReady = false
    private val audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        audioHandler.post {
            focusGranted = change == AudioManager.AUDIOFOCUS_GAIN
            if (!focusGranted) {
                allOff(); piano.suspendStream(); tts?.stop(); publish("AUDIO_FOCUS_LOST")
            }
        }
    }
    private var focusRequest: AudioFocusRequest? = null
    private val devices = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) { audioHandler.post { allOff(); piano.suspendStream(); tts?.stop() }; publish("AUDIO_ROUTE_CHANGED") }
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) { audioHandler.post { allOff(); piano.suspendStream(); tts?.stop() }; publish("AUDIO_ROUTE_CHANGED") }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= 26) {
            focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(audioAttributes).setOnAudioFocusChangeListener(focusListener).build()
        }
        audioManager.registerAudioDeviceCallback(devices, handler)
        tts = TextToSpeech(this) { status -> ttsReady = status == TextToSpeech.SUCCESS }
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) { publishSpeech("TTS_START", utteranceId) }
            override fun onDone(utteranceId: String?) { publishSpeech("TTS_DONE", utteranceId) }
            @Suppress("DEPRECATION")
            override fun onError(utteranceId: String?) { publishSpeech("TTS_ERROR", utteranceId) }
            override fun onStop(utteranceId: String?, interrupted: Boolean) { publishSpeech("TTS_STOP", utteranceId) }
        })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "piano_training/platform_events/v1")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
                override fun onCancel(arguments: Any?) { sink = null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "piano_training/platform/v1")
            .setMethodCallHandler { call, result ->
                // Asset decoding, focus and engine control stay off the UI thread.
                // Keep all audio state and release ramps on one serial worker.
                if (call.method in setOf("prepareAudio", "playNote", "stopVoice",
                        "allNotesOff", "releaseAudio", "activateGeneration", "getAudioState",
                        "speakLocal", "stopSpeech", "preparePieceBacking",
                        "syncPieceBacking", "stopPieceBacking", "pausePieceBacking", "getPieceClock")) {
                    audioHandler.post { handle(call, result, flutterEngine) }
                } else handle(call, result, flutterEngine)
            }
    }
    private fun publish(kind: String) { handler.post { sink?.success(mapOf("kind" to kind, "generation" to generation)) } }
    private fun publishSpeech(kind: String, utteranceId: String?) {
        // Carry the original epochs so a late completion cannot clear a newer icon.
        val parts = utteranceId?.split(":", limit = 3) ?: return
        val speechGeneration = parts.getOrNull(0)?.toLongOrNull() ?: return
        val epoch = parts.getOrNull(1)?.toLongOrNull() ?: return
        handler.post { sink?.success(mapOf("kind" to kind, "generation" to speechGeneration, "speech_epoch" to epoch)) }
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result, engine: FlutterEngine) {
        val request = call.argument<String>("request_id")
        val requestGeneration = call.argument<Number>("generation")?.toLong() ?: 0L
        fun answer(data: Map<String, Any?> = emptyMap(), error: String? = null) {
            result.success(mapOf("protocol_version" to 1, "request_id" to request,
                "generation" to requestGeneration, "ok" to (error == null), "data" to data, "error_code" to error))
        }
        if (call.argument<Number>("protocol_version")?.toInt() != 1) { answer(error = "E_PROTOCOL"); return }
        try {
            when (call.method) {
                "reportFrameStall" -> {
                    audioHandler.post { allOff(); tts?.stop() }
                    Toast.makeText(this, if ((call.argument<String>("locale") ?: Locale.getDefault().language).startsWith("zh"))
                        "画面暂时未更新，练习已暂停。请重新打开应用。"
                        else "The display stopped updating. Practice paused. Reopen the app.", Toast.LENGTH_LONG).show()
                    answer()
                }
                "setTrainingFullscreen" -> {
                    trainingFullscreen = call.argument<Boolean>("enabled") == true
                    applyTrainingDisplay()
                    answer(mapOf("enabled" to trainingFullscreen))
                }
                "activateGeneration" -> {
                    val next = call.argument<Number>("new_generation")!!.toLong()
                    if (next < generation) { answer(error = "E_STALE_GENERATION"); return }
                    allOff(); tts?.stop(); generation = next; speechEpoch = 0L; answer()
                }
                "getCapabilities" -> answer(mapOf("platform" to "ANDROID", "active_generation" to generation, "os_version" to Build.VERSION.RELEASE,
                    "device_model" to "${Build.MANUFACTURER} ${Build.MODEL}", "storage_path" to noBackupFilesDir.absolutePath,
                    "timezone" to TimeZone.getDefault().id, "audio_ready" to ready, "audio_route_category" to route(),
                    "tts_locales" to localLocales(), "available_bytes" to StatFs(noBackupFilesDir.path).availableBytes,
                    "max_verified_touch_points" to verifiedTouchPoints,
                    "renderer_policy" to if (emulatorDevice) "EMULATOR_SKIA_COMPAT" else "PLATFORM_DEFAULT",
                    "touch2_supported" to packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN_MULTITOUCH), "build_verified" to false,
                    "training_fullscreen" to trainingFullscreen,
                    "status_bar_hidden" to if (Build.VERSION.SDK_INT >= 30) window.decorView.rootWindowInsets?.let { !it.isVisible(WindowInsets.Type.statusBars()) } else trainingFullscreen))
                "getStorageStatus" -> answer(mapOf("available_bytes" to StatFs(noBackupFilesDir.path).availableBytes))
                "prepareAudio" -> {
                    ready = false; allOff(); piano.reset(); piano.clearTrackCache()
                    val list = call.argument<List<Map<String, Any>>>("assets") ?: emptyList()
                    require(list.size == 10)
                    fun verified(path: String, hash: String): ByteArray {
                        val bytes = assets.open(engine.dartExecutor.flutterLoaderLookup(path)).use { it.readBytes() }
                        val actual = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                        require(actual == hash) { "E_ASSET_HASH" }
                        return bytes
                    }
                    for ((i, asset) in list.withIndex()) {
                        val pcm = piano.wave(verified(asset["path"] as String, asset["sha256"] as String))
                        piano.loadSample(i, pcm.data, pcm.rate, if (i < 7) intArrayOf(60,62,64,65,67,69,71)[i] else -1, 0, 0, 0)
                    }
                    val bank = org.json.JSONObject(assets.open(engine.dartExecutor.flutterLoaderLookup("assets/content/piano_bank.json"))
                        .bufferedReader().use { it.readText() })
                    val entries = bank.getJSONArray("samples")
                    require(entries.length() == 17)
                    for (i in 0 until entries.length()) {
                        val entry = entries.getJSONObject(i)
                        val midi = entry.getInt("midi")
                        require(midi == 36 + i * 3)
                        val pcm = piano.wave(verified(entry.getString("path"), entry.getString("sha256")))
                        require(pcm.data.size == entry.getInt("sample_frames"))
                        piano.loadSample(midi, pcm.data, pcm.rate, midi,
                            entry.getInt("loop_start"), entry.getInt("loop_end"), entry.getInt("crossfade_frames"))
                    }
                    check(piano.open())
                    ready = true
                    answer(mapOf("loaded_note_ids" to (0..9).toList(), "engine" to "OBOE", "piano_samples" to 17))
                }
                "preparePieceBacking" -> {
                    if (!foreground) { answer(error = "E_AUDIO_BACKGROUND"); return }
                    if (requestGeneration != generation) { answer(error = "E_STALE_GENERATION"); return }
                    val path = call.argument<String>("path") ?: ""
                    val owner = call.argument<String>("owner") ?: ""
                    val tempo = call.argument<Number>("tempo_bpm")?.toInt() ?: 0
                    val replayUs = call.argument<Number>("replay_duration_us")?.toLong()
                    val solo = replayUs != null && call.argument<Boolean>("solo") == true
                    require(owner.isNotBlank() && tempo in setOf(40,50,60,70,80))
                    if (replayUs != null) require(replayUs in 1L..600000000L)
                    releasePieceBacking()
                    val decodeAt = SystemClock.elapsedRealtime()
                    var decoded: NativePiano.Pcm? = null
                    if (!solo) {
                        require(path.matches(Regex("^assets/audio/backing_[a-z_]+_(40|50|60|70|80)\\.ogg$")) && path.endsWith("_${tempo}.ogg"))
                        val lookup = engine.dartExecutor.flutterLoaderLookup(path)
                        val hash = assets.open(lookup).use { stream ->
                            val digest = MessageDigest.getInstance("SHA-256")
                            val buffer = ByteArray(32768)
                            var count = stream.read(buffer)
                            while (count >= 0) {
                                if (count > 0) digest.update(buffer, 0, count)
                                count = stream.read(buffer)
                            }
                            digest.digest().joinToString("") { "%02x".format(it) }
                        }
                        if (hash != call.argument<String>("sha256")) { answer(error = "E_ASSET_HASH"); return }
                        decoded = piano.decode(assets, lookup)
                        require(decoded.data.size == call.argument<Number>("sample_frames")?.toInt())
                    }
                    val pcm = if (replayUs == null) decoded!! else {
                        val rate = 22050
                        val output = FloatArray(((replayUs * rate + 999999) / 1000000).toInt())
                        if (decoded != null) {
                            val segments = call.argument<List<Map<String, Any>>>("replay_segments") ?: emptyList()
                            require(segments.size <= 1025)
                            var previousEnd = 0L
                            for (segment in segments) {
                                val target = (segment["target_us"] as Number).toLong()
                                val source = (segment["source_us"] as Number).toLong()
                                val duration = (segment["duration_us"] as Number).toLong()
                                require(target >= previousEnd && source in 0L..600000000L && duration > 0 && duration <= replayUs && target <= replayUs-duration)
                                previousEnd = target+duration
                                val from = (source * rate / 1000000).toInt()
                                val to = (target * rate / 1000000).toInt()
                                val length = (duration * rate / 1000000).toInt()
                                require(from.toLong()+length <= decoded.data.size.toLong()+2)
                                val count = minOf(length, decoded.data.size-from, output.size-to)
                                if (count > 0) decoded.data.copyInto(output, to, from, from+count)
                                // Short edge fades avoid clicks when pausing a sustained backing.
                                val fade = minOf(110, count/2)
                                for (i in 0 until fade) {
                                    if (target > 0) output[to+i] *= i.toFloat()/fade
                                    if (target+duration < replayUs) output[to+count-1-i] *= i.toFloat()/fade
                                }
                            }
                        }
                        NativePiano.Pcm(output, rate)
                    }
                    val mixedAt = SystemClock.elapsedRealtime()
                    val melody = call.argument<List<Map<String, Any>>>("melody") ?: emptyList()
                    require(melody.size <= if (replayUs == null) 512 else 8192)
                    var totalGate = 0L
                    for (note in melody) {
                        val start = (note["start_us"] as Number).toLong()
                        val duration = (note["duration_us"] as Number).toLong()
                        require((note["note_id"] as Number).toInt() in 0..9 && (note["rate_permille"] as Number).toInt() in 125..8000)
                        require(start >= 0 && duration >= 0 && duration <= 600000000L && start <= 600000000L-duration)
                        totalGate += duration
                    }
                    require(totalGate <= 3600000000L)
                    val releaseCuts = call.argument<List<Number>>("release_cuts")?.map { it.toLong() } ?: emptyList()
                    require(replayUs != null || releaseCuts.isEmpty())
                    require(releaseCuts.size <= 1024 && releaseCuts.all { it in 0L..600000000L })
                    val releaseEnds = melody.map {
                        val end = (it["start_us"] as Number).toLong() + (it["duration_us"] as Number).toLong()
                        minOf(end+260000L, releaseCuts.filter { cut -> cut >= end }.minOrNull() ?: Long.MAX_VALUE)
                    }.toLongArray()
                    piano.prepareTrack(pcm.data, pcm.rate,
                        (call.argument<Number>("gain_permille")?.toInt() ?: 850).coerceIn(0,1000)/1000f,
                        melody.map { (it["note_id"] as Number).toInt() }.toIntArray(),
                        melody.map { (it["rate_permille"] as Number).toInt() }.toIntArray(),
                        melody.map { (it["start_us"] as Number).toLong() }.toLongArray(),
                        melody.map { (it["duration_us"] as Number).toLong() }.toLongArray(), releaseEnds)
                    check(piano.open())
                    pieceBackingOwner = owner
                    pieceBackingStarted = false
                    android.util.Log.i("QinAudio", "prepare $path decode_ms=${mixedAt-decodeAt} premix_ms=${SystemClock.elapsedRealtime()-mixedAt} replay_us=$replayUs notes=${melody.size} solo=$solo")
                    answer(mapOf("prepared" to true, "engine" to "OBOE", "premixed" to melody.isNotEmpty()))
                }
                "syncPieceBacking" -> {
                    if (requestGeneration != generation) { answer(error = "E_STALE_GENERATION"); return }
                    if (!foreground) { releasePieceBacking(); answer(error = "E_AUDIO_BACKGROUND"); return }
                    if (call.argument<String>("owner") != pieceBackingOwner) { answer(mapOf("accepted" to false)); return }
                    if (!acquireFocus()) { releasePieceBacking(); answer(error = "E_AUDIO_FOCUS"); return }
                    val position = call.argument<Number>("position_us")?.toLong() ?: 0L
                    if (!pieceBackingStarted || call.argument<Boolean>("seek") == true) {
                        check(piano.command(4, position = position))
                        pieceBackingStarted = true
                    }
                    answer(mapOf("accepted" to true, "engine" to "OBOE"))
                }
                "getPieceClock" -> {
                    if (requestGeneration != generation || call.argument<String>("owner") != pieceBackingOwner) {
                        answer(mapOf("accepted" to false)); return
                    }
                    val state = piano.state()
                    if (state[3] != 0L) { releasePieceBacking(); publish("PIECE_BACKING_ERROR"); answer(error = "E_AUDIO_STREAM"); return }
                    answer(mapOf("accepted" to true, "position_us" to state[0], "running" to (state[1] != 0L),
                        "underruns" to state[4], "sample_rate" to state[5]))
                }
                "pausePieceBacking" -> {
                    if (requestGeneration != generation || call.argument<String>("owner") != pieceBackingOwner) {
                        answer(mapOf("accepted" to false)); return
                    }
                    piano.command(5)
                    pieceBackingStarted = false
                    answer(mapOf("accepted" to true))
                }
                "stopPieceBacking" -> {
                    if (requestGeneration != generation) { answer(error = "E_STALE_GENERATION"); return }
                    if (call.argument<String>("owner") == pieceBackingOwner) releasePieceBacking()
                    answer()
                }
                "playNote" -> {
                    if (!foreground) { answer(error = "E_AUDIO_BACKGROUND"); return }
                    if (requestGeneration != generation) { answer(error = "E_STALE_GENERATION"); return }
                    if (!ready) { answer(error = "E_AUDIO_PLAY"); return }
                    if (!acquireFocus()) { answer(error = "E_AUDIO_FOCUS"); return }
                    val key = call.argument<Number>("note_id")!!.toInt()
                    val ratePermille = call.argument<Number>("rate_permille")?.toInt() ?: 1000
                    require(key in 0..9 && ratePermille in 125..8000)
                    gain = (call.argument<Number>("gain_permille")?.toInt() ?: 850).coerceIn(0,1000)
                    val voice = ++voiceToken
                    check(piano.command(1, voice, key, ratePermille / 1000f, gain / 1000f * .65f))
                    answer(mapOf("voice_id" to voice, "applied_gain_permille" to gain))
                }
                "stopVoice" -> { piano.command(2, id = call.argument<Number>("voice_id")!!.toInt()); answer() }
                "allNotesOff" -> { allOff(); answer() }
                "getAudioState" -> {
                    val state = piano.state()
                    answer(mapOf("active_voice_count" to state[2], "piece_backing_playing" to (state[1] != 0L && state[0] >= 0),
                        "piece_position_us" to state[0],
                        "engine" to "OBOE", "underruns" to state[4], "sample_rate" to state[5],
                        "foreground" to foreground, "focus_granted" to focusGranted,
                        "speech_epoch" to speechEpoch, "speech_active" to (tts?.isSpeaking == true)))
                }
                "releaseAudio" -> { allOff(); piano.reset(); piano.clearTrackCache(); ready = false; answer() }
                "speakLocal" -> {
                    if (!foreground) { answer(error = "E_AUDIO_BACKGROUND"); return }
                    if (requestGeneration != generation) { answer(error = "E_STALE_GENERATION"); return }
                    val epoch = call.argument<Number>("speech_epoch")?.toLong() ?: (speechEpoch + 1)
                    if (epoch < speechEpoch) { answer(error = "E_STALE_SPEECH"); return }
                    speechEpoch = epoch
                    val tag = call.argument<String>("locale") ?: "en"
                    val language = if (tag.startsWith("zh")) "zh" else "en"
                    val voice = tts?.voices?.firstOrNull { !it.isNetworkConnectionRequired && it.locale.language == language }
                    if (!ttsReady || voice == null) { answer(error = "E_TTS_LOCALE"); return }
                    if (!acquireFocus()) { answer(error = "E_AUDIO_FOCUS"); return }
                    tts?.voice = voice
                    val speechGain = (call.argument<Number>("gain_permille")?.toInt() ?: 1000).coerceIn(0, 1000)
                    val params = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, speechGain / 1000f) }
                    val status = tts?.speak(call.argument<String>("resolved_text"), TextToSpeech.QUEUE_FLUSH, params, "$generation:$epoch:$request")
                    answer(mapOf("accepted" to (status == TextToSpeech.SUCCESS), "applied_gain_permille" to speechGain), if (status == TextToSpeech.SUCCESS) null else "E_TTS_PLAY")
                }
                "stopSpeech" -> {
                    if (requestGeneration != generation) { answer(error = "E_STALE_GENERATION"); return }
                    val epoch = call.argument<Number>("speech_epoch")?.toLong() ?: (speechEpoch + 1)
                    if (epoch >= speechEpoch) { speechEpoch = epoch; tts?.stop() }
                    answer()
                }
                else -> answer(error = "E_METHOD")
            }
        } catch (_: Exception) {
            if (call.method in setOf("preparePieceBacking", "syncPieceBacking")) releasePieceBacking()
            answer(error = "E_PLATFORM")
        }
    }
    private fun io.flutter.embedding.engine.dart.DartExecutor.flutterLoaderLookup(path: String): String =
        io.flutter.FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(path)
    private fun acquireFocus(): Boolean {
        if (!focusGranted) {
            val focused = if (Build.VERSION.SDK_INT >= 26) audioManager.requestAudioFocus(focusRequest!!)
                else @Suppress("DEPRECATION") audioManager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
            focusGranted = focused == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
        return foreground && focusGranted
    }
    private fun localLocales(): List<String> = if (!ttsReady) emptyList() else
        tts?.voices?.filter { !it.isNetworkConnectionRequired }?.map { it.locale.toLanguageTag() }?.distinct() ?: emptyList()
    @Suppress("DEPRECATION")
    private fun route(): String {
        if (Build.VERSION.SDK_INT >= 33) {
            // Query routing for the exact attributes used by SoundPool, not all connected ports.
            val outputs = try { audioManager.getAudioDevicesForAttributes(audioAttributes) }
                catch (_: Exception) { emptyList<AudioDeviceInfo>() }
            if (outputs.size != 1) return "UNKNOWN"
            return when (outputs.single().type) {
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "BUILT_IN"
                AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> "WIRED"
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_BLE_SPEAKER -> "BLUETOOTH"
                else -> "UNKNOWN"
            }
        }
        return when {
            audioManager.isBluetoothA2dpOn -> "BLUETOOTH"
            audioManager.isWiredHeadsetOn -> "WIRED"
            else -> "UNKNOWN"
        }
    }
    private fun releasePieceBacking() {
        piano.command(5)
        pieceBackingOwner = null
        pieceBackingStarted = false
    }
    private fun allOff() {
        piano.command(3)
        pieceBackingOwner = null
        pieceBackingStarted = false
    }
    @Suppress("DEPRECATION")
    private fun applyTrainingDisplay() {
        window.decorView.post {
            if (Build.VERSION.SDK_INT >= 30) {
                window.insetsController?.let { controller ->
                    controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    if (trainingFullscreen) controller.hide(WindowInsets.Type.statusBars())
                    else controller.show(WindowInsets.Type.statusBars())
                }
            } else {
                if (trainingFullscreen) window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            }
        }
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyTrainingDisplay()
    }
    override fun onResume() { super.onResume(); foreground = true }
    override fun onPause() {
        foreground = false
        audioHandler.post { allOff(); piano.suspendStream(); focusGranted = false }
        tts?.stop(); publish("AUDIO_FOCUS_LOST"); super.onPause()
    }
    override fun onDestroy() {
        audioHandler.post {
            allOff(); piano.reset(); ready = false
            if (::audioManager.isInitialized && Build.VERSION.SDK_INT >= 26 && focusRequest != null) {
                audioManager.abandonAudioFocusRequest(focusRequest!!)
            }
            audioThread.quitSafely()
        }
        tts?.shutdown()
        if (::audioManager.isInitialized) audioManager.unregisterAudioDeviceCallback(devices)
        super.onDestroy()
    }
}

