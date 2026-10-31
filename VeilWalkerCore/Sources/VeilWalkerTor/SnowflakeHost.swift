import Foundation
import VWFlake

/// A Snowflake proxy (the Tor Project's own code, snowflake/vwflake): helps people in censored countries reach Tor.
/// On iPhone it runs only while Wake Mode is on screen, which is within Apple's rules; the app stops it when it leaves
/// the foreground. The only thing it reports is bytes relayed: the Go wrapper drops countries and connection events.
public final class SnowflakeHost: NSObject, VwflakeTrafficProtocol, @unchecked Sendable {
    public static let shared = SnowflakeHost()

    private let lock = NSLock()
    private var onBytes: (@Sendable (Int64) -> Void)?

    /// Starts serving up to `capacity` people at once; `onBytes` gets traffic relayed every few seconds.
    public func start(capacity: Int = 2, onBytes: @escaping @Sendable (Int64) -> Void) {
        lock.withLock { self.onBytes = onBytes }
        VwflakeStart(capacity, self)
    }

    public func stop() {
        VwflakeStop()
        lock.withLock { onBytes = nil }
    }

    public var isRunning: Bool { VwflakeRunning() }

    /// Why the last start failed (no network, broker unreachable), or nil.
    public var lastError: String? {
        let e = VwflakeLastError()
        return e.isEmpty ? nil : e
    }

    /// Called from Go.
    public func relayed(_ bytes: Int64) {
        let cb = lock.withLock { onBytes }
        cb?(bytes)
    }
}
