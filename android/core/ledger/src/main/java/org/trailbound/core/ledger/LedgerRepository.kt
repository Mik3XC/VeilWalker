package org.trailbound.core.ledger

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import org.trailbound.core.data.VeilWalkerDatabase
import org.trailbound.core.data.dao.LedgerDao
import org.trailbound.core.data.entity.LedgerEntry
import org.trailbound.core.identity.Ed25519
import org.trailbound.core.identity.hexToBytes
import java.nio.ByteBuffer
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Client copy of the server-authoritative ledger. The client never mints. It appends entries the server
 * returns after checking each one links to the previous hash and carries a valid server signature, so the
 * phone holds an independently verifiable chain. If the server's database is ever lost, these chains are
 * enough to rebuild every balance (nobody can forge the server signature to inflate theirs).
 */
@Singleton
class LedgerRepository @Inject constructor(
    private val dao: LedgerDao,
    private val db: VeilWalkerDatabase,
) {

    fun observeBalance(): Flow<Long> = dao.observeBalanceMilli().map { it / 1000 }

    suspend fun headSeq(): Long = dao.head()?.seq ?: 0

    suspend fun appendFromServer(e: LedgerEntry) {
        val head = dao.head()
        val expectedPrev = head?.entryHash ?: GENESIS
        require(head == null || e.seq == head.seq + 1) { "ledger gap at seq ${e.seq}" }
        require(e.prevHash.contentEquals(expectedPrev)) { "ledger chain broken at seq ${e.seq}" }
        require(e.entryHash.contentEquals(hash(e))) { "ledger hash mismatch at seq ${e.seq}" }
        val sig = e.serverSig
        require(sig != null && Ed25519.verify(SERVER_PUBLIC_KEY, e.entryHash, sig)) {
            "bad server signature at seq ${e.seq}"
        }
        dao.append(e)
    }

    suspend fun verifyChain(): Boolean {
        var prev = GENESIS
        for (e in dao.all()) {
            if (!e.prevHash.contentEquals(prev) || !e.entryHash.contentEquals(hash(e))) return false
            val sig = e.serverSig ?: return false
            if (!Ed25519.verify(SERVER_PUBLIC_KEY, e.entryHash, sig)) return false
            prev = e.entryHash
        }
        return true
    }

    /** Wipes the local copy, for switching to a different identity (restore). The new account's chain is re-fetched. */
    fun resetForNewIdentity() = db.resetLedger()

    companion object {
        val GENESIS = ByteArray(32)

        /** Pinned public key of the production server's ledger signing key (SERVER_SIGNING_KEY_HEX on Railway). */
        val SERVER_PUBLIC_KEY = "fd0adaa84eb11df889b66391dd6c8982dcebd5a12a876aa2031d8de043d0171f".hexToBytes()

        /** Must match backend/src/ledger.rs byte for byte. */
        fun hash(e: LedgerEntry): ByteArray {
            val md = MessageDigest.getInstance("SHA-256")
            md.update(e.prevHash)
            md.update(ByteBuffer.allocate(8).putLong(e.seq).array())
            md.update(e.kind.toByteArray())
            md.update(ByteBuffer.allocate(8).putLong(e.amount).array())
            md.update(e.reasonCode.toByteArray())
            md.update(e.refId.toByteArray())
            md.update(ByteBuffer.allocate(8).putLong(e.tsEpochMs).array())
            return md.digest()
        }
    }
}
