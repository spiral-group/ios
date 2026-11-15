//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, question 412): `SpiralAppPost.supportedRuntimes`
// is the app's promise that a post on that level links. The names a level
// added live in the bundled shell, pinned separately in `project.yml`, so a
// shell tag older than the level would list and mount posts that then fail
// to import. This ties the two together: every level the app claims must
// find its names exported by the shell it ships.
//

import Foundation
@testable import Spiral
import SpiralAppShell
import Testing

struct SpiralAppRuntimeLevelTests {
    /// The names each runtime level added, by the module path a post imports.
    private static let namesAddedByLevel: [String: [String: Set<String>]] = [
        "1.2": ["/runtime/v1/play.js": ["animate", "spring", "EASE", "burst", "crossings"],
                "/runtime/v1/react.js": ["useLayoutEffect"]]
    ]

    @Test
    func theBundledShellExportsEveryClaimedLevelsNames() throws {
        for level in SpiralAppPost.supportedRuntimes.sorted() {
            // Levels before this check carry no entry; a new one must add its names.
            #expect(["1", "1.1"].contains(level) || Self.namesAddedByLevel[level] != nil, "Runtime \(level) lists no names to check")
            for (path, names) in Self.namesAddedByLevel[level] ?? [:] {
                let file = try #require(SpiralAppShell.bundledResource(forPath: path), "The shell doesn't carry \(path)")
                let exported = try Self.exportedNames(of: String(contentsOf: file, encoding: .utf8))
                let missing = names.subtracting(exported).sorted()
                #expect(missing.isEmpty, "Runtime \(level) needs \(missing) from \(path); the shell is \(SpiralAppShell.version)")
            }
        }
    }

    /// Shell 1.0.3's two modules, the last tag before runtime 1.2: the check
    /// must refuse it, and must read a bundle's export list rather than any
    /// mention of a name.
    @Test
    func theCheckRefusesTheShellBeforeRuntime12() {
        let play = "const d=1,o=2;export{d as fitCanvas,o as strokePath};"
        let react = "const q=Tl.useLayoutEffect;export{Uh as useCallback,Hh as useEffect,Bh as useMemo};"

        #expect(Self.exportedNames(of: play) == ["fitCanvas", "strokePath"])
        #expect(!Self.exportedNames(of: react).contains("useLayoutEffect"))
        #expect(Self.exportedNames(of: "export{a as animate}") == ["animate"])
        #expect(Self.exportedNames(of: "export{EASE,burst}") == ["EASE", "burst"])
    }

    // MARK: - Helpers

    /// The names a bundled ES module's `export { … }` lists give out.
    private static func exportedNames(of source: String) -> Set<String> {
        var names: Set<String> = []
        for match in source.matches(of: /export\s*\{([^}]*)\}/) {
            for item in match.1.split(separator: ",") {
                let parts = item.split(whereSeparator: \.isWhitespace)
                if let name = parts.last, !name.isEmpty {
                    names.insert(String(name))
                }
            }
        }
        return names
    }
}
