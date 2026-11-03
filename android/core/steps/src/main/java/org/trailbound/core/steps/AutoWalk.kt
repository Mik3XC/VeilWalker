package org.trailbound.core.steps

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity

/**
 * Hands-free walks. Android's on-device activity recognition wakes us when the phone starts moving on foot;
 * WalkService then confirms with the step sensor (27 s of continuous steps) before anything counts as a walk.
 * The transition API keeps working while the app is closed, and its events are allowed to start a
 * foreground service from the background.
 */
object AutoWalk {
    const val CONFIRM_MS = 27_000L
    const val PAUSE_MS = 47_000L
    const val RED_LIGHT_MS = 180_000L
    const val END_MS = 270_000L

    private const val TAG = "VeilWalker/AutoWalk"

    fun register(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED
        ) return
        val transitions = listOf(DetectedActivity.WALKING, DetectedActivity.ON_FOOT, DetectedActivity.RUNNING).map {
            ActivityTransition.Builder().setActivityType(it).setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER).build()
        }
        runCatching {
            ActivityRecognition.getClient(context)
                .requestActivityTransitionUpdates(ActivityTransitionRequest(transitions), pendingIntent(context))
                .addOnFailureListener { Log.w(TAG, "transition registration failed", it) }
        }.onFailure { Log.w(TAG, "transition registration failed", it) }
    }

    private fun pendingIntent(context: Context) = PendingIntent.getBroadcast(
        context, 0, Intent(context, AutoWalkReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,   // mutable: Play services fills in the result
    )
}

class AutoWalkReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val result = ActivityTransitionResult.extractResult(intent) ?: return
        if (result.transitionEvents.any { it.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER } && !WalkService.isRunning) {
            runCatching { ContextCompat.startForegroundService(context, WalkService.autoIntent(context)) }
                .onFailure { Log.w("VeilWalker/AutoWalk", "could not start walk", it) }
        }
    }
}

/** Transition registrations don't survive a reboot or an app update; this puts them back. */
class AutoWalkBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            AutoWalk.register(context)
        }
    }
}
