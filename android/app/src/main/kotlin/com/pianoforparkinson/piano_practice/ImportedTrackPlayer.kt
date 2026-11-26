package com.pianoforparkinson.piano_practice

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.SystemClock
import java.io.File

/** Stream imported songs so slowing a long MP3 does not allocate a full PCM track. */
class ImportedTrackPlayer(private val handler: Handler, file: File, sourceTempo: Int, tempo: Int) {
    private val player = MediaPlayer()
    private val speed = tempo.toFloat() / sourceTempo
    private var revision = 0
    private var anchor = 0L
    private var paused = true
    private var started = false
    private var ended = false
    private var failed = false
    private fun now() = SystemClock.elapsedRealtimeNanos() / 1000
    val audible: Boolean
        get() = !paused && started && !ended && !failed && player.isPlaying

    init {
        player.setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
        player.setDataSource(file.absolutePath)
        player.prepare()
        player.setOnCompletionListener { ended = true }
        player.setOnErrorListener { _, _, _ -> failed = true; true }
    }

    fun play(positionUs: Long) {
        check(!failed) { "E_IMPORTED_AUDIO" }
        val token = ++revision
        if (player.isPlaying) player.pause()
        paused = false
        started = false
        ended = false
        anchor = now() - positionUs
        player.setOnSeekCompleteListener {
            if (token == revision && !paused) {
                val delay = (anchor - now()).coerceAtLeast(0) / 1000
                handler.postDelayed({
                    if (token == revision && !paused) {
                        player.playbackParams = player.playbackParams.setSpeed(speed).setPitch(1f)
                        player.start()
                        started = true
                    }
                }, delay)
            }
        }
        player.seekTo((positionUs.coerceAtLeast(0) * speed / 1000).toInt())
    }

    fun position(): Long {
        check(!failed) { "E_IMPORTED_AUDIO" }
        val predicted = now() - anchor
        if (paused || !started || ended || predicted < 0) return predicted
        val stamp = player.timestamp
        return if (stamp != null) {
            ((stamp.anchorMediaTimeUs + (System.nanoTime() - stamp.anchorSytemNanoTime) / 1000.0 * stamp.mediaClockRate) / speed).toLong()
        } else (player.currentPosition * 1000.0 / speed).toLong()
    }

    fun pause() {
        ++revision
        if (player.isPlaying) player.pause()
        paused = true
    }

    fun setVolume(value: Float) = player.setVolume(value, value)

    fun close() {
        ++revision
        paused = true
        player.release()
    }
}
