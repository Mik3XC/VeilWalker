package org.trailbound.core.steps

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.trailbound.core.anticheat.Fix
import org.trailbound.core.anticheat.GpsSmoother
import org.trailbound.core.anticheat.SensorWindow
import org.trailbound.core.anticheat.WalkVerifier
import org.trailbound.core.data.dao.StepDao
import org.trailbound.core.data.dao.WalkDao
import org.trailbound.core.data.entity.StepSource
import org.trailbound.core.data.entity.WalkModeEntity
import org.trailbound.core.data.entity.WalkSession
import org.trailbound.core.ledger.SyncWorker
import org.trailbound.core.net.TorManager
import org.trailbound.core.net.WeatherRepository
import org.trailbound.core.snowflake.SnowflakeController
import org.trailbound.core.snowflake.SnowflakeEvent
import javax.inject.Inject
import kotlin.math.sqrt

enum class WalkMode { ACTIVE, ONION, SNOWFLAKE }

/**
 * The only foreground service in the app, and it runs only while the user is on a walk.
 *  - health:     step + motion sensors (requires ACTIVITY_RECOGNITION granted *before* start on API 34+)
 *  - location:   while-in-use GPS veto checks (never background location)
 *  - specialUse: Snowflake proxy, Snowflake Walk only
 */
@AndroidEntryPoint
class WalkService : LifecycleService(), SensorEventListener {

    @Inject lateinit var reader: StepCounterReader
    @Inject lateinit var walkDao: WalkDao
    @Inject lateinit var stepDao: StepDao
    @Inject lateinit var tor: TorManager
    @Inject lateinit var weather: WeatherRepository
    @Inject lateinit var snowflake: SnowflakeController

    private val sensorManager by lazy { getSystemService(SensorManager::class.java) }
    private val fused by lazy { LocationServices.getFusedLocationProviderClient(this) }
    private val verifier = WalkVerifier()
    private val gps = GpsSmoother()

    private var walk: WalkSession? = null
    private var mode = WalkMode.ACTIVE
    private var tick: Job? = null
    private var watchdog: Job? = null
    private var verdictSum = 0.0
    private var verdictCount = 0
    private var gpsOn = false

    // Step timing from TYPE_STEP_DETECTOR: drives auto-confirm, pause, red light and auto-end.
    @Volatile private var lastStepMs = 0L
    @Volatile private var walkingSinceMs = 0L
    private var redLightShown = false

    // 10 s window buffers
    private val accel = ArrayList<Float>(256)
    private val gx = ArrayList<Float>(256)
    private val gy = ArrayList<Float>(256)
    private val gz = ArrayList<Float>(256)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        when (intent?.action) {
            ACTION_STOP -> stopWalk()
            ACTION_CONTINUE -> { lastStepMs = System.currentTimeMillis(); redLightShown = false; notify(notification("Walk continues")) }
            ACTION_FOREGROUND -> upgradeToGps()
            ACTION_SNOWFLAKE_EXTEND -> snowflake.extendWalkCap()
            ACTION_SNOWFLAKE_STOP -> snowflake.stop()
            else -> {
                // One walk at a time: a second start while walking is ignored rather than orphaning the first session.
                if (isRunning) return START_NOT_STICKY
                val auto = intent?.action == ACTION_AUTO
                mode = when {
                    snowflake.hostOnWalks.value -> WalkMode.SNOWFLAKE
                    tor.enabled.value -> WalkMode.ONION
                    else -> WalkMode.ACTIVE
                }
                // Auto starts come from the background, where while-in-use location isn't available: sensor-only
                // until the app is opened (upgradeToGps).
                if (!startInForeground(withGps = !auto)) { stopSelf(); return START_NOT_STICKY }
                isRunning = true
                registerSensors()
                if (auto) confirmThenWalk() else startWalk()
            }
        }
        return START_NOT_STICKY
    }

    private fun hasPerm(p: String) =
        ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    private fun startInForeground(withGps: Boolean): Boolean {
        // Health FGS type crashes on API 34+ without activity recognition, so check before starting.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !hasPerm(Manifest.permission.ACTIVITY_RECOGNITION)) return false
        gpsOn = withGps && hasPerm(Manifest.permission.ACCESS_FINE_LOCATION)
        var types = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            types = ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
            if (gpsOn) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            if (mode == WalkMode.SNOWFLAKE) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && gpsOn) {
            types = ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        }
        ServiceCompat.startForeground(this, NOTIF_ID, notification(if (walk == null) "Checking if you're walking…" else "Walk in progress"), types)
        return true
    }

    /** Opening the app during an auto-started walk adds GPS (allowed now that we're in the foreground). */
    private fun upgradeToGps() {
        if (!isRunning || gpsOn || !hasPerm(Manifest.permission.ACCESS_FINE_LOCATION)) return
        if (runCatching { startInForeground(withGps = true) }.isSuccess && gpsOn) requestLocation()
    }

    /** Auto-detected movement must be 27 s of continuous steps within a minute, or it was nothing. */
    private fun confirmThenWalk() {
        status.value = WalkStatus.Confirming(0)
        lifecycleScope.launch {
            reader.recordDelta(StepSource.PASSIVE)   // bank passive steps; the walk's first window then includes the confirm phase
            val deadline = System.currentTimeMillis() + 60_000
            while (System.currentTimeMillis() < deadline) {
                delay(1_000)
                val walkingFor = if (walkingSinceMs == 0L) 0 else System.currentTimeMillis() - walkingSinceMs
                status.value = WalkStatus.Confirming(walkingFor)
                if (walkingFor >= AutoWalk.CONFIRM_MS) { startWalk(bankPassive = false); return@launch }
            }
            abandon()
        }
    }

    private fun startWalk(bankPassive: Boolean = true) {
        lifecycleScope.launch {
            // Close sessions left open by a killed process, then bank passive steps so the walk starts clean.
            walkDao.closeOpenSessions(System.currentTimeMillis())
            if (bankPassive) reader.recordDelta(StepSource.PASSIVE)
            val id = walkDao.insert(WalkSession(mode = WalkModeEntity.valueOf(mode.name), startEpochMs = System.currentTimeMillis()))
            walk = walkDao.get(id)
            lastStepMs = System.currentTimeMillis()
            notify(notification("Walk in progress"))

            if (tor.enabled.value) launch { tor.ensureStarted() }
            launch { delay(30_000); weather.refresh(maxAgeMs = 20 * 60_000L) }   // after Tor has had a moment to come up
            climbRef = Double.NaN; altSmooth = Double.NaN; stepsSinceRef = 0; coldClimbM = 0.0
            if (mode == WalkMode.SNOWFLAKE) startSnowflake()
            if (gpsOn) requestLocation()

            tick = launch { windowLoop() }
            watchdog = launch { stillnessLoop() }
        }
    }

    /** No walk happened (auto-detection didn't confirm): leave quietly; the steps stay passive. */
    private fun abandon() {
        sensorManager.unregisterListener(this)
        isRunning = false
        status.value = WalkStatus.Idle
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun registerSensors() {
        listOf(Sensor.TYPE_ACCELEROMETER, Sensor.TYPE_GYROSCOPE, Sensor.TYPE_STEP_DETECTOR, Sensor.TYPE_PRESSURE).forEach { type ->
            sensorManager.getDefaultSensor(type)?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
        }
    }

    @SuppressLint("MissingPermission") // checked by caller
    private fun requestLocation() {
        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000).build()
        fused.requestLocationUpdates(req, locationCallback, Looper.getMainLooper())
    }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(r: LocationResult) {
            r.locations.forEach { l ->
                val mock = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) l.isMock else @Suppress("DEPRECATION") l.isFromMockProvider
                gps.add(Fix(l.time, l.latitude, l.longitude, l.accuracy, mock))
            }
        }
    }

    override fun onSensorChanged(e: SensorEvent) {
        when (e.sensor.type) {
            Sensor.TYPE_ACCELEROMETER ->
                accel += sqrt(e.values[0] * e.values[0] + e.values[1] * e.values[1] + e.values[2] * e.values[2])
            Sensor.TYPE_GYROSCOPE -> { gx += e.values[0]; gy += e.values[1]; gz += e.values[2] }
            Sensor.TYPE_STEP_DETECTOR -> {
                val now = System.currentTimeMillis()
                // A gap over 4 s breaks "continuous walking" for the auto-confirm timer.
                if (walkingSinceMs == 0L || now - lastStepMs > 4_000) walkingSinceMs = now
                lastStepMs = now
                stepsSinceRef++
            }
            Sensor.TYPE_PRESSURE -> onPressure(e.values[0])
        }
    }

    // ---- Hidden Peaks: virtual trail climb per step plus real barometric climb, on freezing walks only ----
    private var altSmooth = Double.NaN
    private var climbRef = Double.NaN
    private var stepsSinceRef = 0
    private var coldClimbM = 0.0

    /**
     * Smooths barometric altitude and banks a climb once it rises [CLIMB_STEP_M] above the last low point.
     * Anti-cheat: a climb only counts up to [MAX_RISE_PER_STEP_M] per step taken, so elevators, cars and
     * weather fronts (pressure changes with no walking) add nothing. Only counts while it's freezing outside.
     */
    private fun onPressure(hPa: Float) {
        if (walk == null) return
        val alt = SensorManager.getAltitude(SensorManager.PRESSURE_STANDARD_ATMOSPHERE, hPa).toDouble()
        altSmooth = if (altSmooth.isNaN()) alt else altSmooth + 0.1 * (alt - altSmooth)
        if (climbRef.isNaN()) { climbRef = altSmooth; return }
        when {
            altSmooth >= climbRef + CLIMB_STEP_M -> {
                val credited = minOf(altSmooth - climbRef, stepsSinceRef * MAX_RISE_PER_STEP_M)
                if (weather.weather.value?.freezing == true) coldClimbM += credited
                climbRef = altSmooth; stepsSinceRef = 0
            }
            altSmooth <= climbRef - CLIMB_STEP_M -> { climbRef = altSmooth; stepsSinceRef = 0 }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    /** 47 s still = paused, 3 min = red-light notice (continue or end), 4.5 min = walk ends, like at an intersection. */
    private suspend fun kotlinx.coroutines.CoroutineScope.stillnessLoop() {
        while (isActive) {
            delay(1_000)
            val w = walk ?: continue
            val idle = System.currentTimeMillis() - lastStepMs
            status.value = if (idle >= AutoWalk.PAUSE_MS) WalkStatus.Paused(mode, w.startEpochMs, w.steps, idle)
                else WalkStatus.Walking(mode, w.startEpochMs, w.steps, gpsOn)
            when {
                idle >= AutoWalk.END_MS -> { stopWalk(); return }
                idle >= AutoWalk.RED_LIGHT_MS && !redLightShown -> { redLightShown = true; notify(redLightNotification()) }
                idle < AutoWalk.PAUSE_MS && redLightShown -> { redLightShown = false; notify(notification("Walk in progress")) }
            }
        }
    }

    private suspend fun kotlinx.coroutines.CoroutineScope.windowLoop() {
        while (isActive) {
            delay(WINDOW_MS)
            val now = System.currentTimeMillis()
            val gpsCheck = gps.check(now)
            val source = when {
                tor.isConnected -> StepSource.ONION   // the server only honours this for requests that really arrive over Tor
                gpsCheck.speedKmh != null -> StepSource.ACTIVE_GPS
                else -> StepSource.ACTIVE_SENSOR   // dead zone / no location
            }
            val w = walk ?: continue
            val steps = reader.recordDelta(source, w.id)
            // Hidden Peaks: on a freezing walk every step climbs a virtual 10% mountain trail; real hills
            // (barometer, in onPressure) add on top. Flat-country walkers can still reach Everest.
            if (steps > 0 && weather.weather.value?.freezing == true) coldClimbM += steps * VIRTUAL_RISE_PER_STEP_M
            val verdict = verifier.score(
                SensorWindow(
                    steps.toInt(), WINDOW_MS / 1000.0,
                    accel.toFloatArray(), gx.toFloatArray(), gy.toFloatArray(), gz.toFloatArray(),
                ),
                gpsCheck,
            )
            accel.clear(); gx.clear(); gy.clear(); gz.clear()
            if (steps > 0) {
                verdictSum += verdict.score; verdictCount++
                stepDao.setLatestVerdict(w.id, verdict.score)
            }

            walk = w.copy(
                steps = w.steps + steps,
                distanceM = gps.totalDistanceM,
                verdict = if (verdictCount == 0) 1f else (verdictSum / verdictCount).toFloat(),
                torUsed = w.torUsed || tor.isConnected,
                coldClimbM = coldClimbM,
                minTempF = listOfNotNull(w.minTempF, weather.weather.value?.tempF).minOrNull(),
            ).also { walkDao.update(it) }
        }
    }

    private fun startSnowflake() {
        lifecycleScope.launch {
            snowflake.events.collect { ev ->
                when (ev) {
                    is SnowflakeEvent.Progress -> walk = walk?.copy(snowflakeBytes = ev.bytes, snowflakeMinutes = ev.minutes)
                    SnowflakeEvent.SoftCapReached -> notify(capNotification())
                    SnowflakeEvent.HardCapReached -> notify(notification("Snowflake paused: cap reached. Walk still counting."))
                }
            }
        }
        lifecycleScope.launch { snowflake.start() }
    }

    private fun stopWalk() {
        tick?.cancel()
        watchdog?.cancel()
        sensorManager.unregisterListener(this)
        fused.removeLocationUpdates(locationCallback)
        snowflake.stop()
        lifecycleScope.launch {
            walk?.let { reader.recordDelta(StepSource.ACTIVE_SENSOR, it.id); walkDao.update(it.copy(endEpochMs = System.currentTimeMillis())) }
            walk = null
            isRunning = false
            status.value = WalkStatus.Idle
            SyncWorker.syncSoon(this@WalkService)
            ServiceCompat.stopForeground(this@WalkService, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    override fun onDestroy() {
        isRunning = false
        status.value = WalkStatus.Idle
        sensorManager.unregisterListener(this)
        super.onDestroy()
    }

    // --- notifications ---

    private fun ensureChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Active walk", NotificationManager.IMPORTANCE_LOW))
        }
    }

    private fun redLightNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentTitle("Stopped for 3 min. Red light?")
            .setContentText("The walk ends at 4:30 still unless you keep going.")
            .setOngoing(true)
            .addAction(0, "Continue walk", pi(ACTION_CONTINUE, 4))
            .addAction(0, "End walk", pi(ACTION_STOP, 1))
            .build()

    private fun notification(text: String): Notification {
        ensureChannel()
        val title = when (mode) {
            WalkMode.ACTIVE -> "VeilWalker walk"
            WalkMode.ONION -> "Onion Walk · via Tor"
            WalkMode.SNOWFLAKE -> "Snowflake Walk · helping people reach Tor"
        }
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .addAction(0, "End walk", pi(ACTION_STOP, 1))
            .build()
    }

    private fun capNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentTitle("Snowflake hosted 50 MB")
            .setContentText("Keep hosting while you walk, up to 150 MB?")
            .setOngoing(true)
            .addAction(0, "Walk to 150 MB", pi(ACTION_SNOWFLAKE_EXTEND, 2))
            .addAction(0, "Stop hosting", pi(ACTION_SNOWFLAKE_STOP, 3))
            .build()

    private fun notify(n: Notification) =
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, n)

    private fun pi(action: String, code: Int) = PendingIntent.getService(
        this, code, Intent(this, WalkService::class.java).setAction(action),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    companion object {
        @Volatile var isRunning = false
            private set

        private const val WINDOW_MS = 10_000L
        private const val CLIMB_STEP_M = 3.0          // hysteresis: ignore barometer jitter below this
        private const val MAX_RISE_PER_STEP_M = 0.25  // steep stairs are ~0.18 m per step
        private const val VIRTUAL_RISE_PER_STEP_M = 0.07  // a 10% trail at a 0.7 m stride: Everest = ~126K cold steps
        private const val NOTIF_ID = 42
        private const val CHANNEL = "walk"
        private const val ACTION_STOP = "org.trailbound.walk.STOP"
        private const val ACTION_AUTO = "org.trailbound.walk.AUTO"
        private const val ACTION_CONTINUE = "org.trailbound.walk.CONTINUE"
        private const val ACTION_FOREGROUND = "org.trailbound.walk.FOREGROUND"
        private const val ACTION_SNOWFLAKE_EXTEND = "org.trailbound.walk.SNOWFLAKE_EXTEND"
        private const val ACTION_SNOWFLAKE_STOP = "org.trailbound.walk.SNOWFLAKE_STOP"

        /** Live walk state for the UI. */
        val status = MutableStateFlow<WalkStatus>(WalkStatus.Idle)

        /** Manual start from the app (foreground, so GPS is available). Mode follows the Tor/Snowflake settings. */
        fun startIntent(ctx: Context) = Intent(ctx, WalkService::class.java)

        /** Started by activity recognition; must confirm 27 s of steps before it's a walk. */
        fun autoIntent(ctx: Context) = Intent(ctx, WalkService::class.java).setAction(ACTION_AUTO)

        /** Sent when the app comes to the foreground so an auto-started walk can add GPS. */
        fun foregroundIntent(ctx: Context) = Intent(ctx, WalkService::class.java).setAction(ACTION_FOREGROUND)
    }
}
