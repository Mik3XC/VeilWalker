package org.trailbound.core.ledger

import org.junit.Assert.assertEquals
import org.junit.Test
import org.trailbound.core.data.entity.StepInterval
import org.trailbound.core.data.entity.StepSource

class DayTotalsTest {

    private fun iv(steps: Long, source: StepSource, verdict: Float = 1f) =
        StepInterval(day = "2026-10-27", startEpochMs = 0, endEpochMs = 0, steps = steps, source = source, verdict = verdict)

    @Test fun bucketsBySourceAndWeightsVerdictBySteps() {
        val t = DayTotals.from(
            "2026-10-27",
            listOf(
                iv(500, StepSource.PASSIVE),
                iv(100, StepSource.HEALTH_CONNECT),
                iv(750, StepSource.ONION, 1f),
                iv(250, StepSource.ACTIVE_GPS, 0.6f),
                iv(10, StepSource.ACTIVE_SENSOR, 1f),
            ),
        )
        assertEquals(600L, t.passive)
        assertEquals(750L, t.onion)
        assertEquals(250L, t.gps)
        assertEquals(10L, t.sensor)
        // (750*1 + 250*0.6 + 10*1) / 1010; passive steps don't dilute the walk verdict
        assertEquals(0.9010f, t.verdict, 0.0005f)
    }

    @Test fun passiveOnlyDayHasFullVerdict() {
        assertEquals(1f, DayTotals.from("2026-10-27", listOf(iv(3000, StepSource.PASSIVE))).verdict, 0f)
    }
}
