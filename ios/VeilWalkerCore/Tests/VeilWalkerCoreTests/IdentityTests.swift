import CryptoKit
import Foundation
import XCTest
@testable import VeilWalkerCore

private func hex(_ s: String) -> Data { Data(hex: s)! }

// MARK: - SLIP-0010 (Ed25519 vectors from the SLIP-0010 spec)

final class Slip10Tests: XCTestCase {
    private func check(_ seed: String, _ path: String, chain: String, priv: String, pub: String,
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let node = try Slip10.derive(seed: hex(seed), path: path)
        XCTAssertEqual(node.chainCode.hex, chain, path, file: file, line: line)
        XCTAssertEqual(node.key.hex, priv, path, file: file, line: line)
        let pubKey = try Curve25519.Signing.PrivateKey(rawRepresentation: node.key).publicKey.rawRepresentation
        // SLIP-0010 prints Ed25519 public keys with a 0x00 prefix.
        XCTAssertEqual("00" + pubKey.hex, pub, path, file: file, line: line)
    }

    func testVector1() throws {
        let seed = "000102030405060708090a0b0c0d0e0f"
        try check(seed, "m",
                  chain: "90046a93de5380a72b5e45010748567d5ea02bbf6522f979e05c0d8d8ca9fffb",
                  priv: "2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7",
                  pub: "00a4b2856bfec510abab89753fac1ac0e1112364e7d250545963f135f2a33188ed")
        try check(seed, "m/0'",
                  chain: "8b59aa11380b624e81507a27fedda59fea6d0b779a778918a2fd3590e16e9c69",
                  priv: "68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3",
                  pub: "008c8a13df77a28f3445213a0f432fde644acaa215fc72dcdf300d5efaa85d350c")
        try check(seed, "m/0'/1'",
                  chain: "a320425f77d1b5c2505a6b1b27382b37368ee640e3557c315416801243552f14",
                  priv: "b1d0bad404bf35da785a64ca1ac54b2617211d2777696fbffaf208f746ae84f2",
                  pub: "001932a5270f335bed617d5b935c80aedb1a35bd9fc1e31acafd5372c30f5c1187")
        try check(seed, "m/0'/1'/2'",
                  chain: "2e69929e00b5ab250f49c3fb1c12f252de4fed2c1db88387094a0f8c4c9ccd6c",
                  priv: "92a5b23c0b8a99e37d07df3fb9966917f5d06e02ddbd909c7e184371463e9fc9",
                  pub: "00ae98736566d30ed0e9d2f4486a64bc95740d89c7db33f52121f8ea8f76ff0fc1")
        try check(seed, "m/0'/1'/2'/2'",
                  chain: "8f6d87f93d750e0efccda017d662a1b31a266e4a6f5993b15f5c1f07f74dd5cc",
                  priv: "30d1dc7e5fc04c31219ab25a27ae00b50f6fd66622f6e9c913253d6511d1e662",
                  pub: "008abae2d66361c879b900d204ad2cc4984fa2aa344dd7ddc46007329ac76c429c")
        try check(seed, "m/0'/1'/2'/2'/1000000000'",
                  chain: "68789923a0cac2cd5a29172a475fe9e0fb14cd6adb5ad98a3fa70333e7afa230",
                  priv: "8f94d394a8e8fd6b1bc2f3f49f5c47e385281d5c17e65324b0f62483e37e8793",
                  pub: "003c24da049451555d51a7014a37337aa4e12d41e485abccfa46b47dfb2af54b7a")
    }

    func testVector2() throws {
        let seed = "fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a29f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542"
        try check(seed, "m",
                  chain: "ef70a74db9c3a5af931b5fe73ed8e1a53464133654fd55e7a66f8570b8e33c3b",
                  priv: "171cb88b1b3c1db25add599712e36245d75bc65a1a5c9e18d76f9f2b1eab4012",
                  pub: "008fe9693f8fa62a4305a140b9764c5ee01e455963744fe18204b4fb948249308a")
        try check(seed, "m/0'/2147483647'/1'/2147483646'/2'",
                  chain: "5d70af781f3a37b829f0d060924d5e960bdc02e85423494afc0b1a41bbe196d4",
                  priv: "551d333177df541ad876a60ea71f00447931c0a9da16f227c11ea080d7391b8d",
                  pub: "0047150c75db263559a70d5778bf36abbab30fb061ad69f69ece61a72b0cfa4fc0")
    }

    func testRejectsBadPaths() {
        for path in ["", "44'/0'", "m/44", "m/44'/x'", "m/2147483648'", "m//0'"] {
            XCTAssertThrowsError(try Slip10.derive(seed: hex("00"), path: path), path)
        }
    }
}

// MARK: - BIP39 (24-word vectors from the Trezor reference set)

final class Bip39Tests: XCTestCase {
    private let trezor: [(entropy: String, phrase: String, seed: String)] = [
        ("0000000000000000000000000000000000000000000000000000000000000000",
         "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art",
         "bda85446c68413707090a52022edd26a1c9462295029f2e60cd7c4f2bbd3097170af7a4d73245cafa9c3cca8d561a7c3de6f5d4a10be8ed2a5e608d68f92fcc8"),
        ("7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
         "legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth title",
         "bc09fca1804f7e69da93c2f2028eb238c227f2e9dda30cd63699232578480a4021b146ad717fbb7e451ce9eb835f43620bf5c514db0f8add49f5d121449d3e87"),
        ("8080808080808080808080808080808080808080808080808080808080808080",
         "letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic bless",
         "c0c519bd0e91a2ed54357d9d1ebef6f5af218a153624cf4f2da911a0ed8f7a09e2ef61af0aca007096df430022f7a2b6fb91661a9589097069720d015e4e982f"),
        ("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
         "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote",
         "dd48c104698c30cfe2b6142103248622fb7bb0ff692eebb00089b32d22484e1613912f0a5b694407be899ffd31ed3992c456cdf60f5d4564b8ba3f05a69890ad"),
    ]

    func testWordlist() {
        XCTAssertEqual(Bip39.wordlist.count, 2048)
        XCTAssertEqual(Bip39.wordlist.first, "abandon")
        XCTAssertEqual(Bip39.wordlist.last, "zoo")
        let joined = Bip39.wordlist.joined(separator: "\n") + "\n"
        XCTAssertEqual(Data(SHA256.hash(data: Data(joined.utf8))).hex,
                       "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda")
    }

    func testTrezorVectors() throws {
        for v in trezor {
            XCTAssertEqual(try Bip39.mnemonic(entropy: hex(v.entropy)).joined(separator: " "), v.phrase)
            XCTAssertEqual(try Bip39.entropy(mnemonic: v.phrase).hex, v.entropy)
            XCTAssertEqual(Bip39.seed(mnemonic: v.phrase, passphrase: "TREZOR").hex, v.seed)
        }
    }

    func testEmptyPassphraseSeed() {
        // VeilWalker uses an empty passphrase (salt is just "mnemonic").
        XCTAssertEqual(Bip39.seed(mnemonic: trezor[0].phrase).hex,
                       "408b285c123836004f4b8842c89324c1f01382450c0d439af345ba7fc49acf705489c6fc77dbd4e3dc1dd8cc6bc9f043db8ada1e243c4a0eafb290d399480840")
    }

    func testNormalize() {
        XCTAssertEqual(Bip39.normalize("  Zoo\tZOO \n zoo  "), "zoo zoo zoo")
    }

    func testRejectsBadPhrases() {
        let words = trezor[3].phrase.split(separator: " ").map(String.init)
        XCTAssertThrowsError(try Bip39.entropy(mnemonic: words.dropLast().joined(separator: " "))) {
            XCTAssertEqual($0 as? Bip39.Error, .invalidWordCount(23))
        }
        XCTAssertThrowsError(try Bip39.entropy(mnemonic: (words.dropLast() + ["zoo"]).joined(separator: " "))) {
            XCTAssertEqual($0 as? Bip39.Error, .badChecksum)
        }
        XCTAssertThrowsError(try Bip39.entropy(mnemonic: (words.dropLast() + ["veil"]).joined(separator: " "))) {
            XCTAssertEqual($0 as? Bip39.Error, .unknownWord("veil"))
        }
    }

    func testGenerate() throws {
        let a = Bip39.generate()
        let b = Bip39.generate()
        XCTAssertEqual(a.count, 24)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(try Bip39.entropy(mnemonic: a.joined(separator: " ")).count, 32)
    }
}

// MARK: - Identity (VeilWalker's path m/44'/9077'/0'/0')

final class IdentityTests: XCTestCase {
    // Expected keys computed independently with bip_utils 2.12.1 (Python), which passes
    // the SLIP-0010 spec vectors above.
    private let vectors: [(phrase: String, privateKey: String, publicKey: String)] = [
        ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art",
         "7685a5e8ea8e99956367ebec16c26e7e211a6bda234feb2e042a417010592605",
         "acf1fbbff9010da6ec8285926d6002a0e8f543638db65b8cef0c4cbdcc7a2686"),
        ("legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth title",
         "3706624b50f225ffb01b09cda2ab5f3cfec19cae43e46e4244c4c4b4b70be6e2",
         "6166a85d7c854cb29c42ba2376db8a11ae21e26b2aec8f9a84c5c2574303242c"),
        ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote",
         "d9ebfd7837e41523dd76adc509cd4127f04c1e8fc4ef57515f80d8f591702dd6",
         "26d63c952e3dcaa520fe87ba52250e14362259c6b3d7d2d1c2963d1ed1f04413"),
        ("ozone drill grab fiber curtain grace pudding thank cruise elder eight pioneer trigger conduct feed foil glare firm squirrel wise enhance innocent hungry ensure",
         "f95396b1d0beabdeec15882043611e1de2c247dedc7ecff9401029890dd91e3f",
         "94cca8f2de12a171ac2a6e25954542d35e5fd4caec911227a9381dbafba47b66"),
    ]

    func testPathKeys() throws {
        for v in vectors {
            let id = try Identity(mnemonic: v.phrase)
            XCTAssertEqual(id.privateKey.hex, v.privateKey)
            XCTAssertEqual(id.publicKeyHex, v.publicKey)
        }
    }

    func testMessyInputRestoresSameKey() throws {
        let messy = "  OZONE drill  grab\tfiber curtain grace pudding thank cruise elder eight pioneer\ntrigger conduct feed foil glare firm squirrel wise enhance innocent hungry Ensure "
        XCTAssertEqual(try Identity(mnemonic: messy).publicKeyHex, vectors[3].publicKey)
    }

    func testRequires24Words() {
        let twelve = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        XCTAssertThrowsError(try Identity(mnemonic: twelve)) {
            XCTAssertEqual($0 as? Identity.Error, .wrongWordCount(12))
        }
    }

    func testRestoreFromStoredEntropy() throws {
        let id = try Identity(mnemonic: vectors[1].phrase)
        XCTAssertEqual(id.entropy.hex, "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f")
        let reloaded = try Identity(entropy: id.entropy)
        XCTAssertEqual(reloaded.publicKeyHex, id.publicKeyHex)
        XCTAssertEqual(reloaded.phrase.joined(separator: " "), vectors[1].phrase)
        XCTAssertThrowsError(try Identity(entropy: Data(count: 16)))
    }

    func testCreate() throws {
        let id = Identity.create()
        XCTAssertEqual(id.phrase.count, 24)
        XCTAssertEqual(try Identity(mnemonic: id.phrase.joined(separator: " ")).publicKeyHex, id.publicKeyHex)
        XCTAssertNotEqual(Identity.create().publicKeyHex, id.publicKeyHex)
    }

    func testSignatureVerifies() throws {
        let id = try Identity(mnemonic: vectors[0].phrase)
        let message = Data("POST\n/v1/register\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n0\n00".utf8)
        let sig = try id.sign(message)
        XCTAssertEqual(sig.count, 64)
        XCTAssertTrue(id.signingKey.publicKey.isValidSignature(sig, for: message))
    }

    /// RFC 8032 §7.1 test 1: proves CryptoKit's Ed25519 is standard (what the server's dalek verifier expects).
    func testRfc8032() throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: hex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"))
        XCTAssertEqual(key.publicKey.rawRepresentation.hex, "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        let rfcSig = hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
        XCTAssertTrue(key.publicKey.isValidSignature(rfcSig, for: Data()))
    }

    /// The real cross-platform check: a phrase made on Android must give the same key here.
    /// Android's Slip10Test.kt only has the spec vectors (covered above). Fill this in from a throwaway
    /// account made on the S26 debug build (phrase + x-tb-key), never a real user's phrase.
    func testMatchesAndroid() throws {
        let androidPhrase = ""
        let androidPublicKeyHex = ""
        try XCTSkipIf(androidPhrase.isEmpty, "Waiting for a throwaway phrase + public key from an Android build")
        XCTAssertEqual(try Identity(mnemonic: androidPhrase).publicKeyHex, androidPublicKeyHex)
    }
}
