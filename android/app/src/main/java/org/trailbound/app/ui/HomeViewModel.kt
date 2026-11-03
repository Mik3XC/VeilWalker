package org.trailbound.app.ui

import android.content.Context
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.trailbound.core.achievements.AchievementRepository
import org.trailbound.core.data.dao.StepDao
import org.trailbound.core.identity.IdentityStore
import org.trailbound.core.ledger.LedgerRepository
import org.trailbound.core.net.TorManager
import org.trailbound.core.net.TorState
import org.trailbound.core.route.RouteProgress
import org.trailbound.core.route.RouteRepository
import org.trailbound.core.snowflake.SnowflakeController
import org.trailbound.core.steps.AutoWalk
import org.trailbound.core.net.Weather
import org.trailbound.core.net.WeatherRepository
import org.trailbound.core.data.dao.WalkDao
import org.trailbound.core.steps.WalkService
import org.trailbound.core.steps.WalkStatus
import javax.inject.Inject

@HiltViewModel
class HomeViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    stepDao: StepDao,
    ledger: LedgerRepository,
    private val tor: TorManager,
    identity: IdentityStore,
    routes: RouteRepository,
    achievements: AchievementRepository,
    profile: ProfileStore,
    private val snowflake: SnowflakeController,
    private val weatherRepo: WeatherRepository,
    walkDao: WalkDao,
) : ViewModel() {

    private fun <T> Flow<T>.state(initial: T) = stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initial)

    /** True lifetime step count, exactly what the hardware counted. Multipliers only ever affect points. */
    val lifetimeSteps: StateFlow<Long> = stepDao.observeTotalSteps().map { it ?: 0 }.state(0)

    /** Today's true step count, for the brag card. */
    val todaySteps: StateFlow<Long> = stepDao.observeStepsForDay(java.time.LocalDate.now().toString()).map { it ?: 0 }.state(0)

    /** Today's distance: true steps x calibrated stride. */
    val todayKm: StateFlow<Double> = combine(todaySteps, routes.strideM) { s, stride -> RouteRepository.km(s, stride) }.state(0.0)

    val points: StateFlow<Long> = ledger.observeBalance().state(0)
    val torState: StateFlow<TorState> = tor.state
    val torEnabled: StateFlow<Boolean> = tor.enabled
    val snowflakeOn: StateFlow<Boolean> = snowflake.hostOnWalks
    /** False until the Snowflake proxy library ships; the toggle says "soon" instead of pretending. */
    val snowflakeReady: Boolean = snowflake.isAvailable
    val handle: StateFlow<String?> = identity.username
    val clan: StateFlow<String?> = identity.clan
    val avatar: StateFlow<Int> = profile.avatar
    val walk: StateFlow<WalkStatus> = WalkService.status
    val route: StateFlow<RouteProgress?> = routes.progress.map<RouteProgress, RouteProgress?> { it }.state(null)

    /** Smuggler grade for the brag card: LANDLUBBER, STOWAWAY ... KINGPIN. */
    val outlawRank: StateFlow<String> = achievements.board.map { it.outlawRank }.state("LANDLUBBER")

    /** "4/91 · BRONZE" for the badges link; also keeps achievements evaluating while the app is open. */
    val badges: StateFlow<String?> = achievements.board
        .map { b -> "${b.unlockedCount}/${b.all.size}" + if (b.frost.name != "NONE") " · ${b.frost.title}" else "" }
        .state(null)

    fun toggleTor() {
        val on = !tor.enabled.value
        tor.setEnabled(on)
        if (on) viewModelScope.launch { tor.ensureStarted() }
    }

    fun toggleSnowflake() = snowflake.setHostOnWalks(!snowflake.hostOnWalks.value)

    /** Permissions just granted: (re)register hands-free walk detection. */
    fun enableAutoWalk() = AutoWalk.register(context)

    fun startWalkNow() {
        ContextCompat.startForegroundService(context, WalkService.startIntent(context))
    }

    /** App came to the foreground: let an auto-started walk add GPS. */
    fun onForeground() {
        if (WalkService.isRunning) context.startService(WalkService.foregroundIntent(context))
        viewModelScope.launch { weatherRepo.refresh() }
    }

    /** Outside temperature for the dashboard corner; a snowflake at 30°F or below. */
    val weather: StateFlow<Weather?> = weatherRepo.weather
    val weatherOn: StateFlow<Boolean> = weatherRepo.enabled

    fun enableWeather() {
        weatherRepo.setEnabled(true)
        viewModelScope.launch { weatherRepo.refresh(maxAgeMs = 0) }
    }

    /** Metres climbed on freezing walks: what reveals the Hidden Peaks. */
    val coldClimbM: StateFlow<Double> = walkDao.observeColdClimbM().state(0.0)
}
