package org.trailbound.core.identity

import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * SLIP-0010 Ed25519 derivation from a BIP39 seed, so the same 24 words give the same account key on
 * Android, iOS or anything else that implements SLIP-0010. All path segments are hardened (required for Ed25519).
 */
object Slip10 {
    /** m/44'/9077'/0'/0'. 9077 is an unregistered coin type picked for VeilWalker; changing it changes every account. */
    val ACCOUNT_PATH = intArrayOf(44, 9077, 0, 0)

    fun derive(seed: ByteArray, path: IntArray = ACCOUNT_PATH): ByteArray {
        var i = hmac("ed25519 seed".toByteArray(), seed)
        var key = i.copyOfRange(0, 32)
        var chain = i.copyOfRange(32, 64)
        for (index in path) {
            val hardened = index.toLong() or 0x80000000L
            val data = ByteArray(1 + 32 + 4)
            key.copyInto(data, 1)
            for (b in 0 until 4) data[33 + b] = (hardened shr (24 - 8 * b)).toByte()
            i = hmac(chain, data)
            key = i.copyOfRange(0, 32)
            chain = i.copyOfRange(32, 64)
        }
        return key
    }

    private fun hmac(key: ByteArray, data: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA512").apply { init(SecretKeySpec(key, "HmacSHA512")) }.doFinal(data)
}

object Ed25519 {
    fun publicKey(privateKey: ByteArray): ByteArray = Ed25519PrivateKeyParameters(privateKey, 0).generatePublicKey().encoded

    fun sign(privateKey: ByteArray, message: ByteArray): ByteArray =
        Ed25519Signer().run {
            init(true, Ed25519PrivateKeyParameters(privateKey, 0))
            update(message, 0, message.size)
            generateSignature()
        }

    fun verify(publicKey: ByteArray, message: ByteArray, signature: ByteArray): Boolean =
        runCatching {
            Ed25519Signer().run {
                init(false, Ed25519PublicKeyParameters(publicKey, 0))
                update(message, 0, message.size)
                verifySignature(signature)
            }
        }.getOrDefault(false)
}

fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

fun String.hexToBytes(): ByteArray = chunked(2).map { it.toInt(16).toByte() }.toByteArray()
