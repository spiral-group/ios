//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the App Clip's invitation hand-off, the app's side (Brief 0086).
//

import Foundation

/// Turns the invitation the App Clip left in the App Group into the app's `pendingInvite`, so the start
/// screen's banner and Brief 0073's registration flow run as if the person had tapped the link.
nonisolated enum ClipInviteAdoption {
    /// The invitation to remember, or nil to leave `pendingInvite` as it is.
    ///
    /// Only a launch with no session adopts one, only for this build's own server (a staging invitation never
    /// reaches a prod app, nor the other way round), and a `pendingInvite` the app already holds (a link tapped in
    /// the app itself) wins over the Clip's. `clipInvite` is already checked for freshness. Its inviter is only a first
    /// paint until `PendingInviteRefresh` has the server's: a user ID that isn't one is dropped, a name is capped.
    static func pendingInvite(from clipInvite: ClipInvite?,
                              existing: PendingInvite?,
                              hasSession: Bool,
                              serverName: String = SpiralLink.serverName) -> PendingInvite? {
        guard let clipInvite, !hasSession, existing == nil,
              clipInvite.host.lowercased() == serverName.lowercased() else {
            return nil
        }
        return PendingInvite(token: clipInvite.token,
                             inviterDisplayName: displayName(clipInvite.inviterDisplayName),
                             inviterUserID: clipInvite.inviterUserID.flatMap { isUserID($0) ? $0 : nil })
    }

    /// The invitation a launch asks the server about again: whatever is remembered, adopted now or on an earlier
    /// launch, while no one is signed in. Once per launch; a session's start settles it (the welcome).
    static func inviteToRecheck(_ pendingInvite: PendingInvite?, hasSession: Bool) -> SpiralInviteLink? {
        hasSession ? nil : pendingInvite?.link
    }

    static let maximumDisplayNameLength = 64

    private static func displayName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return String(name.prefix(maximumDisplayNameLength))
    }

    /// `@localpart:server`, within Matrix's 255 characters, without whitespace.
    private static func isUserID(_ value: String) -> Bool {
        guard value.count <= 255, value.hasPrefix("@"), !value.contains(where: \.isWhitespace) else { return false }
        let parts = value.dropFirst().split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }
}
