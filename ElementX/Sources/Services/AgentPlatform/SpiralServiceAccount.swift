//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3): the accounts on our own server that are services,
// not people. People search shows only people (operator, 2026-11-19:
// «сервісних користувачів не шукаєм в пошуку тільки людей»).
//

import Foundation

nonisolated enum SpiralServiceAccount {
    /// Whether `userID` is a service account of `ownServerName`, the server
    /// this session lives on. Another server's ID is never classified: the
    /// namespaces below are our own registrations, and a foreign
    /// `@telegrambot` may be a person there.
    ///
    /// Where each family comes from (to add a new one, extend its source):
    /// - Agents and the platform's appservice sender (`agent-*`, `assistant-*`,
    ///   which covers `agent-platform-bot`): `SpiralAppPostSession.isAgent`,
    ///   from `matrix-agent-platform/deploy/config/synapse-registration.yaml.tmpl`.
    /// - The bridges' bots and puppets (`telegrambot`, `whatsappbot`,
    ///   `instagrambot`, `instagram-login-bot`, `telegram_*`, `whatsapp_*`,
    ///   `instagram_*`): `SpiralBridgeUsers.isBridgeUser`, from the
    ///   `mautrix-*-registration.yaml.tmpl` and
    ///   `instagram-login-bot-registration.yaml.tmpl` files there. A new
    ///   bridge goes into `SpiralBridgeUsers`, which presence and feed
    ///   sharing read too.
    /// - Any localpart starting with `_`, the service convention; today
    ///   `_lk_jwt_service`, the sender of `lk-jwt-registration.yaml.tmpl`.
    /// - `reservedLocalparts`: real accounts that are services, the backend's
    ///   `RESERVED_SERVICE_LOCALPARTS`.
    ///
    /// The bridges' own appservice senders have random localparts
    /// (`${mautrix_sender_localpart}` and the like) and can't be listed here.
    ///
    /// Compared lowercased throughout: server names are case-insensitive and
    /// a typed `@Agent-X:SPIRAL.MD` must not slip past as a person.
    static func isService(_ userID: String, ownServerName: String) -> Bool {
        let userID = userID.lowercased()
        guard userID.hasPrefix("@"),
              let colon = userID.firstIndex(of: ":"),
              userID[userID.index(after: colon)...] == ownServerName.lowercased() else {
            return false
        }
        let localpart = userID[userID.index(after: userID.startIndex)..<colon]
        return localpart.hasPrefix("_")
            || reservedLocalparts.contains(String(localpart))
            || SpiralAppPostSession.isAgent(userID)
            || SpiralBridgeUsers.isBridgeUser(userID)
    }

    /// Whole localparts only (`spiral` keeps `spiralfan`). Mirrors the
    /// backend's `RESERVED_SERVICE_LOCALPARTS` (`personal_agent_reconcile.rs`,
    /// operator 2026-11-14), `spiral` on every stack: Spiral's official feed
    /// account `@spiral`.
    private static let reservedLocalparts: Set = ["spiral"]
}
