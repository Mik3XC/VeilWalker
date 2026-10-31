import CryptoKit
import Foundation

/// The account: an Ed25519 key derived from a 24-word phrase.
/// Must produce the same public key as Android for the same phrase.
///
/// Like Android's IdentityStore, this keeps the phrase's entropy (so the phrase can be shown again)
/// and derives the signing key from it.
public struct Identity: Sendable {
    /// 9077 is VeilWalker's coin type. Changing it changes every account.
    public static let derivationPath = "m/44'/9077'/0'/0'"
    public static let wordCount = 24

    public enum Error: Swift.Error, Equatable {
        case wrongWordCount(Int)
        case invalidPhrase(Bip39.Error)
    }

    /// 32 bytes of BIP39 entropy. This is the secret that goes in the Keychain.
    public let entropy: Data
    public let signingKey: Curve25519.Signing.PrivateKey

    /// Restores from a phrase typed by the user. Normalizes, requires 24 words and a valid checksum.
    public init(mnemonic phrase: String) throws(Error) {
        let normalized = Bip39.normalize(phrase)
        let count = normalized.split(separator: " ").count
        guard count == Self.wordCount else { throw .wrongWordCount(count) }
        do {
            try self.init(entropy: Bip39.entropy(mnemonic: normalized))
        } catch {
            throw .invalidPhrase(error)
        }
    }

    /// From stored entropy (32 bytes for a 24-word phrase).
    public init(entropy: Data) throws(Bip39.Error) {
        guard entropy.count == 32 else { throw .invalidEntropyLength(entropy.count) }
        let phrase = try Bip39.mnemonic(entropy: entropy).joined(separator: " ")
        // The path is a constant, so derivation cannot fail.
        let node = try! Slip10.derive(seed: Bip39.seed(mnemonic: phrase), path: Self.derivationPath)
        self.entropy = entropy
        // Any 32 bytes are a valid Ed25519 private seed.
        signingKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: node.key)
    }

    /// Creates a new account from fresh system randomness.
    public static func create() -> Identity {
        // A freshly generated phrase is always valid.
        try! Identity(entropy: Bip39.entropy(mnemonic: Bip39.generate().joined(separator: " ")))
    }

    /// The recovery phrase, for showing to the user on a privacy-protected screen.
    public var phrase: [String] {
        // entropy was validated in init.
        try! Bip39.mnemonic(entropy: entropy)
    }

    public var privateKey: Data { signingKey.rawRepresentation }

    /// 32-byte public key as lowercase hex: the account ID and the `x-tb-key` header value.
    public var publicKeyHex: String { signingKey.publicKey.rawRepresentation.hex }

    /// Ed25519 signature (64 bytes). CryptoKit randomizes signatures, so they differ from
    /// Android's byte for byte, but any Ed25519 verifier (the server uses ed25519-dalek) accepts them.
    public func sign(_ message: Data) throws -> Data {
        try signingKey.signature(for: message)
    }
}
