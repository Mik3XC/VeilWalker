package org.trailbound.core.net

import android.content.Context
import android.os.SystemClock
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.trailbound.core.net.arti.ArtiNative
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

sealed interface TorState {
    data object Off : TorState
    data object Bootstrapping : TorState
    /** [onionReachable] is null until the first health check over the onion service finishes. */
    data class Ready(val socksPort: Int, val bootstrapMs: Long, val onionReachable: Boolean? = null, val onionRttMs: Long? = null) : TorState
    data class Failed(val reason: String) : TorState
}

/**
 * Embedded Arti (Rust) with a local SOCKS5 listener. OkHttp is pointed at it, so the rest of the app
 * doesn't care whether traffic goes over Tor or clearnet.
 *
 * Tor is ON by default. While it's on, nothing talks to the server over clearnet: if Tor isn't connected,
 * requests wait (see ApiClient) instead of falling back. Turning it off switches to HTTPS to a no-IP-logs backend.
 */
@Singleton
class TorManager @Inject constructor(@ApplicationContext private val context: Context) {

    private val _state = MutableStateFlow<TorState>(TorState.Off)
    val state: StateFlow<TorState> = _state
    private val startLock = Mutex()

    private val prefs = context.getSharedPreferences("tor", Context.MODE_PRIVATE)
    private val _enabled = MutableStateFlow(prefs.getBoolean("enabled", true))
    /** The user's Tor setting (default on). */
    val enabled: StateFlow<Boolean> = _enabled

    /** Turning Tor off stops Arti; turning it on is followed by [ensureStarted] from the caller's scope. */
    fun setEnabled(on: Boolean) {
        prefs.edit().putBoolean("enabled", on).apply()
        _enabled.value = on
        if (!on) stop()
    }

    val isConnected: Boolean get() = _state.value is TorState.Ready

    /**
     * Starts Arti if needed, then checks the production onion service is reachable.
     * Arti gives up after 45 s on its own (state = Failed) so a walk never blocks on Tor.
     */
    suspend fun ensureStarted(): Boolean = startLock.withLock {
        withContext(Dispatchers.IO) {
            if (isConnected) return@withContext true
            if (!ArtiNative.isLoaded) {
                _state.value = TorState.Failed("arti native library not bundled")
                return@withContext false
            }
            _state.value = TorState.Bootstrapping
            val stateDir = context.filesDir.resolve("arti").apply { mkdirs() }.absolutePath
            val cacheDir = context.cacheDir.resolve("arti").apply { mkdirs() }.absolutePath
            val t0 = SystemClock.elapsedRealtime()
            val port = ArtiNative.start(stateDir, cacheDir)
            val bootMs = SystemClock.elapsedRealtime() - t0
            if (port <= 0) {
                val reason = ArtiNative.lastError().ifBlank { "unknown error" }
                Log.w(TAG, "bootstrap failed after ${bootMs}ms: $reason")
                _state.value = TorState.Failed(reason)
                return@withContext false
            }
            Log.i(TAG, "bootstrapped in ${bootMs}ms, socks on 127.0.0.1:$port")
            _state.value = TorState.Ready(port, bootMs)
            // Probe in the background: a first onion circuit can take a minute, and requests shouldn't wait on it.
            scope.launch { checkOnion() }
            true
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * GET /health on the production onion service. The first circuit to an onion service sometimes fails
     * (slow path, or a descriptor still propagating after a server restart), so only report "unreachable"
     * after [ONION_ATTEMPTS] tries; until then the status stays "checking".
     */
    private suspend fun checkOnion() {
        repeat(ONION_ATTEMPTS) { attempt ->
            val ready = _state.value as? TorState.Ready ?: return
            if (ready.onionReachable == true) return   // a real request already proved it
            val t0 = SystemClock.elapsedRealtime()
            val ok = runCatching {
                httpClient().newCall(Request.Builder().url("$ONION_BASE_URL/health").build()).execute().use {
                    it.isSuccessful && it.body.string().trim() == "ok"
                }
            }.onFailure { Log.w(TAG, "onion health check attempt ${attempt + 1} failed: ${it.message}") }.getOrDefault(false)
            val rtt = SystemClock.elapsedRealtime() - t0
            Log.i(TAG, "onion /health reachable=$ok in ${rtt}ms (attempt ${attempt + 1})")
            if (ok) { markOnionOk(rtt); return }
            if (attempt < ONION_ATTEMPTS - 1) delay(20_000)
        }
        (_state.value as? TorState.Ready)?.let { if (it.onionReachable != true) _state.value = it.copy(onionReachable = false) }
    }

    /** Called whenever a request over the onion service succeeds: real traffic beats any probe. */
    fun markOnionOk(rttMs: Long? = null) {
        val ready = _state.value as? TorState.Ready ?: return
        if (ready.onionReachable != true) _state.value = ready.copy(onionReachable = true, onionRttMs = rttMs ?: ready.onionRttMs)
    }

    fun stop() {
        if (ArtiNative.isLoaded) ArtiNative.stop()
        _state.value = TorState.Off
    }

    /** HTTP client for the current mode. Rebuild after Tor state changes. */
    fun httpClient(base: OkHttpClient = OkHttpClient()): OkHttpClient {
        val s = _state.value
        return if (s is TorState.Ready) {
            base.newBuilder()
                .proxy(Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", s.socksPort)))
                .connectTimeout(60, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .callTimeout(50, TimeUnit.SECONDS)   // a stuck onion circuit can't block retries forever
                .build()
        } else base
    }

    companion object {
        private const val TAG = "VeilWalker/Tor"
        private const val ONION_ATTEMPTS = 3

        /** Onion first when Tor is up; clearnet otherwise. Onion keys persist on the Railway /data volume. */
        const val ONION_BASE_URL = "http://6y62fbzjvat43ep2wukogoszr2wtzc2lkzf2bp22wuixkw4lgwxl6cid.onion"
        const val CLEARNET_BASE_URL = "https://feisty-presence-production-b8ec.up.railway.app"
    }
}
