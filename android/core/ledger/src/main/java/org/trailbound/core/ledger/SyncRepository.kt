package org.trailbound.core.ledger

import android.util.Log
import org.json.JSONObject
import org.trailbound.core.data.dao.StepDao
import org.trailbound.core.data.entity.LedgerEntry
import org.trailbound.core.data.entity.StepInterval
import org.trailbound.core.data.entity.StepSource
import org.trailbound.core.identity.IdentityStore
import org.trailbound.core.identity.hexToBytes
import org.trailbound.core.identity.toHex
import org.trailbound.core.net.ApiClient
import org.trailbound.core.net.ApiException
import java.time.LocalDate
import javax.inject.Inject
import javax.inject.Singleton

/** A day's step totals by trust tier, as sent to the server. Only these numbers leave the phone. */
data class DayTotals(val day: String, val passive: Long, val sensor: Long, val gps: Long, val onion: Long, val verdict: Float) {
    /** What the device signs as its own record of the summary (stored by the server alongside the request). */
    fun canonical(): String = "$day|$passive|$sensor|$gps|$onion|$verdict"

    companion object {
        /** Verdict is the step-weighted average over walk intervals; passive steps carry no verdict. */
        fun from(day: String, intervals: List<StepInterval>): DayTotals {
            fun sum(vararg s: StepSource) = intervals.filter { it.source in s }.sumOf { it.steps }
            val walked = intervals.filter { it.source != StepSource.PASSIVE && it.source != StepSource.HEALTH_CONNECT }
            val walkedSteps = walked.sumOf { it.steps }
            val verdict = if (walkedSteps == 0L) 1f
                else (walked.sumOf { it.steps * it.verdict.toDouble() } / walkedSteps).toFloat()
            return DayTotals(
                day = day,
                passive = sum(StepSource.PASSIVE, StepSource.HEALTH_CONNECT),
                sensor = sum(StepSource.ACTIVE_SENSOR),
                gps = sum(StepSource.ACTIVE_GPS),
                onion = sum(StepSource.ONION),
                verdict = verdict,
            )
        }
    }
}

data class SyncResult(val daysSent: Int, val mintedMilli: Long, val held: Int, val ledgerPulled: Int, val viaOnion: Boolean)

@Singleton
class SyncRepository @Inject constructor(
    private val identity: IdentityStore,
    private val api: ApiClient,
    private val steps: StepDao,
    private val ledger: LedgerRepository,
) {
    suspend fun syncNow(): SyncResult {
        identity.ensureIdentity()
        if (!identity.registered) {
            api.register()
            identity.registered = true
        }
        // The server is the source of truth for handle and clan (restores, joins from another device).
        val me = api.me()
        me.username?.let(identity::setUsername)
        identity.setClan(me.clan)
        lastAvatar = me.avatar

        // After a restore or on a new phone, local history is missing or partial: top it up from the server's
        // daily totals so lifetime steps, route progress and badges come back. Idempotent; once per launch.
        if (!historyChecked) { topUpHistory(); historyChecked = true }

        var minted = 0L
        var held = 0
        val days = steps.daysSince(LocalDate.now().minusDays(SYNC_WINDOW_DAYS).toString())
        for (day in days) {
            val totals = DayTotals.from(day, steps.intervalsForDay(day))
            val body = JSONObject()
                .put("day", day)
                .put("steps_passive", totals.passive)
                .put("steps_sensor", totals.sensor)
                .put("steps_gps", totals.gps)
                .put("steps_onion", totals.onion)
                .put("verdict", totals.verdict.toDouble())
                .put("summary_sig", identity.sign(totals.canonical().toByteArray()).toHex())
            try {
                val res = api.sync(body)
                minted += res.optLong("minted_milli")
                if (res.optBoolean("held_for_review")) held++
            } catch (e: ApiException) {
                // 409: totals didn't grow since the last sync of this day. Nothing new to mint; not an error.
                if (e.code != 409) throw e
            }
        }

        val pulled = pullLedger()
        val result = SyncResult(days.size, minted, held, pulled, api.viaOnion)
        Log.i(TAG, "sync: $result")
        return result
    }

    /** Server's avatar index from the last sync, so a restore can bring the profile picture back. */
    @Volatile var lastAvatar: Int = 0
        private set

    @Volatile private var historyChecked = false

    private suspend fun topUpHistory() {
        var added = 0L
        for (d in api.history()) {
            val local = steps.intervalsForDay(d.day).groupBy { it.source }.mapValues { e -> e.value.sumOf { it.steps } }
            val t = java.time.LocalDate.parse(d.day).atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
            fun missing(src: StepSource, server: Long, vararg also: StepSource) =
                server - (local[src] ?: 0) - also.sumOf { local[it] ?: 0 }
            listOf(
                StepSource.PASSIVE to missing(StepSource.PASSIVE, d.passive, StepSource.HEALTH_CONNECT),
                StepSource.ACTIVE_SENSOR to missing(StepSource.ACTIVE_SENSOR, d.sensor),
                StepSource.ACTIVE_GPS to missing(StepSource.ACTIVE_GPS, d.gps),
                StepSource.ONION to missing(StepSource.ONION, d.onion),
            ).filter { it.second > 0 }.forEach { (src, n) ->
                // Timestamped at local midnight; syncs back as the same totals, so nothing is minted twice.
                steps.insertInterval(StepInterval(day = d.day, startEpochMs = t, endEpochMs = t, steps = n, source = src))
                added += n
            }
        }
        if (added > 0) Log.i(TAG, "restored $added steps of history from the server")
    }

    /** Fetches and verifies every new signed entry; appendFromServer rejects anything that doesn't chain or verify. */
    private suspend fun pullLedger(): Int {
        var count = 0
        while (true) {
            val page = api.ledgerAfter(ledger.headSeq())
            if (page.length() == 0) return count
            for (i in 0 until page.length()) {
                val o = page.getJSONObject(i)
                ledger.appendFromServer(
                    LedgerEntry(
                        seq = o.getLong("seq"),
                        kind = o.getString("kind"),
                        amount = o.getLong("amount"),
                        reasonCode = o.getString("reason_code"),
                        refId = o.getString("ref_id"),
                        tsEpochMs = o.getLong("ts_ms"),
                        prevHash = o.getString("prev_hash").hexToBytes(),
                        entryHash = o.getString("entry_hash").hexToBytes(),
                        clientSig = null,
                        serverSig = o.getString("server_sig").hexToBytes(),
                    )
                )
                count++
            }
        }
    }

    private companion object {
        const val TAG = "VeilWalker/Sync"
        /** The server only accepts days up to 7 back. */
        const val SYNC_WINDOW_DAYS = 6L
    }
}
