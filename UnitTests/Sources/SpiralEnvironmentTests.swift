//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0084): the Staging build's endpoints and mark.
//

import Foundation
@testable import Spiral
import Testing

struct SpiralEnvironmentTests {
    @Test
    func aTestBuildIsProd() {
        #expect(SpiralEnvironment.current == .production)
        #expect(SpiralLink.serverName == "spiral.md")
    }
    
    @Test
    func prodEndpointsStayAsTheyWere() {
        let settings = AppSettings.volatile()
        
        #expect(settings.accountProviders == [.managed(serverName: "spiral.md", baseURL: "https://spiral.md")])
        #expect(settings.agentPlatformBaseURL.absoluteString == "https://spiral.md")
        #expect(settings.pushGatewayNotifyEndpoint.absoluteString == "https://spiral.md/_matrix/push/v1/notify")
        #expect(settings.oAuthRedirectURL.absoluteString == "https://spiral.md/oidc/login")
        #expect(settings.websiteURL.absoluteString == "https://spiral.md/brand/")
        #expect(settings.logoURL.absoluteString == "https://spiral.md/brand/logo.png")
        #expect(settings.acceptableUseURL.absoluteString == "https://spiral.md/brand/terms")
        #expect(settings.privacyURL.absoluteString == "https://spiral.md/brand/privacy")
        #expect(settings.interactiveCatalogURL.absoluteString == "https://spiral.md/catalog/")
    }
    
    @Test
    func stagingEndpointsFollowTheContract() {
        let staging = SpiralEnvironment.staging
        
        #expect(staging.serverName == "staging.spiral.md")
        #expect(staging.baseURL.absoluteString == "https://staging.spiral.md")
        #expect(staging.catalogURL.absoluteString == "https://staging.spiral.md/catalog/")
    }
    
    @Test
    func theDevStackKeepsItsValues() {
        let localDev = SpiralEnvironment.localDev
        
        #expect(localDev.serverName == "localhost")
        #expect(localDev.accountProvider == .generic("http://localhost:8008"))
        #expect(localDev.platformURL.absoluteString == "https://synapse.localhost")
    }
    
    /// The dev stack only ever moved the homeserver, the platform and the server name.
    @Test
    func theDevStackKeepsProdsPublicSite() {
        let localDev = SpiralEnvironment.localDev
        let production = SpiralEnvironment.production
        
        #expect(localDev.baseURL == production.baseURL)
        #expect(localDev.oAuthRedirectURL == production.oAuthRedirectURL)
        #expect(localDev.websiteURL == production.websiteURL)
        #expect(localDev.catalogURL == production.catalogURL)
        #expect(localDev.screenMark == nil)
    }
    
    /// The NSE doesn't see the launch environment, so a dev account finds the dev stack by its user ID.
    @Test
    func aDevAccountReachesTheDevStackFromAnyLaunch() {
        let settings = AppSettings.volatile()
        
        #expect(settings.agentPlatformBaseURL(forUserID: "@alice:localhost").absoluteString == "https://synapse.localhost")
        #expect(settings.agentPlatformBaseURL(forUserID: "@alice:spiral.md").absoluteString == "https://spiral.md")
    }
    
    /// MAS rejects a client whose metadata spans hosts, so sign-in depends on this.
    @Test
    func stagingOAuthMetadataSharesOneHost() {
        let staging = SpiralEnvironment.staging
        
        for url in [staging.oAuthRedirectURL, staging.websiteURL, staging.logoURL, staging.acceptableUseURL, staging.privacyURL] {
            #expect(url.host() == "staging.spiral.md")
        }
    }
    
    @Test
    func onlyStagingIsMarked() {
        #expect(SpiralEnvironment.production.screenMark == nil)
        #expect(SpiralEnvironment.production.markedVersionLine("Version 1.0.2 (3)") == "Version 1.0.2 (3)")
        #expect(SpiralEnvironment.staging.screenMark == "Staging")
        #expect(SpiralEnvironment.staging.markedVersionLine("Version 1.0.2 (3)") == "Staging · Version 1.0.2 (3)")
    }
}

#if DEBUG
/// A dev-stack launch, end to end. Skipped unless the host is started with the flag:
/// `TEST_RUNNER_SPIRAL_DEV_STACK=1 run-unit-tests.sh -only-testing:UnitTests/SpiralDevStackLaunchTests`.
struct SpiralDevStackLaunchTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPIRAL_DEV_STACK"] == "1"))
    func aFlaggedDebugBuildPointsAtTheDevStack() {
        let settings = AppSettings.volatile()
        
        #expect(SpiralEnvironment.current == .localDev)
        #expect(SpiralLink.serverName == "localhost")
        #expect(SpiralLink.user(localpart: "alice").webURL?.absoluteString == "https://localhost/@alice")
        #expect(settings.accountProviders == [.generic("http://localhost:8008")])
        #expect(settings.agentPlatformBaseURL.absoluteString == "https://synapse.localhost")
        #expect(settings.pushGatewayNotifyEndpoint.absoluteString == "https://spiral.md/_matrix/push/v1/notify")
        #expect(settings.oAuthRedirectURL.absoluteString == "https://spiral.md/oidc/login")
    }
}
#endif

#if SPIRAL_STAGING
/// The build's wiring, which a plain test build can't see. UnitTests needs `DEBUG`, so this runs in Debug with the condition added:
/// docs/project/CODEBASE/07-build-and-codegen.md.
struct SpiralStagingBuildTests {
    @Test
    func aStagingBuildPointsAtStaging() {
        let settings = AppSettings.volatile()
        
        #expect(SpiralEnvironment.current == .staging)
        #expect(settings.agentPlatformBaseURL.absoluteString == "https://staging.spiral.md")
        #expect(settings.agentPlatformBaseURL(forUserID: "@alice:staging.spiral.md").absoluteString == "https://staging.spiral.md")
        #expect(SpiralLink.serverName == "staging.spiral.md")
        #expect(SpiralLink.user(localpart: "alice").webURL?.absoluteString == "https://staging.spiral.md/@alice")
        #expect(settings.pushGatewayNotifyEndpoint.absoluteString == "https://staging.spiral.md/_matrix/push/v1/notify")
        #expect(settings.oAuthRedirectURL.absoluteString == "https://staging.spiral.md/oidc/login")
        #expect(settings.oAuthConfiguration.clientURI.host() == "staging.spiral.md")
        #expect(settings.interactiveCatalogURL.absoluteString == "https://staging.spiral.md/catalog/")
        #expect(settings.accountProviders == [.managed(serverName: "staging.spiral.md", baseURL: "https://staging.spiral.md")])
        #expect(SpiralInviteLink(token: "TESTFLIGHT")?.webURL.absoluteString == "https://staging.spiral.md/join/TESTFLIGHT")
    }
}
#endif
