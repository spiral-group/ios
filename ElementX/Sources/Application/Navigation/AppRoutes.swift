//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

// MARK: - Routes

enum AppRoute: Hashable {
    // AGENT-PLATFORM (Brief 0083 L1b): no accountProvisioningLink, Element's mobile.element.io links.
    /// An external callback used to complete login with OAuth. This is only used when authentication
    /// requires an external app so cannot be handled directly by the web authentication session.
    case oAuthCallback(url: URL)
    
    /// The app's home screen.
    case roomList
    /// A room, shown as the root of the stack (popping any child rooms).
    case room(roomID: String, via: [String])
    /// The same as ``room`` but using a room alias.
    case roomAlias(String)
    /// A room, pushed as a child of any existing rooms on the stack.
    case childRoom(roomID: String, via: [String])
    /// The same as ``childRoom`` but using a room alias.
    case childRoomAlias(String)
    /// The information about a particular room.
    case roomDetails(roomID: String)
    /// The profile of a member within the current room.
    case roomMemberDetails(userID: String)
    /// An event within a room, shown as the root of the stack (popping any child rooms).
    case event(eventID: String, roomID: String, via: [String])
    /// The same as ``event`` but using a room alias.
    case eventOnRoomAlias(eventID: String, alias: String)
    /// An event within a room, either within the last child on the stack or pushing a new child if needed.
    case childEvent(eventID: String, roomID: String, via: [String])
    /// The same as ``childEvent`` but using a room alias.
    case childEventOnRoomAlias(eventID: String, alias: String)
    /// The profile of a matrix user (outside of a room).
    case userProfile(userID: String)
    /// An Element Call running in a particular room
    case call(roomID: String, isVoiceCall: Bool)
    /// The settings screen.
    case settings
    /// The setting screen for key backup.
    case chatBackupSettings
    /// An external share request e.g. from the ShareExtension
    case share(ShareExtensionPayload)
    /// The change roles screen of a room with the transfer ownership setting
    case transferOwnership(roomID: String)
    /// A thread within a room, only to be used to handle tap on notification for threaded events.
    case thread(roomID: String, threadRootEventID: String, focusEventID: String?)
    /// The search screen
    case search

    // AGENT-PLATFORM: deep-link into the ApprovalDetailScreen,
    // triggered by tapping an approval's push. The `approvalID`
    // is the one the Spiral direct push names. Drives
    // both `UserSessionFlowCoordinator.handleAppRoute` (which
    // switches to the Agents tab) and
    // `AgentSpacesTabFlowCoordinator.handleAppRoute` (which pushes
    // the detail coordinator onto the sidebar nav stack).
    case approvalDetail(approvalID: String)

    // AGENT-PLATFORM: deep-link into the VerificationDetailScreen,
    // triggered by tapping a verification's push. The
    // `verificationID` is the `verification_approvals` row the
    // Spiral direct push names. Routing is the
    // same shape as `.approvalDetail` — `UserSessionFlowCoordinator`
    // switches to the Agents tab, then `AgentSpacesTabFlowCoordinator`
    // pops to dashboard root and pushes
    // `VerificationDetailScreenCoordinator` onto the sidebar
    // stack so back-button returns to the dashboard rather than
    // an intermediate Verifications list.
    case verificationDetail(verificationID: String)

    // AGENT-PLATFORM: deep-link into the `PublicProfileScreen`
    // (S178), which lists a person's *public agents*. Reached
    // from the agent surfaces, where those agents are the
    // subject.
    //
    // Brief 0060: `.userProfile` is NO LONGER promoted to this
    // route. That promotion (v1.7.x chore P4) fired whenever the
    // MXID sat on a homeserver we provision, which became every
    // MXID once spiral.md was the only one (ADR-0060) — so every
    // shared profile link landed here and read "no public
    // agents". Profile links now open Element's canonical
    // `UserProfileScreen`.
    case publicProfile(targetMXID: String)
    
    // AGENT-PLATFORM (Brief 0073 / ADR-0008): an invitation to register,
    // `https://spiral.md/join/{token}`. Logged out it reaches the
    // authentication flow (start-screen banner, token on the OAuth URL);
    // logged in `AppCoordinator.handleDeepLink` turns it into the
    // inviter's profile instead.
    case inviteLink(SpiralInviteLink)
    
    // AGENT-PLATFORM (decision 111): a post catalogue template,
    // `https://spiral.md/catalog/<id>`. Shaped like `.share`: a nil
    // `roomID` asks which chat, and the chats tab resolves the id against
    // the catalogue before it asks.
    case catalogTemplate(templateID: String, roomID: String?)

    // AGENT-PLATFORM (decision 150): the third-party AI toggle in Advanced
    // settings, opened by the notice to a person without AI consent. Raised
    // by the notice's action only: no URL parses into it, so a link in a
    // message can't open Settings.
    case aiConsentSettings

    // AGENT-PLATFORM: feed (Brief 0082): one feed post, `spiral.md/feed/<id>`,
    // opened on the Feed tab.
    case feedPost(postID: String)
    // AGENT-PLATFORM: feed (Brief 0082): the person's feed notices, opened by a
    // `feed_notice` push. No URL parses into it.
    case feedNotices

    /// Whether or not the route should be handled by the authentication flow.
    var isAuthenticationRoute: Bool {
        switch self {
        case .oAuthCallback: true
        case .inviteLink: true
        default: false
        }
    }
}

// AGENT-PLATFORM (Brief 0083 L1b): no AccountProvisioningParameters.

struct AppRouteURLParser {
    let urlParsers: [URLParser]
    
    init(appSettings: AppSettings) {
        urlParsers = [
            AppGroupURLParser(),
            // AGENT-PLATFORM (Brief 0060 / ADR-0072): one parser for
            // both link namespaces — `SpiralLink.matrixLinkTarget`
            // resolves our own spiral.md smart links and, inbound only,
            // the matrix.to permalinks the Matrix wire format uses.
            // `ElementWebURLParser` is gone — there is no Spiral web
            // client and we never link to app.element.io.
            MatrixLinkParser(),
            InviteLinkParser(),
            CatalogLinkParser(), // AGENT-PLATFORM (decision 111)
            FeedLinkParser(), // AGENT-PLATFORM: feed (Brief 0082)
            // AGENT-PLATFORM (Brief 0083 L1b): no AccountProvisioningURLParser.
            OAuthCallbackURLParser(redirectURL: appSettings.oAuthRedirectURL)
        ]
    }
    
    func route(from url: URL) -> AppRoute? {
        for parser in urlParsers {
            if let appRoute = parser.route(from: url) {
                return appRoute
            }
        }
        
        return nil
    }
}

// MARK: - URL Parsers

// AGENT-PLATFORM (Brief 0083 L1b): no note on Element's missing universal link parsers.
/// Represents a type that can parse a `URL` into an `AppRoute`.
protocol URLParser {
    func route(from url: URL) -> AppRoute?
}

/// The parser for routes that come from app extensions such as the Share Extension.
private struct AppGroupURLParser: URLParser {
    func route(from url: URL) -> AppRoute? {
        guard let scheme = url.scheme,
              scheme == InfoPlistReader.app.appScheme,
              url.pathComponents.last == ShareExtensionConstants.urlPath else {
            return nil
        }
        
        guard let query = url.query(percentEncoded: false),
              let queryData = query.data(using: .utf8) else {
            MXLog.error("Failed processing share parameters")
            return nil
        }
        
        do {
            let payload = try JSONDecoder().decode(ShareExtensionPayload.self, from: queryData)
            return .share(payload)
        } catch {
            MXLog.error("Failed decoding share payload with error: \(error)")
            return nil
        }
    }
}

/// AGENT-PLATFORM (Brief 0060 / ADR-0072): routes every Matrix link the
/// app can receive — our own `spiral.md` smart links and their
/// `spiral://` scheme twins (used by the link landing page's open
/// button, because universal links don't fire on same-domain taps in
/// Safari), plus inbound matrix.to permalinks from message content.
///
/// `.user` maps to the upstream `.userProfile` route, which lands on
/// Element's canonical profile screen — the person, their MXID and a
/// way to message them. That is what a shared profile link promises.
private struct MatrixLinkParser: URLParser {
    func route(from url: URL) -> AppRoute? {
        switch SpiralLink.matrixLinkTarget(from: url) {
        case .user(let userID):
            return .userProfile(userID: userID)
        case .roomAlias(let alias):
            return .roomAlias(alias)
        case .room(let roomID):
            return .room(roomID: roomID, via: [])
        case .event(let roomID, let eventID):
            // A room alias here means the permalink addressed the room
            // by alias; the alias-flavoured route keeps that shape.
            if roomID.hasPrefix("#") {
                return .eventOnRoomAlias(eventID: eventID, alias: roomID)
            }
            return .event(eventID: eventID, roomID: roomID, via: [])
        case .none:
            return nil
        }
    }
}

/// AGENT-PLATFORM (Brief 0073 / ADR-0008): `spiral.md/join/{token}` and
/// `spiral://join/{token}` — an invitation to register.
private struct InviteLinkParser: URLParser {
    func route(from url: URL) -> AppRoute? {
        SpiralInviteLink.parse(url).map { .inviteLink($0) }
    }
}

/// AGENT-PLATFORM (decision 111): `spiral.md/catalog/<id>` and
/// `spiral:///catalog/<id>` — a post catalogue template, with no chat yet.
private struct CatalogLinkParser: URLParser {
    func route(from url: URL) -> AppRoute? {
        SpiralCatalogLink.parse(url).map { .catalogTemplate(templateID: $0.templateID, roomID: nil) }
    }
}

/// AGENT-PLATFORM: feed (Brief 0082): `spiral.md/feed/<id>` and
/// `spiral:///feed/<id>` — one feed post.
private struct FeedLinkParser: URLParser {
    func route(from url: URL) -> AppRoute? {
        SpiralFeedLink.parse(url).map { .feedPost(postID: $0.postID) }
    }
}

// AGENT-PLATFORM (Brief 0083 L1b): no AccountProvisioningURLParser, Element's mobile.element.io links.

/// The parser for the OAuth callback URL. This always returns an `.oAuthCallback`.
struct OAuthCallbackURLParser: URLParser {
    let redirectURL: URL
    
    func route(from url: URL) -> AppRoute? {
        guard url.absoluteString.starts(with: redirectURL.absoluteString) else { return nil }
        return .oAuthCallback(url: url)
    }
}
