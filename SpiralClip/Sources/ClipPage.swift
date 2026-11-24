//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the App Clip for invite links (Brief 0086).
//

import Foundation

/// The four tour pages Spark swipes through (concept D, D1–D4).
enum ClipPage: Int, CaseIterable, Identifiable {
    case invite
    case privacy
    case calls
    case assistant

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .invite: String(localized: "clip.page.invite.title")
        case .privacy: String(localized: "clip.page.privacy.title")
        case .calls: String(localized: "clip.page.calls.title")
        case .assistant: String(localized: "clip.page.assistant.title")
        }
    }

    var subtitle: String {
        switch self {
        case .invite: String(localized: "clip.page.invite.subtitle")
        case .privacy: String(localized: "clip.page.privacy.subtitle")
        case .calls: String(localized: "clip.page.calls.subtitle")
        case .assistant: String(localized: "clip.page.assistant.subtitle")
        }
    }

    /// The App Store screenshots' Spark poses (operator, 2026-11-19); `SparkInvite` holds the invitation card.
    var imageName: String {
        switch self {
        case .invite: "SparkInvite"
        case .privacy: "SparkPrivacy"
        case .calls: "SparkCalls"
        case .assistant: "SparkAssistant"
        }
    }

    /// Where the inviter's picture sits on the `invite` page's Spark: centred on the card's spiral, as fractions of
    /// the image's width and height, from its top left in every layout direction (the image never mirrors). The
    /// image is `spark-invite-card.png` cropped to Spark (672 × 917 of its 1254 px square, from 295, 171); the
    /// operator's measured centre (0.499, 0.604) lands at (0.4922, 0.6395). The diameter, 0.135 of the height, is
    /// larger than the spiral (0.085 of the square) so a face reads, and stays inside the card (0.178 high).
    static let inviterAvatarRect = CGRect(x: 0.4922 - 0.184 / 2, y: 0.6395 - 0.135 / 2, width: 0.184, height: 0.135)

    var next: ClipPage? {
        ClipPage(rawValue: rawValue + 1)
    }

    var previous: ClipPage? {
        ClipPage(rawValue: rawValue - 1)
    }
}
