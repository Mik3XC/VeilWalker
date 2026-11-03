package org.trailbound.app.ui

import org.trailbound.core.net.WeatherRepository
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.trailbound.core.identity.IdentityStore
import org.trailbound.core.ledger.LedgerRepository
import org.trailbound.core.ledger.SyncRepository
import org.trailbound.core.net.ApiClient
import org.trailbound.core.net.ApiException
import javax.inject.Inject

data class AccountState(
    val publicKey: String? = null,
    val username: String? = null,
    val clan: String? = null,
    val words: List<String>? = null,   // only while revealed
    val syncStatus: String? = null,
    val busy: Boolean = false,
)

@HiltViewModel
class AccountViewModel @Inject constructor(
    private val identity: IdentityStore,
    private val ledger: LedgerRepository,
    private val sync: SyncRepository,
    private val api: ApiClient,
    private val profile: ProfileStore,
    private val weather: WeatherRepository,
) : ViewModel() {

    val weatherOn: StateFlow<Boolean> = weather.enabled

    fun toggleWeather() {
        val on = !weather.enabled.value
        weather.setEnabled(on)
        if (on) viewModelScope.launch { weather.refresh(maxAgeMs = 0) }
    }

    val avatar: StateFlow<Int> = profile.avatar

    fun pickAvatar(i: Int) {
        profile.setAvatar(i)
        viewModelScope.launch { runCatching { if (identity.registered) api.setAvatar(i) } }   // best effort; Social re-syncs
    }

    private val _state = MutableStateFlow(
        AccountState(publicKey = identity.ensureIdentity(), username = identity.username.value, clan = identity.clan.value)
    )
    val state: StateFlow<AccountState> = _state

    fun toggleWords() {
        _state.value = _state.value.copy(words = if (_state.value.words == null) identity.words() else null)
    }

    fun syncNow() = launchBusy {
        val r = sync.syncNow()
        val chainOk = ledger.verifyChain()
        "Synced ${r.daysSent} day(s) via ${if (r.viaOnion) "onion" else "clearnet"} · " +
            "+${r.mintedMilli / 1000.0} pts · ${r.ledgerPulled} new ledger entries · chain ${if (chainOk) "verified" else "BROKEN"}" +
            if (r.held > 0) " · ${r.held} day(s) held for review" else ""
    }

    fun claim(name: String) = launchBusy {
        try {
            if (!identity.registered) sync.syncNow()   // registers the account first
            val claimed = api.claimUsername(name.trim())
            identity.setUsername(claimed)
            _state.value = _state.value.copy(username = claimed)
            "@$claimed is yours. Forever."
        } catch (e: ApiException) {
            when (e.reason) {
                "taken" -> "@${name.trim()} is taken. Pick another."
                "already_claimed" -> "This account already has a handle."
                "invalid_length" -> "5 to 20 characters."
                "invalid_characters" -> "Letters, numbers and _ only."
                "reserved" -> "That handle is reserved."
                else -> "Failed: ${e.message}"
            }
        }
    }

    fun clanCreate(tag: String) = clan { api.clanCreate(tag) }
    fun clanJoin(tag: String) = clan { api.clanJoin(tag) }
    fun clanLeave() = clan { api.clanLeave() }

    private fun clan(op: suspend () -> String?) = launchBusy {
        try {
            if (!identity.registered) sync.syncNow()
            val tag = op()
            identity.setClan(tag)
            _state.value = _state.value.copy(clan = tag)
            tag?.let { "You're [$it] now." } ?: "Left the clan."
        } catch (e: ApiException) {
            when (e.reason) {
                "invalid_tag" -> "Tags are 2–4 letters or digits."
                "taken" -> "That tag exists. Join it instead?"
                "not_found" -> "No clan with that tag. Create it?"
                "full" -> "That clan is full (50)."
                "in_clan" -> "Leave your current clan first."
                else -> "Failed: ${e.message}"
            }
        }
    }

    /**
     * Deletes the server-side data, then wipes everything on this phone (Android kills the app as it clears).
     * The handle stays reserved forever so nobody can take over the name.
     */
    fun deleteAccount(context: android.content.Context) = launchBusy {
        if (identity.registered) api.deleteAccount()
        context.getSystemService(android.app.ActivityManager::class.java).clearApplicationUserData()
        "Deleted."
    }

    fun restore(phrase: String) = launchBusy {
        val pub = identity.restore(phrase)
        ledger.resetForNewIdentity()
        _state.value = _state.value.copy(publicKey = pub, words = null, username = null)
        val r = sync.syncNow()
        profile.setAvatar(sync.lastAvatar.coerceIn(Avatars.indices))
        _state.value = _state.value.copy(username = identity.username.value, clan = identity.clan.value)
        "Restored account ${pub.take(8)}… · pulled ${r.ledgerPulled} ledger entries"
    }

    private fun launchBusy(block: suspend () -> String) {
        _state.value = _state.value.copy(busy = true, syncStatus = null)
        viewModelScope.launch {
            val msg = runCatching { withContext(Dispatchers.IO) { block() } }
                .getOrElse { "Failed: ${it.message}" }
            _state.value = _state.value.copy(busy = false, syncStatus = msg)
        }
    }
}
