package org.trailbound.core.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import org.trailbound.core.identity.IdentityStore
import org.trailbound.core.identity.toHex
import java.io.IOException
import java.security.MessageDigest
import java.security.SecureRandom
import javax.inject.Inject
import javax.inject.Singleton

class ApiException(val code: Int, message: String, val body: String = "") : IOException(message) {
    /** The server's machine-readable reason ({"error": "..."}), if it sent one. */
    val reason: String? get() = runCatching { JSONObject(body).getString("error") }.getOrNull()
}

/**
 * Signed requests to the VeilWalker API (see backend/src/auth.rs for the exact format). Goes over the
 * onion service when Tor is up, otherwise clearnet HTTPS. No cookies, no tokens: every request is signed.
 */
@Singleton
class ApiClient @Inject constructor(
    private val identity: IdentityStore,
    private val tor: TorManager,
) {
    private val random = SecureRandom()

    val viaOnion: Boolean get() = tor.isConnected

    suspend fun register() {
        call("POST", "/v1/register", body = ByteArray(0))
    }

    /** Returns the server's response JSON ({minted_milli, held_for_review, seq}). */
    suspend fun sync(summary: JSONObject): JSONObject =
        JSONObject(call("POST", "/v1/sync", body = summary.toString().toByteArray()))

    data class Me(val username: String?, val clan: String?, val avatar: Int)

    data class DayHistory(val day: String, val passive: Long, val sensor: Long, val gps: Long, val onion: Long)

    /** The account's permanent handle and clan tag (either may be null). */
    suspend fun me(): Me = JSONObject(call("GET", "/v1/me")).let { Me(it.nullableString("username"), it.nullableString("clan"), it.optInt("avatar")) }

    private fun JSONObject.nullableString(key: String): String? = if (isNull(key)) null else optString(key).ifEmpty { null }

    /** Clan calls return the new tag (null after leaving); errors carry reason invalid_tag/taken/in_clan/not_found/full. */
    suspend fun clanCreate(tag: String): String? = clanCall("/v1/clan", tag)
    suspend fun clanJoin(tag: String): String? = clanCall("/v1/clan/join", tag)
    suspend fun clanLeave(): String? = clanCall("/v1/clan/leave", "")

    private suspend fun clanCall(path: String, tag: String): String? =
        JSONObject(call("POST", path, body = JSONObject().put("tag", tag).toString().toByteArray()))
            .let { if (it.isNull("clan")) null else it.getString("clan") }

    /** Claims the permanent handle; throws ApiException with reason taken / already_claimed / invalid_* / reserved. */
    suspend fun claimUsername(name: String): String =
        JSONObject(call("POST", "/v1/username", body = JSONObject().put("username", name).toString().toByteArray()))
            .getString("username")

    /** A friend or squadmate as the server shows them: never more than handle, clan, avatar and weekly steps. */
    data class Person(val id: String, val handle: String?, val clan: String?, val avatar: Int, val weekSteps: Long)

    data class Squad(val clan: String?, val members: List<Person>, val weekTotal: Long)

    private fun people(a: JSONArray) = (0 until a.length()).map { i ->
        val o = a.getJSONObject(i)
        Person(o.getString("id"), o.nullableString("handle"), o.nullableString("clan"), o.optInt("avatar"), o.optLong("week_steps"))
    }

    suspend fun setAvatar(index: Int) {
        call("POST", "/v1/profile", body = JSONObject().put("avatar", index).toString().toByteArray())
    }

    /** Returns the new invite code. kind = "friend" (one use) or "clan" (10 uses). Errors: no_handle, no_clan. */
    suspend fun createInvite(kind: String): String =
        JSONObject(call("POST", "/v1/invites", body = JSONObject().put("kind", kind).toString().toByteArray())).getString("code")

    /** Returns (friend handle, clan joined or null). Errors: not_found, expired, own_invite. */
    suspend fun acceptInvite(code: String): Pair<String?, String?> =
        JSONObject(call("POST", "/v1/invites/accept", body = JSONObject().put("code", code).toString().toByteArray()))
            .let { it.nullableString("friend") to it.nullableString("joined_clan") }

    suspend fun friends(): List<Person> = people(JSONArray(call("GET", "/v1/friends")))

    suspend fun removeFriend(id: String) {
        call("POST", "/v1/friends/remove", body = JSONObject().put("id", id).toString().toByteArray())
    }

    suspend fun squad(): Squad = JSONObject(call("GET", "/v1/squad")).let {
        Squad(it.nullableString("clan"), people(it.getJSONArray("members")), it.optLong("week_total"))
    }

    /** Deletes the account's synced data on the server (Play account-deletion requirement). */
    suspend fun deleteAccount() {
        call("DELETE", "/v1/account", body = ByteArray(0))
    }

    /** The account's synced daily totals (oldest first), for rebuilding history after a restore. */
    suspend fun history(): List<DayHistory> = JSONArray(call("GET", "/v1/history")).let { a ->
        (0 until a.length()).map { i ->
            val o = a.getJSONObject(i)
            DayHistory(o.getString("day"), o.optLong("steps_passive"), o.optLong("steps_sensor"), o.optLong("steps_gps"), o.optLong("steps_onion"))
        }
    }

    suspend fun ledgerAfter(seq: Long): JSONArray =
        JSONArray(call("GET", "/v1/ledger", query = "after=$seq"))

    private suspend fun call(method: String, path: String, query: String? = null, body: ByteArray? = null): String =
        withContext(Dispatchers.IO) {
            // Tor on means onion only: bring it up, and if it won't connect, fail (callers retry later) rather than leak to clearnet.
            if (tor.enabled.value && !tor.ensureStarted()) throw IOException("Tor is on but not connected; not falling back to clearnet")
            val bytes = body ?: ByteArray(0)
            val ts = System.currentTimeMillis().toString()
            val nonce = ByteArray(16).also(random::nextBytes).toHex()
            val bodyHash = MessageDigest.getInstance("SHA-256").digest(bytes).toHex()
            val sig = identity.sign("$method\n$path\n$bodyHash\n$ts\n$nonce".toByteArray()).toHex()

            val base = if (tor.isConnected) TorManager.ONION_BASE_URL else TorManager.CLEARNET_BASE_URL
            val url = base + path + (query?.let { "?$it" } ?: "")
            val req = Request.Builder()
                .url(url)
                .header("x-tb-key", identity.ensureIdentity())
                .header("x-tb-ts", ts)
                .header("x-tb-nonce", nonce)
                .header("x-tb-sig", sig)
                .method(method, if (method == "GET") null else bytes.toRequestBody(JSON))
                .build()
            tor.httpClient().newCall(req).execute().use { res ->
                val text = res.body.string()
                if (!res.isSuccessful) throw ApiException(res.code, "$method $path -> ${res.code}", text)
                if (base == TorManager.ONION_BASE_URL) tor.markOnionOk()
                text
            }
        }

    private companion object {
        val JSON = "application/json".toMediaType()
    }
}
