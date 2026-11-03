package org.trailbound.core.snowflake

import javax.inject.Inject
import javax.inject.Singleton

/**
 * Thin wrapper over the gomobile-built Snowflake proxy AAR (git.torproject.org/pluggable-transports/snowflake, /proxy).
 * Until that AAR is built and added (core/snowflake/libs/snowflake.aar), this reports unavailable and
 * Snowflake Walk behaves like a normal Active Walk.
 */
@Singleton
class SnowflakeEngine @Inject constructor() {

    // TODO(snowflake-aar): replace these stubs with calls into the generated `snowflake.Proxy` bindings.
    val isAvailable: Boolean = false

    private var relayed = 0L

    fun start(capacity: Int) { /* proxy.start(brokerUrl, capacity) */ }
    fun pause() { /* stop accepting new clients; let current ones drain */ }
    fun resume() { /* accept clients again */ }
    fun stop() { /* proxy.stop() */ }
    fun bytesRelayed(): Long = relayed
}
