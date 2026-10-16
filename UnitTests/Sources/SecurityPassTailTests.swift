//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0076, audit tail).
//

@testable import ElementX
import Foundation
import MatrixRustSDKMocks
import Testing

struct SecurityPassTailTests {
    @Test
    func theInvitationIsAppendedWithoutReencodingTheSDKQuery() throws {
        let sdkData = OAuthAuthorizationDataSDKMock()
        sdkData.loginUrlReturnValue = "https://spiral.md/auth/authorize?state=a%2Bb&redirect_uri=spiral%3A%2F%2Foidc"
        let proxy = OAuthAuthorizationDataProxy(underlyingData: sdkData, inviteToken: "TESTFLIGHT")
        
        let url = proxy.url.absoluteString
        #expect(url.contains("state=a%2Bb"), "the SDK's %2B must survive")
        #expect(url.contains("redirect_uri=spiral%3A%2F%2Foidc"))
        #expect(url.hasSuffix("&spiral_invite=TESTFLIGHT"))
    }
    
    @Test
    func withoutAnInvitationTheURLIsUntouched() {
        let sdkData = OAuthAuthorizationDataSDKMock()
        sdkData.loginUrlReturnValue = "https://spiral.md/auth/authorize?state=a%2Bb"
        #expect(OAuthAuthorizationDataProxy(underlyingData: sdkData, inviteToken: nil).url.absoluteString
            == "https://spiral.md/auth/authorize?state=a%2Bb")
    }
    
    // Brief 0073 re-run: the page opens the Register tab from the intent,
    // with or without an invitation.
    @Test
    func aRegistrationSaysSoEvenWithoutAnInvitation() {
        let sdkData = OAuthAuthorizationDataSDKMock()
        sdkData.loginUrlReturnValue = "https://spiral.md/auth/authorize?state=a%2Bb"
        #expect(OAuthAuthorizationDataProxy(underlyingData: sdkData, inviteToken: nil, isRegistration: true).url.absoluteString
            == "https://spiral.md/auth/authorize?state=a%2Bb&spiral_flow=register")
        #expect(OAuthAuthorizationDataProxy(underlyingData: sdkData, inviteToken: "TESTFLIGHT", isRegistration: true).url.absoluteString
            == "https://spiral.md/auth/authorize?state=a%2Bb&spiral_invite=TESTFLIGHT&spiral_flow=register")
    }
    
    @Test
    func ourOwnSchemeIsRecognisedSoItIsNeverBouncedToTheBrowser() throws {
        #expect(Application.isOwnScheme(try #require(URL(string: "spiral://phrase-changed?result=x")), appScheme: "spiral"))
        #expect(Application.isOwnScheme(try #require(URL(string: "SPIRAL://unknown")), appScheme: "spiral"))
        #expect(!Application.isOwnScheme(try #require(URL(string: "https://spiral.md/@a")), appScheme: "spiral"))
    }
}
