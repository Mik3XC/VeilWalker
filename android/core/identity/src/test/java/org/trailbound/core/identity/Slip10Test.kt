package org.trailbound.core.identity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Slip10Test {

    // SLIP-0010 official Ed25519 test vector 1 (seed 000102030405060708090a0b0c0d0e0f).
    private val seed = "000102030405060708090a0b0c0d0e0f".hexToBytes()

    @Test fun masterKeyMatchesSpec() {
        assertEquals(
            "2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7",
            Slip10.derive(seed, intArrayOf()).toHex(),
        )
    }

    @Test fun hardenedChildMatchesSpec() {
        // m/0'
        assertEquals(
            "68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3",
            Slip10.derive(seed, intArrayOf(0)).toHex(),
        )
    }

    @Test fun signatureRoundTrips() {
        val priv = Slip10.derive(seed)
        val pub = Ed25519.publicKey(priv)
        val sig = Ed25519.sign(priv, "hello".toByteArray())
        assertTrue(Ed25519.verify(pub, "hello".toByteArray(), sig))
        assertFalse(Ed25519.verify(pub, "hellp".toByteArray(), sig))
    }
}
