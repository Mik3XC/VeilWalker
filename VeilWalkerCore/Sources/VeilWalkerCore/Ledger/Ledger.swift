import CryptoKit
import Foundation

/// One server-signed entry of the account's points ledger. Amounts are milli-points.
public struct LedgerEntry: Equatable, Sendable {
    public let seq: Int64
    public let kind: String          // earn | redeem | adjust (no expire: points are lifetime)
    public let amount: Int64
    public let reasonCode: String
    public let refId: String
    public let tsMs: Int64
    public let prevHash: Data
    public let entryHash: Data
    public let serverSig: Data

    public init(seq: Int64, kind: String, amount: Int64, reasonCode: String, refId: String, tsMs: Int64,
                prevHash: Data, entryHash: Data, serverSig: Data) {
        self.seq = seq
        self.kind = kind
        self.amount = amount
        self.reasonCode = reasonCode
        self.refId = refId
        self.tsMs = tsMs
        self.prevHash = prevHash
        self.entryHash = entryHash
        self.serverSig = serverSig
    }
}

/// The server's `EntryDto` (backend/src/ledger.rs): bytes as hex.
struct LedgerEntryDTO: Decodable {
    let seq: Int64
    let kind: String
    let amount: Int64
    let reason_code: String
    let ref_id: String
    let ts_ms: Int64
    let prev_hash: String
    let entry_hash: String
    let server_sig: String

    func entry() throws -> LedgerEntry {
        guard let prev = Data(hex: prev_hash), let hash = Data(hex: entry_hash), let sig = Data(hex: server_sig) else {
            throw Ledger.Rejection.malformed(seq: seq)
        }
        return LedgerEntry(seq: seq, kind: kind, amount: amount, reasonCode: reason_code, refId: ref_id,
                           tsMs: ts_ms, prevHash: prev, entryHash: hash, serverSig: sig)
    }
}

/// Verification of the server-authoritative ledger. The phone never mints: it only appends entries that
/// chain onto its head and carry the pinned server signature, so it holds an independently verifiable copy.
public enum Ledger {
    public static let genesis = Data(count: 32)

    /// Production ledger signing key (SERVER_SIGNING_KEY_HEX on Railway), pinned as on Android.
    public static let serverPublicKey = Data(hex: "fd0adaa84eb11df889b66391dd6c8982dcebd5a12a876aa2031d8de043d0171f")!

    public enum Rejection: Error, Equatable {
        case malformed(seq: Int64)
        case gap(seq: Int64)
        case brokenChain(seq: Int64)
        case hashMismatch(seq: Int64)
        case badSignature(seq: Int64)
    }

    /// sha256(prev ‖ seq ‖ kind ‖ amount ‖ reason ‖ ref_id ‖ ts_ms), integers as big-endian i64.
    /// Must match backend/src/ledger.rs `entry_hash` and Android's LedgerRepository.hash byte for byte.
    public static func hash(prev: Data, seq: Int64, kind: String, amount: Int64, reasonCode: String, refId: String, tsMs: Int64) -> Data {
        var h = SHA256()
        h.update(data: prev)
        h.update(data: bigEndian(seq))
        h.update(data: Data(kind.utf8))
        h.update(data: bigEndian(amount))
        h.update(data: Data(reasonCode.utf8))
        h.update(data: Data(refId.utf8))
        h.update(data: bigEndian(tsMs))
        return Data(h.finalize())
    }

    public static func hash(_ e: LedgerEntry) -> Data {
        hash(prev: e.prevHash, seq: e.seq, kind: e.kind, amount: e.amount, reasonCode: e.reasonCode, refId: e.refId, tsMs: e.tsMs)
    }

    /// Throws unless `entry` is the next link after `head` (nil = empty chain) and is signed by `serverKey`.
    public static func check(_ entry: LedgerEntry, after head: LedgerEntry?, serverKey: Data = serverPublicKey) throws(Rejection) {
        if let head, entry.seq != head.seq + 1 { throw .gap(seq: entry.seq) }
        guard entry.prevHash == (head?.entryHash ?? genesis) else { throw .brokenChain(seq: entry.seq) }
        guard entry.entryHash == hash(entry) else { throw .hashMismatch(seq: entry.seq) }
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: serverKey),
              key.isValidSignature(entry.serverSig, for: entry.entryHash)
        else { throw .badSignature(seq: entry.seq) }
    }

    /// Re-verifies a whole stored chain from genesis.
    public static func verifyChain(_ entries: [LedgerEntry], serverKey: Data = serverPublicKey) -> Bool {
        var head: LedgerEntry?
        for e in entries {
            do { try check(e, after: head, serverKey: serverKey) } catch { return false }
            head = e
        }
        return true
    }

    private static func bigEndian(_ v: Int64) -> Data {
        withUnsafeBytes(of: v.bigEndian) { Data($0) }
    }
}
