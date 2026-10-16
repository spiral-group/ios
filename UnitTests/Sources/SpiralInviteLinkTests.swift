//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0073 / ADR-0008 — invite links. The token
// grammar mirrors `identity-login/src/services/invites-core.ts`.
//

@testable import ElementX
import Foundation
import Testing

struct SpiralInviteLinkTests {
    @Test
    func buildsBothURLForms() throws {
        let link = try #require(SpiralInviteLink(token: "Qz8Hf72Kd91"))
        #expect(link.webURL.absoluteString == "https://spiral.md/join/Qz8Hf72Kd91")
        #expect(link.schemeURL.absoluteString == "spiral://join/Qz8Hf72Kd91")
    }
    
    @Test
    func parsesUniversalAndSchemeLinks() throws {
        #expect(SpiralInviteLink.parse(try #require(URL(string: "https://spiral.md/join/Qz8Hf72Kd91")))?.token == "Qz8Hf72Kd91")
        #expect(SpiralInviteLink.parse(try #require(URL(string: "https://SPIRAL.md/join/TESTFLIGHT")))?.token == "TESTFLIGHT")
        #expect(SpiralInviteLink.parse(try #require(URL(string: "spiral://join/Qz8Hf72Kd91")))?.token == "Qz8Hf72Kd91")
        #expect(SpiralInviteLink.parse(try #require(URL(string: "spiral:///join/Qz8Hf72Kd91")))?.token == "Qz8Hf72Kd91")
    }
    
    @Test
    func refusesEverythingThatIsNotAnInvitation() throws {
        #expect(SpiralInviteLink.parse(try #require(URL(string: "https://spiral.md/@alice"))) == nil)
        #expect(SpiralInviteLink.parse(try #require(URL(string: "https://spiral.md/join"))) == nil)
        #expect(SpiralInviteLink.parse(try #require(URL(string: "https://spiral.md/join/a/b"))) == nil)
        #expect(SpiralInviteLink.parse(try #require(URL(string: "https://evil.example/join/Qz8Hf72Kd91"))) == nil)
        #expect(SpiralInviteLink.parse(try #require(URL(string: "https://spiral.md/join/abc"))) == nil, "too short")
        #expect(SpiralInviteLink.parse(try #require(URL(string: "https://spiral.md/join/has%20space"))) == nil)
    }
    
    @Test
    func parsesWhateverWasPasted() {
        #expect(SpiralInviteLink.parse(pastedText: " https://spiral.md/join/Qz8Hf72Kd91 ")?.token == "Qz8Hf72Kd91")
        #expect(SpiralInviteLink.parse(pastedText: "spiral.md/join/Qz8Hf72Kd91")?.token == "Qz8Hf72Kd91")
        #expect(SpiralInviteLink.parse(pastedText: "spiral://join/TESTFLIGHT")?.token == "TESTFLIGHT")
        #expect(SpiralInviteLink.parse(pastedText: "Qz8Hf72Kd91")?.token == "Qz8Hf72Kd91")
        #expect(SpiralInviteLink.parse(pastedText: "") == nil)
        #expect(SpiralInviteLink.parse(pastedText: "hello world") == nil)
        #expect(SpiralInviteLink.parse(pastedText: "https://spiral.md/@alice") == nil)
    }
    
    @Test
    func routesThroughTheAppRouteParser() throws {
        let parser = AppRouteURLParser(appSettings: AppSettings.volatile())
        let route = parser.route(from: try #require(URL(string: "https://spiral.md/join/Qz8Hf72Kd91")))
        #expect(route == .inviteLink(try #require(SpiralInviteLink(token: "Qz8Hf72Kd91"))))
        #expect(route?.isAuthenticationRoute == true)
        
        // Profile links still resolve to the profile, not an invitation.
        #expect(parser.route(from: try #require(URL(string: "https://spiral.md/@alice"))) == .userProfile(userID: "@alice:spiral.md"))
    }
    
    @Test
    func authorizationURLCarriesTheInvitation() throws {
        // The SDK's `OAuthAuthorizationData` cannot be constructed in tests;
        // the query-appending logic is exercised through URLComponents the
        // same way the proxy does it.
        var components = try #require(URLComponents(string: "https://spiral.md/auth/authorize?client_id=c&state=s"))
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: SpiralInviteLink.authorizationQueryParameter, value: "Qz8Hf72Kd91")]
        #expect(components.url?.absoluteString == "https://spiral.md/auth/authorize?client_id=c&state=s&spiral_invite=Qz8Hf72Kd91")
    }
    
    @Test
    func pendingInviteRoundTripsThroughAppSettings() {
        let appSettings = AppSettings.volatile()
        #expect(appSettings.pendingInvite == nil)
        appSettings.pendingInvite = PendingInvite(token: "Qz8Hf72Kd91", inviterDisplayName: "Andrii", inviterUserID: "@alice:spiral.md")
        #expect(appSettings.pendingInvite?.inviterDisplayName == "Andrii")
        #expect(appSettings.pendingInvite?.link?.webURL.absoluteString == "https://spiral.md/join/Qz8Hf72Kd91")
        appSettings.pendingInvite = nil
        #expect(appSettings.pendingInvite == nil)
    }
    
    @Test
    func myInviteCountsSeats() throws {
        let link = try #require(SpiralInviteLink(token: "Qz8Hf72Kd91"))
        #expect(MyInvite(link: link, maxUses: 10, used: 3, expiresAt: nil).seatsLeft == 7)
        #expect(MyInvite(link: link, maxUses: 10, used: 10, expiresAt: nil).isExhausted)
        #expect(MyInvite(link: link, maxUses: 10, used: 12, expiresAt: nil).seatsLeft == 0, "never negative")
    }
}
