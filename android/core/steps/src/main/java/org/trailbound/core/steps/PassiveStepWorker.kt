package org.trailbound.core.steps

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import org.trailbound.core.data.dao.TraceDao
import org.trailbound.core.data.entity.StepSource
import java.util.concurrent.TimeUnit

/**
 * Passive all-day counting with no foreground service. Doze or Samsung "sleeping apps" may delay
 * runs; that's fine, because the hardware counter accumulates and the next run catches up.
 */
@HiltWorker
class PassiveStepWorker @AssistedInject constructor(
    @Assisted ctx: Context,
    @Assisted params: WorkerParameters,
    private val reader: StepCounterReader,
    private val traceDao: TraceDao,
) : CoroutineWorker(ctx, params) {

    override suspend fun doWork(): Result {
        // While a walk is running, WalkService owns the counter and records those steps at the higher rate.
        if (!WalkService.isRunning) reader.recordDelta(StepSource.PASSIVE)
        traceDao.purgeOlderThan(System.currentTimeMillis() - TimeUnit.DAYS.toMillis(30))
        return Result.success()
    }

    companion object {
        private const val NAME = "passive-steps"

        fun schedule(context: Context) {
            val req = PeriodicWorkRequestBuilder<PassiveStepWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, req)
        }
    }
}
