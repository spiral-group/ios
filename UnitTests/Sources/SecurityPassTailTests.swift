//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0076, audit tail).
//

import Foundation
import MatrixRustSDKMocks
@testable import Spiral
import Testing

struct SecurityPassTailTests {
    @Test
    func theInvitationIsAppendedWithoutReencodingTheSDKQuery() throws {
        let sdkData = OAuthAuthorizationDataSDKMock()
        sdkData.loginUrlReturnValue = "https://spiral.md/auth/authorize?state=a%2Bb&redirect_uri=spiral%3A%2F%2Foidc"
        let proxy = OAuthAuthorizationDataProxy(underlyingData: sdkData, homeserver: "example.com", inviteToken: "TESTFLIGHT")
        
        let url = proxy.url.absoluteString
        #expect(url.contains("state=a%2Bb"), "the SDK's %2B must survive")
        #expect(url.contains("redirect_uri=spiral%3A%2F%2Foidc"))
        #expect(url.hasSuffix("&spiral_invite=TESTFLIGHT"))
    }
    
    @Test
    func withoutAnInvitationTheURLIsUntouched() {
        let sdkData = OAuthAuthorizationDataSDKMock()
        sdkData.loginUrlReturnValue = "https://spiral.md/auth/authorize?state=a%2Bb"
        #expect(OAuthAuthorizationDataProxy(underlyingData: sdkData, homeserver: "example.com", inviteToken: nil).url.absoluteString
            == "https://spiral.md/auth/authorize?state=a%2Bb")
    }
    
    // Brief 0073 re-run: the page opens the Register tab from the intent,
    // with or without an invitation.
    @Test
    func aRegistrationSaysSoEvenWithoutAnInvitation() {
        let sdkData = OAuthAuthorizationDataSDKMock()
        sdkData.loginUrlReturnValue = "https://spiral.md/auth/authorize?state=a%2Bb"
        #expect(OAuthAuthorizationDataProxy(underlyingData: sdkData, homeserver: "example.com", inviteToken: nil, isRegistration: true).url.absoluteString
            == "https://spiral.md/auth/authorize?state=a%2Bb&spiral_flow=register")
        #expect(OAuthAuthorizationDataProxy(underlyingData: sdkData, homeserver: "example.com", inviteToken: "TESTFLIGHT", isRegistration: true).url.absoluteString
            == "https://spiral.md/auth/authorize?state=a%2Bb&spiral_invite=TESTFLIGHT&spiral_flow=register")
    }
    
    // The real Info.plist: `spiral` is the second scheme, after the bundle identifier.
    @Test
    func everySchemeTheAppRegistersIsItsOwnSoItIsNeverBouncedToTheBrowser() throws {
        #expect(try Application.isOwnScheme(#require(URL(string: "spiral://unknown-path"))))
        #expect(try Application.isOwnScheme(#require(URL(string: "SPIRAL://phrase-changed?result=x"))))
        #expect(try Application.isOwnScheme(#require(URL(string: "\(InfoPlistReader.app.baseBundleIdentifier)://share"))))
        #expect(try !Application.isOwnScheme(#require(URL(string: "https://spiral.md/@a"))))
    }
}
