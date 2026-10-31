import Foundation

/// What the home screen's Tor line says. Mirrors Android's TorState, plus iOS's `waking` after a suspension:
/// iOS freezes Arti in the background, so a stale "ok" would be a lie (handoff §6, "UI honesty").
public enum TorPhase: Equatable, Sendable {
    /// Back from the background; nothing has been proven since.
    case waking
    /// Arti is bootstrapping.
    case connecting
    /// Arti is up; the onion health check hasn't finished yet (Android: onionReachable == null).
    case checking
    /// A real request over the onion service succeeded.
    case ok
    /// Three health checks in a row failed (Android: onionReachable == false).
    case unreachable
    /// Arti itself failed to start.
    case failed

    /// `(%) tor · onion ok` when on, `[x] tor off` when off. Android's torLine() says "tor on ·"; iOS drops "on" so the
    /// line fits beside the walk status.
    public func line(enabled: Bool) -> String {
        guard enabled else { return "[x] tor off" }
        switch self {
        case .waking: return "(%) tor waking…"
        case .connecting: return "(%) tor · connecting…"
        case .checking: return "(%) tor · checking…"
        case .ok: return "(%) tor · onion ok"
        case .unreachable: return "(%) tor · retrying"
        case .failed: return "(%) tor · waiting"
        }
    }
}

/// Wraps a transport and reports each answered request, so any real round trip over the onion service marks it
/// reachable (Android's markOnionOk()). Any HTTP status counts: the server answered over the onion.
public struct ReportingTransport: Transport {
    private let base: Transport
    private let onAnswered: @Sendable () -> Void

    public init(_ base: Transport, onAnswered: @escaping @Sendable () -> Void) {
        self.base = base
        self.onAnswered = onAnswered
    }

    public var isOnion: Bool { base.isOnion }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await base.send(request)
        onAnswered()
        return response
    }
}
