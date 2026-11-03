package org.trailbound.app.ui

import org.junit.Assert.assertEquals
import org.junit.Test
import org.trailbound.core.net.TorState
import org.trailbound.core.steps.WalkStatus

/** Frames pinned from an independent port of iPhone's WallBreaker.frame(t), so both apps draw the same animation. */
class WallBreakerTest {
    @Test fun frameAt0s() {
        val f = WallBreaker.frame(0.0)
        assertEquals("           #                      \n           #                      \nyou        #                   tor\n           #                      \n(@) >      #                   (%)\n           #                      \n           #                      \n           #                      \n        censor                    ", f.art)
        assertEquals("the direct path is blocked", f.caption)
        assertEquals(false, f.through)
    }

    @Test fun frameAt4s() {
        val f = WallBreaker.frame(4.0)
        assertEquals("           #                      \n           #    *                 \nyou        #                   tor\n           #        *             \n(@) > > >x #                   (%)\n           #                      \n           #   *                  \n           #                      \n        censor                    ", f.art)
        assertEquals("volunteers light up snowflakes", f.caption)
        assertEquals(false, f.through)
    }

    @Test fun frameAt10s() {
        val f = WallBreaker.frame(10.0)
        assertEquals("           #                      \n           /    *                 \nyou                      *     tor\n                    *             \n(@) >........>.......*.........(%)\n                           *      \n               *                  \n           \\          *           \n        censor                    ", f.art)
        assertEquals("traffic slips through, still encrypted by Tor", f.caption)
        assertEquals(true, f.through)
    }

    @Test fun shortTorWording() {
        assertEquals("(%) tor \u00b7 onion ok", torLine(true, TorState.Ready(9050, 1000, onionReachable = true)))
        assertEquals("(%) tor \u00b7 checking\u2026", torLine(true, TorState.Ready(9050, 1000)))
        assertEquals("(%) tor \u00b7 retrying", torLine(true, TorState.Ready(9050, 1000, onionReachable = false)))
        assertEquals("[x] tor off", torLine(false, TorState.Off))
    }

    @Test fun walkIdleWording() = assertEquals("walk: auto \u00b7 27 s of steps needed", walkLine(WalkStatus.Idle))
}
