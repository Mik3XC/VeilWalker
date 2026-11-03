package org.trailbound.core.ledger

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/** Syncs daily totals and pulls the signed ledger: hourly in the background, and right after each walk. */
@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted ctx: Context,
    @Assisted params: WorkerParameters,
    private val sync: SyncRepository,
) : CoroutineWorker(ctx, params) {

    override suspend fun doWork(): Result = try {
        sync.syncNow()
        Result.success()
    } catch (e: Exception) {
        Log.w("VeilWalker/Sync", "sync failed, will retry", e)
        Result.retry()
    }

    companion object {
        private val online = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

        fun schedule(context: Context) {
            val req = PeriodicWorkRequestBuilder<SyncWorker>(1, TimeUnit.HOURS).setConstraints(online).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork("sync", ExistingPeriodicWorkPolicy.KEEP, req)
        }

        fun syncSoon(context: Context) {
            val req = OneTimeWorkRequestBuilder<SyncWorker>()
                .setConstraints(online)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork("sync-now", ExistingWorkPolicy.APPEND_OR_REPLACE, req)   // run after any sync in progress instead of cancelling it
        }
    }
}
