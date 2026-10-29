"""One-time mechanical migration, retained with the implementation audit."""
from pathlib import Path
P = Path(__file__).resolve().parents[1] / 'android/app/src/main/kotlin/com/pianoforparkinson/piano_practice/MainActivity.kt'
s = P.read_text(encoding='utf8')
if '    private var pool:' not in s:
    raise SystemExit('Already migrated; this archived migration is not a rebuild step.')
start = s.index('    private var pool:')
end = s.index('    private var gain =', start)
s = s[:start] + '''    private val piano = NativePiano()
    private var pieceBackingOwner: String? = null
    private var pieceBackingStarted = false
    private var voiceToken = 0
''' + s[end:]
s = s.replace('"syncPieceBacking", "stopPieceBacking"', '"syncPieceBacking", "stopPieceBacking", "getPieceClock"')
start = s.index('                "prepareAudio" ->')
end = s.index('                "speakLocal" ->', start)
s = s[:start] + '''                "prepareAudio" -> {
                    ready = false; allOff(); piano.reset()
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
                    require(path.matches(Regex("^assets/audio/backing_[a-z_]+_(40|50|60|70|80)\\\\.ogg$")) && path.endsWith("_${tempo}.ogg"))
                    require(owner.isNotBlank() && tempo in setOf(40,50,60,70,80))
                    releasePieceBacking()
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
                    val pcm = piano.decode(assets, lookup)
                    val melody = call.argument<List<Map<String, Any>>>("melody") ?: emptyList()
                    require(melody.size <= 512)
                    piano.prepareTrack(pcm.data, pcm.rate,
                        (call.argument<Number>("gain_permille")?.toInt() ?: 850).coerceIn(0,1000)/1000f,
                        melody.map { (it["note_id"] as Number).toInt() }.toIntArray(),
                        melody.map { (it["rate_permille"] as Number).toInt() }.toIntArray(),
                        melody.map { (it["start_us"] as Number).toLong() }.toLongArray(),
                        melody.map { (it["duration_us"] as Number).toLong() }.toLongArray())
                    check(piano.open())
                    pieceBackingOwner = owner
                    pieceBackingStarted = false
                    answer(mapOf("prepared" to true, "engine" to "OBOE", "premixed" to melody.isNotEmpty()))
                }
                "syncPieceBacking" -> {
                    if (requestGeneration != generation) { answer(error = "E_STALE_GENERATION"); return }
                    if (!foreground) { releasePieceBacking(); answer(error = "E_AUDIO_BACKGROUND"); return }
                    if (call.argument<String>("owner") != pieceBackingOwner) { answer(mapOf("accepted" to false)); return }
                    if (!acquireFocus()) { releasePieceBacking(); answer(error = "E_AUDIO_FOCUS"); return }
                    val position = call.argument<Number>("position_us")?.toLong() ?: 0L
                    if (!pieceBackingStarted) {
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
                    require(key in 0..9 && ratePermille in 500..2000)
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
                        "engine" to "OBOE", "underruns" to state[4], "sample_rate" to state[5],
                        "foreground" to foreground, "focus_granted" to focusGranted,
                        "speech_epoch" to speechEpoch, "speech_active" to (tts?.isSpeaking == true)))
                }
                "releaseAudio" -> { allOff(); piano.reset(); ready = false; answer() }
''' + s[end:]
start = s.index('    private fun rebalance()')
end = s.index('    @Suppress("DEPRECATION")\n    private fun applyTrainingDisplay',start)
s = s[:start] + '''    private fun releasePieceBacking() {
        piano.command(5)
        pieceBackingOwner = null
        pieceBackingStarted = false
    }
    private fun allOff() {
        piano.command(3)
        pieceBackingOwner = null
        pieceBackingStarted = false
    }
''' + s[end:]
s=s.replace('allOff(); pool?.release(); pool = null; ready = false','allOff(); piano.reset(); ready = false')
s=s.replace('// Audio focus and SoundPool can block in device/vendor code.', '// Asset decoding, focus and engine control stay off the UI thread.')
P.write_text(s,encoding='utf8')
