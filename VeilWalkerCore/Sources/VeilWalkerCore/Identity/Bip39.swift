import CommonCrypto
import CryptoKit
import Foundation
import Security

/// BIP39 with the English wordlist. Phrases must restore identically on Android,
/// so this follows the spec exactly: NFKD, PBKDF2-HMAC-SHA512, 2048 rounds, salt "mnemonic" + passphrase.
public enum Bip39 {
    public enum Error: Swift.Error, Equatable {
        case invalidEntropyLength(Int)
        case invalidWordCount(Int)
        case unknownWord(String)
        case badChecksum
    }

    public static let wordlist: [String] = {
        guard let url = Bundle.module.url(forResource: "bip39-english", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { fatalError("bip39-english.txt missing from bundle") }
        let words = text.split(whereSeparator: \.isNewline).map(String.init)
        precondition(words.count == 2048, "BIP39 wordlist must have 2048 words")
        return words
    }()

    private static let indexByWord: [String: Int] = {
        Dictionary(uniqueKeysWithValues: wordlist.enumerated().map { ($1, $0) })
    }()

    /// Trim, lowercase, single spaces, NFKD. Matches Android's input normalization.
    public static func normalize(_ phrase: String) -> String {
        phrase.decomposedStringWithCompatibilityMapping
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// A fresh 24-word phrase from 256 bits of system randomness.
    public static func generate() -> [String] {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        defer { bytes.resetBytes(in: 0..<bytes.count) }
        // 32 bytes is always a valid length.
        return try! mnemonic(entropy: Data(bytes))
    }

    public static func mnemonic(entropy: Data) throws(Error) -> [String] {
        guard [16, 20, 24, 28, 32].contains(entropy.count) else {
            throw .invalidEntropyLength(entropy.count)
        }
        let checksumBits = entropy.count * 8 / 32
        let hash = Data(SHA256.hash(data: entropy))
        let bits = Self.bits(entropy) + Self.bits(hash).prefix(checksumBits)
        return stride(from: 0, to: bits.count, by: 11).map { start in
            let index = bits[start..<start + 11].reduce(0) { $0 << 1 | ($1 ? 1 : 0) }
            return wordlist[index]
        }
    }

    /// Validates word count, words and checksum, and returns the entropy.
    public static func entropy(mnemonic phrase: String) throws(Error) -> Data {
        let words = normalize(phrase).split(separator: " ").map(String.init)
        guard [12, 15, 18, 21, 24].contains(words.count) else {
            throw .invalidWordCount(words.count)
        }
        var bits = [Bool]()
        bits.reserveCapacity(words.count * 11)
        for word in words {
            guard let index = indexByWord[word] else { throw .unknownWord(word) }
            for shift in stride(from: 10, through: 0, by: -1) {
                bits.append(index >> shift & 1 == 1)
            }
        }
        let checksumBits = bits.count / 33
        let entropyBits = bits.count - checksumBits
        var entropy = Data(count: entropyBits / 8)
        for i in 0..<entropy.count {
            entropy[i] = bits[i * 8..<i * 8 + 8].reduce(0) { $0 << 1 | ($1 ? 1 : 0) }
        }
        let expected = Self.bits(Data(SHA256.hash(data: entropy))).prefix(checksumBits)
        guard Array(bits[entropyBits...]) == Array(expected) else { throw .badChecksum }
        return entropy
    }

    /// The 64-byte BIP39 seed. VeilWalker always uses an empty passphrase.
    /// Does not validate the checksum; call `entropy(mnemonic:)` first.
    public static func seed(mnemonic phrase: String, passphrase: String = "") -> Data {
        let password = Array(normalize(phrase).utf8)
        let salt = Array(("mnemonic" + passphrase).decomposedStringWithCompatibilityMapping.utf8)
        var out = [UInt8](repeating: 0, count: 64)
        let status = password.withUnsafeBufferPointer { pw in
            pw.withMemoryRebound(to: CChar.self) { pwChars in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwChars.baseAddress, pwChars.count,
                    salt, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    2048,
                    &out, out.count
                )
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed: \(status)")
        return Data(out)
    }

    private static func bits(_ data: Data) -> [Bool] {
        data.flatMap { byte in (0..<8).map { byte >> (7 - $0) & 1 == 1 } }
    }
}
