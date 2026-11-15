//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct AppRouteURLParserTests {
    var appSettings: AppSettings
    var appRouteURLParser: AppRouteURLParser
    
    init() {
        appSettings = AppSettings.volatile()
        appRouteURLParser = AppRouteURLParser(appSettings: appSettings)
    }
    
    @Test
    func oAuthCallbackRoute() {
        // Given an OAuth callback for this app.
        let callbackURL = appSettings.oAuthRedirectURL.appending(queryItems: [URLQueryItem(name: "state", value: "12345"),
                                                                              URLQueryItem(name: "code", value: "67890")])
        
        // When parsing that route.
        let route = appRouteURLParser.route(from: callbackURL)
        
        // Then it should be considered a valid OAuth callback.
        #expect(route == .oAuthCallback(url: callbackURL))
    }
    
    @Test
    func oAuthCallbackAppVariantRoute() {
        // Given an OAuth callback for a different app variant.
        let callbackURL = appSettings.oAuthRedirectURL
            .deletingLastPathComponent()
            .appending(component: "io.element.elementz")
            .appending(queryItems: [URLQueryItem(name: "state", value: "12345"),
                                    URLQueryItem(name: "code", value: "67890")])
        
        // When parsing that route in this app.
        let route = appRouteURLParser.route(from: callbackURL)
        
        // Then the route shouldn't be considered valid and should be ignored.
        #expect(route == nil)
    }
    
    // AGENT-PLATFORM (Brief 0060 / ADR-0072): matrix.to parsing is kept
    // READ-ONLY for bridge/legacy inbound content (the mautrix bridges
    // format every mention in message HTML as a matrix.to link), so
    // these two regression tests stay.
    @Test
    func matrixUserURL() throws {
        let userID = "@test:matrix.org"
        let url = try #require(URL(string: "https://matrix.to/#/\(userID)"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .userProfile(userID: userID))
    }
    
    @Test
    func matrixRoomIdentifierURL() throws {
        let id = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        let url = try #require(URL(string: "https://matrix.to/#/\(id)"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .room(roomID: id, via: []))
    }
    
    // MARK: - Spiral smart links (Brief 0060)
    
    @Test
    func spiralProfileURL() throws {
        let url = try #require(URL(string: "https://spiral.md/@telegram_123456789"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .userProfile(userID: "@telegram_123456789:spiral.md"))
    }
    
    @Test
    func spiralRoomAliasURL() throws {
        let url = try #require(URL(string: "https://spiral.md/c/general"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .roomAlias("#general:spiral.md"))
    }
    
    @Test
    func spiralRoomURL() throws {
        let url = try #require(URL(string: "https://spiral.md/!PGBmctdJNFwoAOHtvM"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .room(roomID: "!PGBmctdJNFwoAOHtvM:spiral.md", via: []))
    }
    
    @Test
    func spiralMessageURL() throws {
        let event = "WUzJ-abZT4jooldYohZlI8ueLnHGrng5De38aiOg31M"
        let url = try #require(URL(string: "https://spiral.md/!PGBmctdJNFwoAOHtvM/$\(event)"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .event(eventID: "$\(event)", roomID: "!PGBmctdJNFwoAOHtvM:spiral.md", via: []))
    }
    
    @Test
    func spiralCustomSchemeURL() throws {
        let url = try #require(URL(string: "spiral:///@telegram_123456789"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .userProfile(userID: "@telegram_123456789:spiral.md"))
    }
    
    /// There is no Spiral web client, so Element Web links are no longer
    /// intercepted — they open in the browser like any other URL.
    @Test
    func elementWebURLIsNotHandled() throws {
        let url = try #require(URL(string: "https://app.element.io/#/room/!abc:matrix.org"))
        
        #expect(appRouteURLParser.route(from: url) == nil)
    }
    
    /// Non-link paths on our own domain must stay in the browser.
    @Test
    func spiralNonLinkPathsAreNotHandled() throws {
        for path in ["/brand/privacy", "/api/v1/agents", "/", "/@", "/@UPPER", "/general"] {
            let url = try #require(URL(string: "https://spiral.md\(path)"))
            #expect(appRouteURLParser.route(from: url) == nil, "\(path) must not route")
        }
    }
    
    // MARK: - AGENT-PLATFORM: post catalogue links (decision 111)
    
    @Test
    func catalogueTemplateLinksAskWhichChat() throws {
        for string in ["https://spiral.md/catalog/poll", "spiral:///catalog/poll", "https://spiral.md/catalog/poll/"] {
            let url = try #require(URL(string: string))
            #expect(appRouteURLParser.route(from: url) == .catalogTemplate(templateID: "poll", roomID: nil), "\(string)")
        }
    }
    
    /// The index and the catalogue's files are web pages and files, not links
    /// into the app, and the other links keep their routes.
    @Test
    func catalogueLinksLeaveTheRestAlone() throws {
        for path in ["/catalog", "/catalog/", "/catalog/index.json", "/catalog/poll/app.jsx"] {
            let url = try #require(URL(string: "https://spiral.md\(path)"))
            #expect(appRouteURLParser.route(from: url) == nil, "\(path) must not route")
        }
        #expect(try appRouteURLParser.route(from: #require(URL(string: "https://spiral.md/@red"))) == .userProfile(userID: "@red:spiral.md"))
        let invite = try #require(SpiralInviteLink(token: "TESTFLIGHT"))
        #expect(appRouteURLParser.route(from: invite.webURL) == .inviteLink(invite))
    }
    
    /// Signed out, a link that is not an authentication route is stored and
    /// replayed once the session starts (`AppCoordinator.storedAppRoute`).
    @Test
    func aCatalogueLinkIsReplayedAfterSignIn() {
        #expect(!AppRoute.catalogTemplate(templateID: "poll", roomID: nil).isAuthenticationRoute)
    }
}
