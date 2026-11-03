package org.trailbound.core.snowflake

import org.trailbound.flake.vwflake.Traffic
import org.trailbound.flake.vwflake.Vwflake
import java.util.concurrent.atomic.AtomicLong
import javax.inject.Inject
import javax.inject.Singleton

/**
 * The Tor Project's Snowflake proxy (v2, via the shared Go wrapper in ios/snowflake/vwflake, built into
 * libs/vwflake.aar by snowflake/build-aar.sh). The wrapper pushes byte deltas and only has start/stop; this adapts
 * it to the controller's cumulative counter and pause/resume. Only bytes cross the bridge: the wrapper drops
 * countries and connection events, so nothing about who was helped reaches the app.
 */
@Singleton
class SnowflakeEngine @Inject constructor() {

    val isAvailable: Boolean = true

    private val relayed = AtomicLong(0)
    private var capacity = 2
    private val traffic = object : Traffic {
        override fun relayed(bytes: Long) { relayed.addAndGet(bytes) }
    }

    fun start(capacity: Int) { this.capacity = capacity; Vwflake.start(capacity.toLong(), traffic) }
    /** The 50 MB prompt: stop serving; current clients drop. */
    fun pause() = Vwflake.stop()
    fun resume() = Vwflake.start(capacity.toLong(), traffic)
    fun stop() = Vwflake.stop()
    fun bytesRelayed(): Long = relayed.get()
    val lastError: String? get() = Vwflake.lastError().ifEmpty { null }
}
