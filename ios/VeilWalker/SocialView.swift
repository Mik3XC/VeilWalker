import SwiftUI
import VeilWalkerCore

/// Invites, friends and the squad leaderboard. Friends see handle, clan, picture and weekly steps, nothing else.
/// Mirrors SocialScreen.kt.
struct SocialView: View {
    @Environment(AppModel.self) private var app
    @State private var friends: [ApiClient.Person] = []
    @State private var squad: ApiClient.Squad?
    @State private var friendCode: String?
    @State private var squadCode: String?
    @State private var message: String?
    @State private var loading = true
    @State private var code = ""

    var body: some View {
        VeilScreen(spacing: 6) {
            Text("Social").font(Veil.headline)
            Text("Friends see your handle, clan, picture and weekly steps. Nothing else.").font(Veil.small).foregroundStyle(Veil.dim)
            if let message { Text(message).foregroundStyle(Veil.violet).accessibilityIdentifier("social-message") }

            section("invite")
            VeilButton(label: "New friend invite", glyph: "+") { run { _ = try await newInvite(.friend); return nil } }
            if let c = friendCode {
                Text(c).font(Veil.titleLarge).foregroundStyle(Veil.green).textSelection(.enabled)
                ShareLink(item: inviteText(c, squad: nil)) { Text("> share invite").foregroundStyle(Veil.violet).padding(.vertical, 6) }
            }
            TerminalField(label: "have a code? VW-XXXX-XXXX", text: $code) {
                String($0.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(12))
            }
            VeilButton(label: "Accept code", glyph: "!", enabled: code.count >= 11) {
                let c = code
                code = ""
                run { try await accept(c) }
            }

            section("friends (\(friends.count))")
            if loading {
                Text("loading…").foregroundStyle(Veil.muted)
            } else if friends.isEmpty {
                Text("No friends yet. Share an invite.").foregroundStyle(Veil.muted)
            }
            ForEach(friends) { p in
                PersonRow(rank: nil, person: p) { run { try await remove(p) } }
            }

            section(squad?.clan.map { "squad [\($0)]" } ?? "squad")
            if let squad, let tag = squad.clan {
                Text("\(Fmt.grouped(squad.weekTotal)) steps this week together").fontWeight(.bold).foregroundStyle(Veil.violet)
                ForEach(Array(squad.members.enumerated()), id: \.element.id) { i, p in PersonRow(rank: i + 1, person: p, onRemove: nil) }
                VeilButton(label: "New squad invite [\(tag)]", glyph: "+") { run { _ = try await newInvite(.clan); return nil } }
                if let c = squadCode {
                    Text(c).font(Veil.titleLarge).foregroundStyle(Veil.green).textSelection(.enabled)
                    ShareLink(item: inviteText(c, squad: tag)) { Text("> share squad invite").foregroundStyle(Veil.violet).padding(.vertical, 6) }
                }
            } else {
                Text("Not in a clan. Create or join one in @ account, or accept a squad invite.").foregroundStyle(Veil.muted)
            }

            VeilButton(label: "Refresh", glyph: "~") { refreshTask() }
        }
        .task { await refresh() }
    }

    private func section(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("// \(title)").foregroundStyle(Veil.green)
            Rectangle().fill(Veil.muted).frame(height: 1)
        }
        .padding(.top, 8)
    }

    private func inviteText(_ code: String, squad: String?) -> String {
        squad.map { "Walk with my squad [\($0)] on VeilWalker. Invite code: \(code)" }
            ?? "Walk with me on VeilWalker, the step counter that doesn't watch you. Invite code: \(code)"
    }

    // MARK: Calls

    private func refreshTask() { Task { await refresh() } }

    private func refresh() async {
        loading = true
        await perform {
            guard let api = app.api() else { throw AppModel.AccountError.offline }
            try? await api.setAvatar(app.avatar)   // friends see the picture you chose
            friends = try await api.friends()
            let s = try await api.squad()
            squad = s
            app.setClan(s.clan)
            return nil
        }
        loading = false
    }

    private func newInvite(_ kind: ApiClient.InviteKind) async throws -> String {
        guard let api = app.api() else { throw AppModel.AccountError.offline }
        let c = try await api.createInvite(kind)
        if kind == .clan { squadCode = c } else { friendCode = c }
        return c
    }

    private func accept(_ c: String) async throws -> String? {
        guard let api = app.api() else { throw AppModel.AccountError.offline }
        let r = try await api.acceptInvite(c)
        await refresh()
        return "You and @\(r.friend ?? "?") are friends" + (r.joinedClan.map { ". Joined [\($0)]." } ?? ".")
    }

    private func remove(_ p: ApiClient.Person) async throws -> String? {
        guard let api = app.api() else { throw AppModel.AccountError.offline }
        try await api.removeFriend(id: p.id)
        await refresh()
        return "Removed @\(p.handle ?? "anon")"
    }

    private func run(_ op: @escaping () async throws -> String?) {
        Task { await perform(op) }
    }

    private func perform(_ op: () async throws -> String?) async {
        do {
            if let m = try await op() { message = m }
        } catch let e as ApiError {
            message = switch e.reason {
            case "no_handle": "Claim a handle in @ account first."
            case "no_clan": "Join or create a clan first."
            case "not_found": "No invite with that code."
            case "expired": "That invite expired or was used up."
            case "own_invite": "That's your own invite."
            default: "Failed: \(e.status)"
            }
        } catch {
            message = AppModel.offlineMessage
        }
    }
}

private struct PersonRow: View {
    let rank: Int?
    let person: ApiClient.Person
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            AvatarArt(index: person.avatar, size: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text((rank.map { "#\($0) " } ?? "") + (person.clan.map { "[\($0)] " } ?? "") + (person.handle ?? "anon")).fontWeight(.bold)
                Text("\(Fmt.grouped(person.weekSteps)) steps this week").font(Veil.small).foregroundStyle(Veil.dim)
            }
            Spacer()
            if let onRemove {
                Button(action: onRemove) { Text("x").foregroundStyle(Veil.muted).padding(8) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("remove \(person.handle ?? "friend")")
            }
        }
        .padding(.vertical, 4)
    }
}
