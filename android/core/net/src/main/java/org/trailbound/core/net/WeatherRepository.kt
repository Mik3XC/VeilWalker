package org.trailbound.core.net

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.roundToInt

/** Outside temperature, car-dashboard style: a snowflake at 30°F or below. */
data class Weather(val tempF: Int, val fetchedAtMs: Long) {
    val freezing: Boolean get() = tempF <= FREEZING_F

    companion object { const val FREEZING_F = 30 }
}

/**
 * Current temperature from the US National Weather Service (api.weather.gov: public domain, no key, no account).
 *
 * Privacy: the location is rounded to 0.1° (about 11 km) before it leaves the phone, it goes over Tor whenever
 * Tor is on (and not at all if Tor is on but not connected yet), and nothing is stored but the last temperature.
 */
@Singleton
class WeatherRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val tor: TorManager,
) {
    private val prefs = context.getSharedPreferences("weather", Context.MODE_PRIVATE)
    private val _weather = MutableStateFlow(
        prefs.getInt("temp_f", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE }?.let { Weather(it, prefs.getLong("at", 0)) }
    )
    val weather: StateFlow<Weather?> = _weather
    private val lock = Mutex()

    private val _enabled = MutableStateFlow(prefs.getBoolean("enabled", false))
    /** Opt-in (off by default): weather is the only feature that sends any location off the phone. */
    val enabled: StateFlow<Boolean> = _enabled

    /** Turning it off also forgets the last reading, so no snowflake and no cold climb until it's back on. */
    fun setEnabled(on: Boolean) {
        val e = prefs.edit().putBoolean("enabled", on)
        if (!on) e.remove("temp_f").remove("at")
        e.apply()
        _enabled.value = on
        if (!on) _weather.value = null
    }

    /** Refreshes if the reading is older than [maxAgeMs]. Safe to call often; failures keep the last reading. */
    suspend fun refresh(maxAgeMs: Long = 30 * 60_000L) = lock.withLock {
        if (!_enabled.value) return@withLock
        val last = _weather.value
        if (last != null && System.currentTimeMillis() - last.fetchedAtMs < maxAgeMs) return@withLock
        val (lat, lon) = coarseLocation() ?: return@withLock
        val client = when {
            !tor.enabled.value -> OkHttpClient()
            tor.isConnected -> tor.httpClient()
            else -> return@withLock   // Tor on but not up yet: wait rather than leak the request in the clear
        }.newBuilder().callTimeout(45, TimeUnit.SECONDS).build()

        val temp = withContext(Dispatchers.IO) {
            runCatching {
                val point = "https://api.weather.gov/points/%.1f,%.1f".format(Locale.US, lat, lon)
                val hourly = JSONObject(get(client, point)).getJSONObject("properties").getString("forecastHourly")
                val now = JSONObject(get(client, hourly)).getJSONObject("properties").getJSONArray("periods").getJSONObject(0)
                val t = now.getDouble("temperature")
                if (now.optString("temperatureUnit") == "C") (t * 9 / 5 + 32).roundToInt() else t.roundToInt()
            }.onFailure { Log.w(TAG, "weather fetch failed: ${it.message}") }.getOrNull()
        } ?: return@withLock

        val w = Weather(temp, System.currentTimeMillis())
        prefs.edit().putInt("temp_f", w.tempF).putLong("at", w.fetchedAtMs).apply()
        _weather.value = w
        Log.i(TAG, "temp ${w.tempF}F freezing=${w.freezing}")
    }

    private fun get(client: OkHttpClient, url: String): String =
        client.newCall(
            Request.Builder().url(url)
                // NWS asks every app to identify itself; this names the app, never the user.
                .header("User-Agent", "VeilWalker/1.0 (premiselayer@gmail.com)")
                .header("Accept", "application/geo+json")
                .build()
        ).execute().use { r ->
            check(r.isSuccessful) { "HTTP ${r.code}" }
            r.body.string()
        }

    /** Last known position from any provider, rounded to 0.1°. Never turns the GPS on by itself. */
    @SuppressLint("MissingPermission")
    private fun coarseLocation(): Pair<Double, Double>? {
        val granted = listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            .any { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        if (!granted) return null
        val lm = context.getSystemService(LocationManager::class.java)
        val best = lm.getProviders(true).mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time }
            ?: return null
        return Math.round(best.latitude * 10) / 10.0 to Math.round(best.longitude * 10) / 10.0
    }

    private companion object { const val TAG = "VeilWalker/Weather" }
}
