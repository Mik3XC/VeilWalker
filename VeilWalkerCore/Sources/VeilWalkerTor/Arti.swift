import Foundation
import VWTor

public struct TorError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// Embedded Arti (rust/vw-tor). Tor sleeps until something needs it: the app starts it in the foreground,
/// during live walks and in background sync, never as a resident client (iOS suspends apps anyway).
///
/// Every Rust call blocks, so they run on a private queue instead of Swift's cooperative threads.
public final class Arti: Sendable {
    public static let shared = Arti()

    private let queue = DispatchQueue(label: "com.premisei3.veilwalker.arti", qos: .utility, attributes: .concurrent)

    public init() {}

    /// Application Support/arti/{state,cache}, excluded from backup. Not Caches: iOS may purge that,
    /// and a cached consensus is what lets later starts bootstrap in seconds.
    public static func defaultDirectories() throws -> (state: URL, cache: URL) {
        var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "arti", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        let state = root.appending(path: "state", directoryHint: .isDirectory)
        let cache = root.appending(path: "cache", directoryHint: .isDirectory)
        for dir in [state, cache] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return (state, cache)
    }

    public var isRunning: Bool { vw_tor_is_running() == 1 }

    /// Bootstraps if not running. Returns when connected; throws on failure or after `timeout`.
    public func start(timeout: Duration = .seconds(45), directories: (state: URL, cache: URL)? = nil) async throws {
        let dirs = try directories ?? Self.defaultDirectories()
        let ms = Self.millis(timeout)
        try await run {
            guard vw_tor_start(dirs.state.path, dirs.cache.path, ms) == 0 else { throw Self.lastError() }
        }
    }

    public func stop() {
        vw_tor_stop()
    }

    /// One request to an http://…onion URL. Any HTTP status is a response; only transport failures throw.
    func http(method: String, url: String, headers: String, body: Data, timeout: Duration) async throws -> (status: Int, body: Data) {
        let ms = Self.millis(timeout)
        return try await run {
            var out = VwHttpResponse(status: 0, body: nil, body_len: 0)
            let rc = body.withUnsafeBytes { raw in
                vw_http(method, url, headers, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, ms, &out)
            }
            guard rc == 0 else { throw Self.lastError() }
            defer { vw_http_response_free(&out) }
            let data = out.body.map { Data(bytes: $0, count: out.body_len) } ?? Data()
            return (Int(out.status), data)
        }
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// Must be called on the thread whose Rust call just failed.
    private static func lastError() -> TorError {
        guard let p = vw_last_error() else { return TorError(message: "unknown error") }
        defer { vw_string_free(p) }
        let msg = String(cString: p)
        return TorError(message: msg.isEmpty ? "unknown error" : msg)
    }

    private static func millis(_ d: Duration) -> UInt32 {
        let (seconds, attoseconds) = d.components
        let ms = seconds * 1000 + attoseconds / 1_000_000_000_000_000
        return UInt32(clamping: max(ms, 0))
    }
}
