package org.trailbound.core.steps

/** What the walk service is doing right now, for the home screen. */
sealed interface WalkStatus {
    data object Idle : WalkStatus
    /** Auto-detected movement; becomes a walk after [AutoWalk.CONFIRM_MS] of continuous steps. */
    data class Confirming(val walkingForMs: Long) : WalkStatus
    data class Walking(val mode: WalkMode, val startedMs: Long, val steps: Long, val gps: Boolean) : WalkStatus
    /** Still for 47 s+: steps resume the walk; 3 min shows the red-light notice; 4.5 min ends it. */
    data class Paused(val mode: WalkMode, val startedMs: Long, val steps: Long, val idleMs: Long) : WalkStatus
}
