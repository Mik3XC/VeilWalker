import CryptoKit
import Foundation

/// SLIP-0010 key derivation for Ed25519. Ed25519 only supports hardened children.
public enum Slip10 {
    public enum Error: Swift.Error, Equatable {
        case invalidPath(String)
    }

    public struct Node: Sendable, Equatable {
        /// The 32-byte Ed25519 private seed (what CryptoKit calls rawRepresentation).
        public let key: Data
        public let chainCode: Data
    }

    static let hardenedOffset: UInt32 = 0x8000_0000

    public static func master(seed: Data) -> Node {
        split(HMAC<SHA512>.authenticationCode(
            for: seed,
            using: SymmetricKey(data: Data("ed25519 seed".utf8))
        ))
    }

    /// Derives a hardened child. `index` is the unhardened number (0 for 0').
    public static func child(of parent: Node, index: UInt32) -> Node {
        precondition(index < hardenedOffset, "index must be below 2^31")
        var data = Data([0x00])
        data.append(parent.key)
        withUnsafeBytes(of: (index | hardenedOffset).bigEndian) { data.append(contentsOf: $0) }
        return split(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: parent.chainCode)))
    }

    /// Derives along a path like `m/44'/9077'/0'/0'`. Every component must be hardened.
    public static func derive(seed: Data, path: String) throws(Error) -> Node {
        var components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first == "m" else { throw .invalidPath(path) }
        components.removeFirst()
        var node = master(seed: seed)
        for component in components {
            guard component.hasSuffix("'") || component.hasSuffix("H"),
                  let index = UInt32(component.dropLast()),
                  index < hardenedOffset
            else { throw .invalidPath(path) }
            node = child(of: node, index: index)
        }
        return node
    }

    private static func split(_ mac: HMAC<SHA512>.MAC) -> Node {
        let bytes = Data(mac)
        return Node(key: bytes.prefix(32), chainCode: bytes.suffix(32))
    }
}
