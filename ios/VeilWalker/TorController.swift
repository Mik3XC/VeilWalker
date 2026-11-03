import Foundation
import Observation
import VeilWalkerCore
import VeilWalkerTor

/// Owns the home screen's Tor line. Tor sleeps until it's needed: it starts in the foreground and is shown as
/// `waking…` after a suspension, and "onion ok" only follows a real answer from the onion service. Mirrors Android's
/// TorManager (3 health checks, 20 s apart; any successful request marks the onion ok).
@MainActor @Observable
final class TorController {
    private(set) var phase: TorPhase = .connecting
    /// On by default. Off is the user's explicit choice (clearnet); there is never a silent fallback.
    private(set) var enabled: Bool
    private var checking: Task<Void, Never>?

    private static let enabledKey = "torEnabled"
    static let onionAttempts = 3

    init() {
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    var line: String { phase.line(enabled: enabled) }

    /// Starts Arti if needed and checks the onion service. Returns when the check finishes (or immediately if off).
    func wake() async {
        guard enabled else { return }
        if checking == nil {
            checking = Task { await self.bootAndCheck(); self.checking = nil }
        }
        await checking?.value
    }

    private func bootAndCheck() async {
        if phase != .waking && phase != .ok { phase = .connecting }
        do {
            try await Arti.shared.start()
        } catch {
            if enabled { phase = .failed }
            return
        }
        guard enabled else { return }
        if phase != .ok { phase = .checking }
        for attempt in 0..<Self.onionAttempts {
            if phase == .ok || !enabled { return }   // a real request already proved it
            if (try? await TorTransport().health()) == true {
                markOnionOk()
                return
            }
            if attempt < Self.onionAttempts - 1 { try? await Task.sleep(for: .seconds(20)) }
        }
        if enabled && phase != .ok { phase = .unreachable }
    }

    func markOnionOk() {
        if enabled { phase = .ok }
    }

    /// The app is going to the background: whatever Tor proved is stale once iOS freezes it.
    func suspend() {
        if enabled { phase = .waking }
    }

    func toggle() {
        enabled.toggle()
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            phase = .connecting
        } else {
            checking?.cancel()
            checking = nil
            Arti.shared.stop()
        }
    }

    /// Onion when on (and every answer marks it ok), clearnet only when the user switched Tor off.
    func transport() -> Transport {
        guard enabled else { return ClearnetTransport() }
        return ReportingTransport(TorTransport()) { [weak self] in
            Task { @MainActor [weak self] in self?.markOnionOk() }
        }
    }
}
