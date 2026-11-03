package org.trailbound.app.ui

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.trailbound.core.identity.IdentityStore
import org.trailbound.core.net.ApiClient
import org.trailbound.core.net.ApiException
import javax.inject.Inject

data class SocialState(
    val friends: List<ApiClient.Person> = emptyList(),
    val squad: ApiClient.Squad? = null,
    val friendCode: String? = null,
    val squadCode: String? = null,
    val message: String? = null,
    val loading: Boolean = true,
)

@HiltViewModel
class SocialViewModel @Inject constructor(
    private val api: ApiClient,
    private val identity: IdentityStore,
    private val profile: ProfileStore,
) : ViewModel() {

    private val _state = MutableStateFlow(SocialState())
    val state: StateFlow<SocialState> = _state

    fun refresh() = run(loading = true) {
        api.setAvatar(profile.avatar.value)            // friends see the picture you chose
        val friends = api.friends()
        val squad = api.squad()
        identity.setClan(squad.clan)
        _state.value = _state.value.copy(friends = friends, squad = squad)
        null
    }

    fun newInvite(kind: String) = run {
        val code = api.createInvite(kind)
        _state.value = if (kind == "clan") _state.value.copy(squadCode = code) else _state.value.copy(friendCode = code)
        null
    }

    fun accept(code: String) = run {
        val (friend, clan) = api.acceptInvite(code)
        refresh()
        "You and @${friend ?: "?"} are friends" + (clan?.let { ". Joined [$it]." } ?: ".")
    }

    fun remove(p: ApiClient.Person) = run {
        api.removeFriend(p.id)
        refresh()
        "Removed @${p.handle}"
    }

    private fun run(loading: Boolean = false, block: suspend () -> String?) {
        if (loading) _state.value = _state.value.copy(loading = true)
        viewModelScope.launch {
            val msg = try {
                block()
            } catch (e: ApiException) {
                when (e.reason) {
                    "no_handle" -> "Claim a handle in @ account first."
                    "no_clan" -> "Join or create a clan first."
                    "not_found" -> "No invite with that code."
                    "expired" -> "That invite expired or was used up."
                    "own_invite" -> "That's your own invite."
                    else -> "Failed: ${e.message}"
                }
            } catch (e: Exception) {
                "Offline or Tor still connecting. Try again in a moment."
            }
            _state.value = _state.value.copy(message = msg ?: _state.value.message, loading = false)
        }
    }
}

private fun share(ctx: Context, code: String, squad: String?) {
    val text = if (squad != null) "Walk with my squad [$squad] on VeilWalker. Invite code: $code"
        else "Walk with me on VeilWalker, the step counter that doesn't watch you. Invite code: $code"
    ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), "Share invite"))
}

@Composable
private fun Section(title: String) {
    Text("// $title", color = MaterialTheme.colorScheme.secondary, modifier = Modifier.padding(top = 8.dp))
    HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.outline)
}

@Composable
private fun PersonRow(rank: Int?, p: ApiClient.Person, onRemove: (() -> Unit)?) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        AvatarArt(p.avatar.coerceIn(Avatars.indices), size = 5.sp)
        Column(Modifier.weight(1f).padding(start = 10.dp)) {
            Text(
                (rank?.let { "#$it " } ?: "") + (p.clan?.let { "[$it] " } ?: "") + (p.handle ?: "anon"),
                fontWeight = FontWeight.Bold,
            )
            Text("%,d steps this week".format(p.weekSteps), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        }
        if (onRemove != null) {
            Text("x", color = MaterialTheme.colorScheme.outline, modifier = Modifier.width(32.dp).veilClick(onClick = onRemove).padding(8.dp))
        }
    }
}

@Composable
fun SocialScreen(onBack: () -> Unit, vm: SocialViewModel = hiltViewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    var code by remember { mutableStateOf("") }
    val violet = MaterialTheme.colorScheme.primary
    LaunchedEffect(Unit) { vm.refresh() }

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text("Social", style = MaterialTheme.typography.headlineMedium)
        Text("Friends see your handle, clan, picture and weekly steps. Nothing else.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        state.message?.let { Text(it, color = violet) }

        Section("invite")
        VeilButton("New friend invite", { vm.newInvite("friend") }, glyph = "+")
        state.friendCode?.let { c ->
            Text(c, style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.secondary)
            VeilButton("Share invite", { share(ctx, c, null) }, glyph = ">")
        }
        OutlinedTextField(
            value = code,
            onValueChange = { code = it.uppercase().filter { ch -> ch.isLetterOrDigit() || ch == '-' }.take(12) },
            label = { Text("have a code? VW-XXXX-XXXX") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        VeilButton("Accept code", { vm.accept(code); code = "" }, enabled = code.length >= 11, glyph = "!")

        Section("friends (${state.friends.size})")
        if (state.loading) Text("loading…", color = MaterialTheme.colorScheme.outline)
        else if (state.friends.isEmpty()) Text("No friends yet. Share an invite.", color = MaterialTheme.colorScheme.outline)
        state.friends.forEach { PersonRow(null, it) { vm.remove(it) } }

        val squad = state.squad
        Section(squad?.clan?.let { "squad [$it]" } ?: "squad")
        if (squad?.clan == null) {
            Text("Not in a clan. Create or join one in @ account, or accept a squad invite.", color = MaterialTheme.colorScheme.outline)
        } else {
            Text("%,d steps this week together".format(squad.weekTotal), color = violet, fontWeight = FontWeight.Bold)
            squad.members.forEachIndexed { i, p -> PersonRow(i + 1, p, null) }
            VeilButton("New squad invite [${squad.clan}]", { vm.newInvite("clan") }, glyph = "+")
            state.squadCode?.let { c ->
                Text(c, style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.secondary)
                VeilButton("Share squad invite", { share(ctx, c, squad.clan) }, glyph = ">")
            }
        }

        VeilButton("Refresh", vm::refresh, glyph = "~")
        VeilButton("Back", onBack, glyph = "<")
    }
}
