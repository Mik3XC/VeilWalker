package org.trailbound.core.identity

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import cash.z.ecc.android.bip39.Mnemonics
import cash.z.ecc.android.bip39.toSeed
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.inject.Inject
import javax.inject.Singleton

/**
 * The account is the 24-word phrase. Its entropy is stored encrypted under a non-exportable Android Keystore
 * AES key; the Ed25519 signing key is re-derived in memory when needed (Keystore can't hold a key derived
 * from our own seed, and its native Ed25519 needs API 33+).
 */
@Singleton
class IdentityStore @Inject constructor(@ApplicationContext private val context: Context) {

    private val prefs = context.getSharedPreferences("identity", Context.MODE_PRIVATE)
    private val _publicKey = MutableStateFlow(loadPublicKey())
    /** Hex public key = the account ID. Null until an identity exists. */
    val publicKey: StateFlow<String?> = _publicKey

    val hasIdentity: Boolean get() = prefs.contains(KEY_ENTROPY)

    private val _username = MutableStateFlow(prefs.getString(KEY_USERNAME, null))
    /** Permanent handle once claimed (the server is the source of truth; this is a cache). */
    val username: StateFlow<String?> = _username

    fun setUsername(name: String) {
        prefs.edit().putString(KEY_USERNAME, name).apply()
        _username.value = name
    }

    private val _clan = MutableStateFlow(prefs.getString(KEY_CLAN, null))
    /** Clan tag shown before the handle, e.g. [ROX] HashCat. Cache of the server's value; null = no clan. */
    val clan: StateFlow<String?> = _clan

    fun setClan(tag: String?) {
        prefs.edit().putString(KEY_CLAN, tag).apply()
        _clan.value = tag
    }

    /** Creates a fresh 24-word identity if none exists yet. Returns the public key hex. */
    @Synchronized
    fun ensureIdentity(): String {
        _publicKey.value?.let { return it }
        val code = Mnemonics.MnemonicCode(Mnemonics.WordCount.COUNT_24)
        return save(code)
    }

    /** Replaces the identity with one restored from [phrase]. Throws if the phrase isn't a valid BIP39 phrase. */
    @Synchronized
    fun restore(phrase: String): String {
        val code = Mnemonics.MnemonicCode(phrase.trim().lowercase().split(Regex("\\s+")).joinToString(" "))
        code.validate()
        return save(code)
    }

    /** The recovery phrase, for showing to the user. */
    fun words(): List<String> = mnemonic().words.map { String(it) }

    /** Signs [message] with the account key; the private key never leaves this call. */
    fun sign(message: ByteArray): ByteArray {
        val priv = privateKey()
        return try { Ed25519.sign(priv, message) } finally { priv.fill(0) }
    }

    private fun mnemonic(): Mnemonics.MnemonicCode {
        val entropy = decrypt(prefs.getString(KEY_ENTROPY, null) ?: error("no identity"))
        return Mnemonics.MnemonicCode(entropy)
    }

    private fun privateKey(): ByteArray {
        val seed = mnemonic().toSeed()
        return try { Slip10.derive(seed) } finally { seed.fill(0) }
    }

    private fun save(code: Mnemonics.MnemonicCode): String {
        val seed = code.toSeed()
        val priv = Slip10.derive(seed)
        val pub = Ed25519.publicKey(priv).toHex()
        seed.fill(0); priv.fill(0)
        prefs.edit()
            .putString(KEY_ENTROPY, encrypt(code.toEntropy()))
            .putString(KEY_PUBLIC, pub)
            .putBoolean(KEY_REGISTERED, false)
            .remove(KEY_USERNAME)
            .remove(KEY_CLAN)
            .commit()
        _publicKey.value = pub
        _username.value = null
        _clan.value = null
        return pub
    }

    var registered: Boolean
        get() = prefs.getBoolean(KEY_REGISTERED, false)
        set(v) { prefs.edit().putBoolean(KEY_REGISTERED, v).apply() }

    private fun loadPublicKey(): String? = prefs.getString(KEY_PUBLIC, null)

    // --- Keystore wrapping ---

    private fun keystoreKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEYSTORE_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(
                KeyGenParameterSpec.Builder(KEYSTORE_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
        }.generateKey()
    }

    private fun encrypt(plain: ByteArray): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, keystoreKey()) }
        return c.iv.toHex() + ":" + c.doFinal(plain).toHex()
    }

    private fun decrypt(stored: String): ByteArray {
        val (iv, ct) = stored.split(":")
        val c = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, keystoreKey(), GCMParameterSpec(128, iv.hexToBytes()))
        }
        return c.doFinal(ct.hexToBytes())
    }

    private companion object {
        const val KEYSTORE_ALIAS = "veilwalker-identity"
        const val KEY_ENTROPY = "entropy"
        const val KEY_PUBLIC = "pubkey"
        const val KEY_REGISTERED = "registered"
        const val KEY_USERNAME = "username"
        const val KEY_CLAN = "clan"
    }
}
