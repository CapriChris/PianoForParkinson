package com.pianoforparkinson.piano_practice

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteOrder
import kotlin.math.*

/** Bounded local MP3 decoding and monophonic pitch estimation. */
object Mp3Melody {
    private const val rate = 8000
    private const val maxSeconds = 600

    fun extract(file: File, cancelled: () -> Boolean): Map<String, Any> {
        val samples = decode(file, cancelled)
        val notes = mutableListOf<Map<String, Any>>()
        val frame = 512
        val hop = 160
        var active = -1
        var candidate = -1
        var stable = 0
        var candidateStart = 0
        var start = 0
        var confidence = 0.0
        var confidenceCount = 0
        var lowEnergy = Double.POSITIVE_INFINITY
        var peakEnergy = 0.0
        var retrigger = false
        fun emit(end: Int) {
            if (active >= 36 && end - start >= 640) {
                notes.add(mapOf("midi" to active, "start_ms" to start * 1000 / rate,
                    "end_ms" to end * 1000 / rate,
                    "confidence" to confidence / confidenceCount.coerceAtLeast(1)))
            }
        }
        for (offset in 0..max(0, samples.size - frame) step hop) {
            if (cancelled()) error("E_IMPORT_CANCELLED")
            if (offset + frame > samples.size) break
            val pitch = pitch(samples, offset, frame)
            val midi = pitch.first
            val energy = pitch.third
            val attack = midi == active && offset - start >= 1280 &&
                energy > lowEnergy * 1.9 && lowEnergy < peakEnergy * .6 && energy > peakEnergy * .6
            if (midi != candidate) {
                candidate = midi
                candidateStart = offset
                stable = 1
                retrigger = false
            } else if (attack && !retrigger) {
                candidateStart = offset
                stable = 1
                retrigger = true
            } else stable++
            if (stable == 3 && (candidate != active || retrigger)) {
                emit(candidateStart)
                active = candidate
                start = candidateStart
                confidence = 0.0
                confidenceCount = 0
                lowEnergy = energy
                peakEnergy = energy
                retrigger = false
            }
            if (midi == active && active >= 0) {
                confidence += pitch.second
                confidenceCount++
                lowEnergy = min(lowEnergy, energy)
                peakEnergy = max(peakEnergy, energy)
            }
            require(notes.size <= 4096) { "E_IMPORT_TOO_MANY_NOTES" }
        }
        emit(samples.size)
        require(notes.isNotEmpty()) { "E_IMPORT_NO_MELODY" }
        return mapOf("notes" to notes, "duration_ms" to samples.size * 1000L / rate,
            "method" to "local-yin-v1")
    }

    private fun pitch(data: FloatArray, offset: Int, length: Int): Triple<Int, Double, Double> {
        var energy = 0.0
        for (j in 0 until length step 2) energy += data[offset + j] * data[offset + j]
        energy /= length / 2
        if (energy < .00004) return Triple(-1, 0.0, energy)
        val difference = DoubleArray(125)
        var sum = 0.0
        for (lag in 1 until difference.size) {
            var value = 0.0
            for (j in 0 until length - difference.size step 2) {
                val delta = data[offset + j] - data[offset + j + lag]
                value += delta * delta
            }
            sum += value
            difference[lag] = if (sum == 0.0) 1.0 else value * lag / sum
        }
        var lag = 4
        while (lag < difference.size - 2) {
            if (difference[lag] < .18) {
                while (lag + 1 < difference.size && difference[lag + 1] < difference[lag]) lag++
                val before = difference[lag - 1]
                val after = difference.getOrElse(lag + 1) { difference[lag] }
                val divisor = before - 2 * difference[lag] + after
                val refined = lag + if (abs(divisor) > .000001) .5 * (before - after) / divisor else 0.0
                val midi = (69 + 12 * ln(rate / refined / 440.0) / ln(2.0)).roundToInt()
                return Triple(if (midi in 36..96) midi else -1, 1 - difference[lag], energy)
            }
            lag++
        }
        return Triple(-1, 0.0, energy)
    }

    private fun decode(file: File, cancelled: () -> Boolean): FloatArray {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(file.absolutePath)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME) in setOf("audio/mpeg", "audio/mp3")
            } ?: error("E_IMPORT_NOT_MP3")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            if (format.containsKey(MediaFormat.KEY_DURATION)) {
                require(format.getLong(MediaFormat.KEY_DURATION) <= maxSeconds * 1000000L) { "E_IMPORT_TOO_LONG" }
            }
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            var inputDone = false
            var outputDone = false
            var idle = 0
            var phase = 0
            var output = FloatArray(rate * 30)
            var size = 0
            while (!outputDone) {
                if (cancelled()) error("E_IMPORT_CANCELLED")
                if (!inputDone) {
                    val index = codec.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val buffer = codec.getInputBuffer(index)!!
                        val count = extractor.readSampleData(buffer, 0)
                        if (count < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(index, 0, count, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val index = codec.dequeueOutputBuffer(info, 10000)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val actual = codec.outputFormat
                    sampleRate = actual.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = actual.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    encoding = if (actual.containsKey(MediaFormat.KEY_PCM_ENCODING)) actual.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                    require(encoding in setOf(AudioFormat.ENCODING_PCM_16BIT, AudioFormat.ENCODING_PCM_FLOAT))
                } else if (index >= 0) {
                    idle = 0
                    val buffer = codec.getOutputBuffer(index)!!.order(ByteOrder.LITTLE_ENDIAN)
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    val bytes = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
                    while (buffer.remaining() >= channels * bytes) {
                        var mono = 0f
                        repeat(channels) { mono += if (bytes == 4) buffer.float else buffer.short / 32768f }
                        phase += rate
                        if (phase >= sampleRate) {
                            phase -= sampleRate
                            require(size < rate * maxSeconds) { "E_IMPORT_TOO_LONG" }
                            if (size == output.size) output = output.copyOf(min(rate * maxSeconds, output.size * 2))
                            output[size++] = mono / channels
                        }
                    }
                    outputDone = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    codec.releaseOutputBuffer(index, false)
                } else {
                    idle++
                    require(idle < 6000) { "E_IMPORT_DECODE_TIMEOUT" }
                }
            }
            return output.copyOf(size)
        } finally {
            runCatching { decoder?.stop() }
            decoder?.release()
            extractor.release()
        }
    }
}
