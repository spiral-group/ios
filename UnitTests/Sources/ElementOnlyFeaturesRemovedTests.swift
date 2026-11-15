//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083 L1b part 2, decision 302): Element-only features
// stay removed. An upstream sync that brings one back fails here.
//

import Foundation
import MatrixRustSDKMocks
@testable import Spiral
import Testing

struct ElementOnlyFeaturesRemovedTests {
    /// Element Pro's check fetched `/.well-known/element/element.json` from every server it configured.
    @Test
    func configuringAServerFetchesNoElementWellKnownFile() async throws {
        let configuration = ClientFactoryMock.Configuration()
        let client = try #require(configuration.homeserverClients["matrix.org"])
        let service = AuthenticationService(userSessionManager: UserSessionManagerMock(.init()),
                                            encryptionKeyProvider: EncryptionKeyProvider(),
                                            clientFactory: ClientFactoryMock(configuration),
                                            appSettings: .volatile(),
                                            appHooks: AppHooks())
        
        try await service.configure(for: "matrix.org", flow: .login).get()
        
        #expect(client.getUrlUrlCallsCount == 0)
    }
    
    /// Element's account provisioning links were `mobile.element.io` URLs naming a server and a login hint.
    @Test
    func provisioningLinksAreNotRoutes() throws {
        let parser = AppRouteURLParser(appSettings: .volatile())
        let url = try #require(URL(string: "https://mobile.element.io/?account_provider=example.com&login_hint=alice"))
        
        #expect(parser.route(from: url) == nil)
    }
}
