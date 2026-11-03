package org.trailbound.core.ledger

import org.junit.Assert.assertEquals
import org.junit.Test
import org.trailbound.core.data.entity.StepSource
import org.trailbound.core.ledger.PointsPolicy.Bucket

class PointsPolicyTest {

    @Test fun everyStepCounts() {
        val day = listOf(
            Bucket(StepSource.PASSIVE, 10_000, 1f),
            Bucket(StepSource.ONION, 5_000, 1f),
        )
        // 5,000 onion @1.25 = 6,250 milli + 10,000 passive @0.5 = 5,000 milli
        assertEquals(11_250L, PointsPolicy.milliPointsForDay(day))
    }

    @Test fun noDailyCap() {
        val day = listOf(Bucket(StepSource.ACTIVE_GPS, 30_000, 1f))
        assertEquals(30_000L, PointsPolicy.milliPointsForDay(day))
    }

    @Test fun verdictScalesPoints() {
        val day = listOf(Bucket(StepSource.ACTIVE_GPS, 10_000, 0.5f))
        assertEquals(5_000L, PointsPolicy.milliPointsForDay(day))
    }
}
