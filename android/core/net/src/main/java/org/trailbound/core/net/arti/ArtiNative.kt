package org.trailbound.core.net.arti

/**
 * JNI surface of rust/trailbound-net (libtrailbound_net.so). Kept tiny on purpose: start, stop, and that's it.
 * Build the .so with `cargo ndk` (see rust/trailbound-net/README.md); the app still runs without it,
 * with Tor Mode reported as unavailable.
 */
object ArtiNative {
    val isLoaded: Boolean = runCatching { System.loadLibrary("trailbound_net") }.isSuccess

    /** Bootstraps Arti and opens a SOCKS5 listener on 127.0.0.1. Blocks; returns the port, or -1 on failure. */
    external fun start(stateDir: String, cacheDir: String): Int

    external fun stop()

    /** Reason the last [start] returned -1 (empty after a success). */
    external fun lastError(): String
}
