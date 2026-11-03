package org.trailbound.core.steps

import org.junit.Assert.assertEquals
import org.junit.Test

class WalkDistanceTest {
    @Test fun driftIsCappedAtTwoMetresPerStep() = assertEquals(264.0, WalkDistance.capped(2_059.0, 132), 0.0)
    @Test fun realDistanceIsKept() = assertEquals(950.0, WalkDistance.capped(950.0, 1_300), 0.0)
    @Test fun noStepsNoDistance() = assertEquals(0.0, WalkDistance.capped(400.0, 0), 0.0)
}
