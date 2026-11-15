//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the puppets and bots of the Telegram, WhatsApp and
// Instagram bridges, told apart by the bridges' exclusive appservice
// namespaces (deploy/config `mautrix-*-registration.yaml.tmpl`,
// `instagram-login-bot-…`). Presence leaves them out (Brief 0072), and a
// feed post is never shared into a room with one of them in it (D-P12).
//

import Foundation

nonisolated enum SpiralBridgeUsers {
    private static let puppetPrefixes = ["telegram_", "whatsapp_", "instagram_"]
    private static let bots = Set(["telegrambot", "whatsappbot", "instagrambot", "instagram-login-bot"])

    static func isBridgeUser(_ userID: String) -> Bool {
        guard userID.hasPrefix("@"), let colon = userID.firstIndex(of: ":") else {
            return false
        }
        let localpart = userID[userID.index(after: userID.startIndex)..<colon]
        return puppetPrefixes.contains { localpart.hasPrefix($0) } || bots.contains(String(localpart))
    }
}
