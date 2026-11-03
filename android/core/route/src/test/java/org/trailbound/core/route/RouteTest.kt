package org.trailbound.core.route

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RouteTest {

    private val r = NorthStarRoute

    @Test fun routeLengthIsPlausible() {
        // Straight lines between 12 towns from Bucktown to Philadelphia: roughly 200 km.
        assertTrue("length ${r.lengthM}", r.lengthM in 150_000.0..260_000.0)
    }

    @Test fun startUnlocksFirstPostcardOnly() {
        val p = r.positionAt(0.0)
        assertEquals(1, p.unlocked.size)
        assertEquals("Cambridge, Maryland", p.next?.name)
    }

    @Test fun reachingAMilestoneUnlocksIt() {
        val atThird = r.cumulativeM[2]
        assertEquals(3, r.positionAt(atThird).unlocked.size)
        assertEquals(2, r.positionAt(atThird - 1).unlocked.size)
    }

    @Test fun pastTheEndIsFinished() {
        val p = r.positionAt(r.lengthM * 2)
        assertTrue(p.finished)
        assertEquals(r.milestones.size, p.unlocked.size)
        assertEquals(null, p.next)
    }

    @Test fun strideNeedsEnoughGpsSteps() {
        assertEquals(0.75, RouteRepository.strideFrom(100.0, 100), 0.0)
        // From the S26 Edge test walks: 806 m / 1,043 steps
        assertEquals(0.773, RouteRepository.strideFrom(806.0, 1043), 0.001)
        assertEquals(1.0, RouteRepository.strideFrom(5000.0, 1000), 0.0)
    }
}
