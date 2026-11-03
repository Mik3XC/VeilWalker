package org.trailbound.app

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.trailbound.app.ui.Consent
import org.trailbound.core.ledger.SyncWorker
import org.trailbound.core.net.TorManager
import org.trailbound.core.steps.AutoWalk
import org.trailbound.core.steps.PassiveStepWorker
import javax.inject.Inject

@HiltAndroidApp
class VeilWalkerApp : Application(), Configuration.Provider {

    @Inject lateinit var workerFactory: HiltWorkerFactory
    @Inject lateinit var tor: TorManager

    /** Lives as long as the process: used for warming Tor up at launch. */
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setWorkerFactory(workerFactory).build()

    override fun onCreate() {
        super.onCreate()
        if (Consent.given(this)) startBackgroundWork()
    }

    /** Nothing is collected until health-data consent is given; then this runs every launch. */
    fun startBackgroundWork() {
        PassiveStepWorker.schedule(this)
        SyncWorker.schedule(this)
        AutoWalk.register(this)
        if (tor.enabled.value) appScope.launch { tor.ensureStarted() }
    }
}
