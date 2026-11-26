package com.pianoforparkinson.piano_practice

import kotlin.math.*

/** Offline waveform-similarity overlap-add. Pitch stays tied to the input sample
 * rate while musical duration follows tempo. The audio callback only reads PCM. */
object AudioTimeStretch {
    fun stretch(input: FloatArray, speed: Double): FloatArray {
        require(speed in .125..8.0)
        if (abs(speed - 1.0) < .00001 || input.isEmpty()) return input
        val length = (input.size / speed).roundToInt().coerceAtLeast(1)
        val output = FloatArray(length)
        val weights = FloatArray(length)
        val window = 1024
        val hop = 256
        val overlap = window - hop
        val envelope = FloatArray(window) { (.5 - .5 * cos(2 * PI * it / window)).toFloat() }
        var previous = -1
        var target = 0
        while (target < length) {
            val expected = (target * speed).roundToInt()
            var best = expected.coerceIn(0, max(0, input.size - window))
            if (previous >= 0 && target + overlap < length) {
                var bestScore = Double.NEGATIVE_INFINITY
                val low = max(previous + 1, expected - 160)
                val high = min(input.size - window, expected + 160)
                for (candidate in low..high step 8) {
                    var dot = 0.0
                    var energy = .000000001
                    for (j in 0 until overlap step 8) {
                        val old = if (weights[target + j] > .0001f)
                            output[target + j] / weights[target + j] else 0f
                        val sample = input[candidate + j]
                        dot += old * sample
                        energy += sample * sample
                    }
                    val score = dot / sqrt(energy)
                    if (score > bestScore) { bestScore = score; best = candidate }
                }
            }
            val count = min(window, min(length - target, input.size - best))
            for (j in 0 until count) {
                output[target + j] += input[best + j] * envelope[j]
                weights[target + j] += envelope[j]
            }
            previous = best
            target += hop
        }
        for (i in output.indices) {
            if (weights[i] > .0001f) output[i] /= weights[i]
        }
        return output
    }
}
