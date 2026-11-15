//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM: App Review F1 (decision 252). Spiral ships without location
// sharing: no purpose string, no MapLibre in the bundle, and a session location
// manager that never asks for access.

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct SpiralNoLocationSharingTests {
    @Test
    func theAppDeclaresNoLocationPurposeString() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil,
                "The host app's Info.plist should be the one read.")
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") == nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") == nil)
    }

    @Test
    func noLanguageShipsALocationPurposeString() throws {
        let bundleURL = Bundle.main.bundleURL
        let enumerator = try #require(FileManager.default.enumerator(at: bundleURL, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in enumerator where url.lastPathComponent == "InfoPlist.strings" {
            let strings = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(url.path) should be readable.")
            #expect(!strings.keys.contains { $0.hasPrefix("NSLocation") }, "\(url.deletingLastPathComponent().lastPathComponent) has a location string.")
            checked += 1
        }
        #expect(checked > 1, "The app should ship its InfoPlist.strings.")
    }
    
    /// The strings download would otherwise bring `NSLocation*` back from upstream's `InfoPlist.json`.
    @Test
    func localazyNeverDownloadsALocationPurposeString() throws {
        let localazy = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(component: "localazy.json")
        let configuration = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: localazy)) as? [String: Any])
        let conversion = try #require(configuration["conversion"] as? [String: Any])
        let actions = try #require(conversion["actions"] as? [[String: Any]])
        let infoPlistActions = actions.filter { action in
            (action["conditions"] as? [String])?.contains { $0.contains("InfoPlist.json") } == true
        }
        
        #expect(!infoPlistActions.isEmpty)
        for action in infoPlistActions {
            #expect((action["excludeKeys"] as? [String])?.contains("REGEX:NSLocation.*") == true,
                    "Every InfoPlist action should exclude NSLocation*.")
        }
    }
    
    @Test
    func theAppEmbedsNoMap() throws {
        let frameworks = try #require(Bundle.main.privateFrameworksPath)
        #expect(!FileManager.default.fileExists(atPath: "\(frameworks)/MapLibre.framework"))
        #expect(!FileManager.default.fileExists(atPath: "\(frameworks)/MapLibreShim.framework"))
        #expect(MapLibreLoader.shim == nil)
    }

    @Test
    func locationSharingIsOff() {
        #expect(!AppSettings.bundledMapTilerConfiguration.isEnabled)
    }

    @Test
    func theSessionsLocationManagerReportsLocationAsRestricted() async {
        let manager = LiveLocationManager(appSettings: AppSettings.volatile())
        let service = LiveLocationServiceMock(.init(userID: "@alice:matrix.org"))
        service.actionsPublisher = PassthroughSubject<LiveLocationServiceAction, Never>().eraseToAnyPublisher()

        await waitForConfirmation("A restored share stops") { confirm in
            service.stopAllLiveLocationsClosure = { confirm() }
            manager.add(service)
        }
        #expect(service.authorizationStatusChangedToReceivedStatus == .restricted)
    }
}
