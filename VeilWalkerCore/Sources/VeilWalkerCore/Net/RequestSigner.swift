import CryptoKit
import Foundation
import Security

/// Signs API requests the way backend/src/auth.rs verifies them. No cookies, no tokens.
///
/// Signed message (UTF-8): "METHOD\nPATH\nhex(sha256(body))\nTS\nNONCE".
/// PATH never includes the query string; the server hard-codes each route's path.
public enum RequestSigner {
    public static func message(method: String, path: String, body: Data, timestampMillis: Int64, nonceHex: String) -> Data {
        let bodyHash = Data(SHA256.hash(data: body)).hex
        return Data("\(method)\n\(path)\n\(bodyHash)\n\(timestampMillis)\n\(nonceHex)".utf8)
    }

    /// The four x-tb-* headers for one request. `nonce` and `now` are injectable for tests.
    public static func headers(
        identity: Identity,
        method: String,
        path: String,
        body: Data,
        now: Date = Date(),
        nonce: Data = randomNonce()
    ) throws -> [String: String] {
        let ts = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        let nonceHex = nonce.hex
        let sig = try identity.sign(message(method: method, path: path, body: body, timestampMillis: ts, nonceHex: nonceHex))
        return [
            "x-tb-key": identity.publicKeyHex,
            "x-tb-ts": String(ts),
            "x-tb-nonce": nonceHex,
            "x-tb-sig": sig.hex,
        ]
    }

    /// 16 random bytes. The server rejects any nonce it has seen before.
    public static func randomNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }
}
