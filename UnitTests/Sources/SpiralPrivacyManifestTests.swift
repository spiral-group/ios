//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0078): the privacy manifests as they ship in the built app,
// against the App Store label in ~/Projects/docs/legal/app-store-privacy.md. An
// upstream sync that brings Element's manifest back fails here.

import Foundation
import Testing

struct SpiralPrivacyManifestTests {
    @Test
    func theAppDeclaresWhatSpiralCollects() throws {
        let manifest = try Self.manifest(at: Bundle.main.bundleURL)
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect(manifest["NSPrivacyTrackingDomains"] == nil)

        let entries = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = Set(entries.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        #expect(types == ["NSPrivacyCollectedDataTypeName",
                          "NSPrivacyCollectedDataTypeEmailsOrTextMessages",
                          "NSPrivacyCollectedDataTypePhotosorVideos",
                          "NSPrivacyCollectedDataTypeAudioData",
                          "NSPrivacyCollectedDataTypeOtherUserContent",
                          "NSPrivacyCollectedDataTypeUserID",
                          "NSPrivacyCollectedDataTypeDeviceID",
                          "NSPrivacyCollectedDataTypeOtherUsageData",
                          "NSPrivacyCollectedDataTypeOtherDiagnosticData"])
        #expect(entries.count == types.count)

        for entry in entries {
            let type = entry["NSPrivacyCollectedDataType"] as? String ?? "?"
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == true, "\(type)")
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false, "\(type)")
            #expect(entry["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"], "\(type)")
        }

        // CA92.1: CallKitServiceConstants keeps app-only data in UserDefaults.standard.
        #expect(try Self.reasons(in: manifest) == ["NSPrivacyAccessedAPICategoryUserDefaults": ["1C8F.1", "CA92.1"],
                                                   "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
                                                   "NSPrivacyAccessedAPICategoryDiskSpace": ["7D9E.1"],
                                                   "NSPrivacyAccessedAPICategorySystemBootTime": ["8FFB.1"]])
    }

    @Test
    func theShareExtensionShipsItsOwnManifest() throws {
        let manifest = try Self.manifest(at: Bundle.main.bundleURL.appending(path: "PlugIns/ShareExtension.appex"))
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        #expect(try Self.reasons(in: manifest) == ["NSPrivacyAccessedAPICategoryUserDefaults": ["1C8F.1"],
                                                   "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"]])
    }

    @Test
    func theNotificationExtensionKeepsItsManifest() throws {
        let manifest = try Self.manifest(at: Bundle.main.bundleURL.appending(path: "PlugIns/NSE.appex"))
        // The NSE compiles CallKitServiceConstants too.
        #expect(try Self.reasons(in: manifest)["NSPrivacyAccessedAPICategoryUserDefaults"] == ["1C8F.1", "CA92.1"])
    }

    // MARK: - Helpers

    private static func manifest(at bundleURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundleURL.appending(path: "PrivacyInfo.xcprivacy"))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private static func reasons(in manifest: [String: Any]) throws -> [String: [String]] {
        let entries = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var reasons = [String: [String]]()
        for entry in entries {
            let type = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            reasons[type] = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
        }
        return reasons
    }
}
