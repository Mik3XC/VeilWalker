import Foundation
import Security

/// Where the identity's entropy lives. The Keychain in the app; in memory in tests.
public protocol SecretStore: Sendable {
    func read() throws -> Data?
    func write(_ secret: Data) throws
    func delete() throws
}

/// Device-only Keychain item: readable after first unlock, never synced to iCloud, not in backups
/// that restore to another device. The iOS counterpart of Android's Keystore-wrapped entropy.
public struct KeychainSecretStore: SecretStore {
    public struct Failure: Error, Equatable {
        public let status: OSStatus
    }

    let service: String
    let account: String

    public init(service: String = "com.premisei3.veilwalker.identity", account: String = "entropy") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw Failure(status: status)
        }
    }

    public func write(_ secret: Data) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = secret
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}

/// Loads, creates and replaces the account identity.
public final class IdentityStore: Sendable {
    private let secrets: SecretStore

    public init(secrets: SecretStore = KeychainSecretStore()) {
        self.secrets = secrets
    }

    /// The stored identity, or nil if this phone has none yet.
    public func load() throws -> Identity? {
        guard let entropy = try secrets.read() else { return nil }
        return try Identity(entropy: entropy)
    }

    /// The stored identity, creating and saving a fresh one if none exists.
    public func ensureIdentity() throws -> Identity {
        if let existing = try load() { return existing }
        let identity = Identity.create()
        try secrets.write(identity.entropy)
        return identity
    }

    /// Replaces the identity with one restored from a typed phrase.
    @discardableResult
    public func restore(phrase: String) throws -> Identity {
        let identity = try Identity(mnemonic: phrase)
        try secrets.write(identity.entropy)
        return identity
    }

    /// Forgets the identity on this phone (after account deletion).
    public func erase() throws {
        try secrets.delete()
    }
}
