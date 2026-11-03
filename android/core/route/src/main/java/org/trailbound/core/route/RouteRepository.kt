package org.trailbound.core.route

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import org.trailbound.core.data.dao.StepDao
import org.trailbound.core.data.dao.WalkDao
import javax.inject.Inject
import javax.inject.Singleton

data class RouteProgress(val route: Route, val position: Route.Position, val strideM: Double)

/**
 * Route progress = all counted steps x the walker's stride. Stride is calibrated from their own GPS-measured
 * walks (distance / steps), so short- and long-legged walkers both move at their real pace.
 */
@Singleton
class RouteRepository @Inject constructor(steps: StepDao, walks: WalkDao) {

    val route: Route = NorthStarRoute

    /** The walker's calibrated stride in metres; km anywhere in the app = true steps x this. */
    val strideM: Flow<Double> = walks.observeGpsCalibration().map { strideFrom(it?.distanceM, it?.steps) }

    val progress: Flow<RouteProgress> = combine(steps.observeTotalSteps(), walks.observeGpsCalibration()) { total, cal ->
        val stride = strideFrom(cal?.distanceM, cal?.steps)
        RouteProgress(route, route.positionAt((total ?: 0) * stride), stride)
    }

    companion object {
        const val DEFAULT_STRIDE_M = 0.75

        /** Needs ~500 GPS-measured steps before trusting the user's own stride; clamped to human range. */
        fun km(steps: Long, strideM: Double): Double = steps * strideM / 1000.0

        fun strideFrom(distanceM: Double?, steps: Long?): Double =
            if (distanceM == null || steps == null || steps < 500) DEFAULT_STRIDE_M
            else (distanceM / steps).coerceIn(0.5, 1.0)
    }
}
