package com.pianoforparkinson.piano_practice

import android.content.res.AssetManager
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Only called on PianoAudio, except Oboe's allocation-free render callback. */
class NativePiano {
    companion object { init { System.loadLibrary("qin_audio") } }
    external fun reset()
    external fun suspendStream()
    external fun open(): Boolean
    external fun loadSample(id: Int, pcm: FloatArray, rate: Int, root: Int,
                            loopStart: Int, loopEnd: Int, crossfade: Int)
    external fun command(kind: Int, id: Int = 0, note: Int = 0, ratio: Float = 1f,
                         gain: Float = 0f, position: Long = 0): Boolean
    external fun prepareTrack(pcm: FloatArray, rate: Int, gain: Float,
                              notes: IntArray, ratios: IntArray,
                              starts: LongArray, durations: LongArray, releaseEnds: LongArray)
    external fun state(): LongArray
    private external fun decodeVorbis(encoded: ByteArray): FloatArray

    data class Pcm(val data: FloatArray, val rate: Int)
    private var cachedPath: String? = null
    private var cachedPcm: Pcm? = null
    fun clearTrackCache() { cachedPath = null; cachedPcm = null }
    fun wave(bytes: ByteArray): Pcm {
        val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        require(String(bytes, 0, 4) == "RIFF" && String(bytes, 8, 4) == "WAVE")
        var cursor = 12
        var rate = 0
        var channels = 0
        while (cursor + 8 <= bytes.size) {
            val name = String(bytes, cursor, 4)
            val size = b.getInt(cursor + 4)
            require(size >= 0 && cursor.toLong() + 8 + size <= bytes.size)
            val start = cursor + 8
            if (name == "fmt ") {
                require(size >= 16 && b.getShort(start).toInt() == 1 && b.getShort(start + 14).toInt() == 16)
                channels = b.getShort(start + 2).toInt(); rate = b.getInt(start + 4)
                require(channels in 1..2 && rate in 8000..96000)
            }
            if (name == "data") {
                require(rate > 0 && size % (2 * channels) == 0)
                val pcm = FloatArray(size / (2 * channels))
                for (i in pcm.indices) {
                    var v = 0f
                    for (c in 0 until channels) v += b.getShort(start + (i * channels + c) * 2) / 32768f
                    pcm[i] = v / channels
                }
                return Pcm(pcm, rate)
            }
            cursor = start + size + size % 2
        }
        error("No PCM data")
    }

    fun decode(assets: AssetManager, path: String): Pcm {
        if (path == cachedPath) cachedPcm?.let { return it }
        val encoded = assets.open(path).use { it.readBytes() }
        return Pcm(decodeVorbis(encoded), 22050).also { cachedPath = path; cachedPcm = it }
    }
}
