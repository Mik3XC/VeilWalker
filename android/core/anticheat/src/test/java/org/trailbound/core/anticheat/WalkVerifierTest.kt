package org.trailbound.core.anticheat

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class WalkVerifierTest {

    private fun noisy(n: Int, scale: Float, seed: Int) =
        Random(seed).let { r -> FloatArray(n) { (r.nextFloat() - 0.5f) * scale } }

    @Test fun realisticWalkScoresHigh() {
        val v = WalkVerifier()
        val w = SensorWindow(
            steps = 19, durationS = 10.0,
            accelMagnitudes = FloatArray(200) { 9.8f + noisy(200, 4f, 1)[it] },
            gyroX = noisy(200, 1f, 2), gyroY = noisy(200, 1f, 3), gyroZ = noisy(200, 1f, 4),
        )
        assertTrue(v.score(w, GpsCheck(5.0, false)).score > 0.9f)
    }

    @Test fun singleAxisSwingIsFlagged() {
        val v = WalkVerifier()
        val w = SensorWindow(
            steps = 20, durationS = 10.0,
            accelMagnitudes = FloatArray(200) { 9.8f + noisy(200, 4f, 1)[it] },
            gyroX = noisy(200, 3f, 2), gyroY = FloatArray(200), gyroZ = FloatArray(200),
        )
        assertTrue(Flag.SINGLE_AXIS_ROTATION in v.score(w, null).flags)
    }

    @Test fun stoppingAtEndOfWalkIsNotPenalised() {
        // Real case from the S26 Edge test walk: the last window had 2 steps as the user stopped.
        val v = WalkVerifier()
        val w = SensorWindow(
            steps = 2, durationS = 10.0,
            accelMagnitudes = FloatArray(200) { 9.8f + noisy(200, 4f, 9)[it] },
            gyroX = noisy(200, 1f, 10), gyroY = noisy(200, 1f, 11), gyroZ = noisy(200, 1f, 12),
        )
        assertTrue(Flag.CADENCE_OUT_OF_BAND !in v.score(w, null).flags)
    }

    @Test fun slowCrossingWindowIsNotPenalised() {
        // From the 10-min test walk: 9 steps in a window while slowing for a crossing.
        val v = WalkVerifier()
        val w = SensorWindow(
            steps = 9, durationS = 10.0,
            accelMagnitudes = FloatArray(200) { 9.8f + noisy(200, 4f, 13)[it] },
            gyroX = noisy(200, 1f, 14), gyroY = noisy(200, 1f, 15), gyroZ = noisy(200, 1f, 16),
        )
        assertTrue(v.score(w, GpsCheck(3.0, false)).flags.isEmpty())
    }

    @Test fun shakerCadenceIsFlagged() {
        val v = WalkVerifier()
        val w = SensorWindow(
            steps = 45, durationS = 10.0,
            accelMagnitudes = FloatArray(200) { 9.8f + noisy(200, 4f, 17)[it] },
            gyroX = noisy(200, 1f, 18), gyroY = noisy(200, 1f, 19), gyroZ = noisy(200, 1f, 20),
        )
        assertTrue(Flag.CADENCE_OUT_OF_BAND in v.score(w, null).flags)
    }

    @Test fun deadZoneIsNotPenalised() {
        val v = WalkVerifier()
        val w = SensorWindow(
            steps = 18, durationS = 10.0,
            accelMagnitudes = FloatArray(200) { 9.8f + noisy(200, 4f, 5)[it] },
            gyroX = noisy(200, 1f, 6), gyroY = noisy(200, 1f, 7), gyroZ = noisy(200, 1f, 8),
        )
        assertTrue(v.score(w, GpsCheck(speedKmh = null, isMock = false)).flags.isEmpty())
    }
}
