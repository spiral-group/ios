//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 111): settings whose post catalogue is on disk,
// so a flow that reads it never reaches spiral.md from a test.
//

import Foundation
@testable import Spiral

extension AppSettings {
    /// `interactiveCatalogURL` is read once, at init, from the debug
    /// override a simulator uses (`-SpiralCatalogURL`); it is set only for
    /// that init, so no other settings see it.
    static func volatile(catalogURL: URL) -> AppSettings {
        let key = "SpiralCatalogURL"
        UserDefaults.standard.set(catalogURL.absoluteString, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        return volatile()
    }

    /// A catalogue directory holding `index` as its `index.json`, or nothing.
    static func catalogueFixture(index: String?) throws -> URL {
        let base = URL.temporaryDirectory.appending(path: "catalog-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let index {
            try index.write(to: base.appending(path: "index.json"), atomically: true, encoding: .utf8)
        }
        return base
    }
}
