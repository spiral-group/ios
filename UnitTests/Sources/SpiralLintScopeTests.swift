//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
import Testing

// AGENT-PLATFORM (Brief 0083 L1c): the guard behind the spiral_raw_* rules in
// `.swiftlint.yml`. They apply only to the folders in its `&spiral_code` list,
// and SwiftLint says nothing about a pattern that matches no file, so a renamed
// folder would fall out of the rules unnoticed. Nor does it say anything about
// a rule that only warns: below `severity: error`, or with no severity at all
// (a custom rule's default is a warning), a rule no longer fails the build.

struct SpiralLintScopeTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // UnitTests
        .deletingLastPathComponent() // repo

    private static let spiralRules: Set = ["spiral_raw_font", "spiral_raw_color", "spiral_raw_corner_radius"]

    @Test
    func everyScopedFolderExists() throws {
        let folders = try Self.scopedFolders()
        #expect(folders.count >= 20, "Parsed: \(folders)")

        let missing = folders.filter(Self.matchesNothing)
        #expect(missing.isEmpty, "The spiral_raw_* rules name folders that don't exist: \(missing)")
    }

    /// A pattern entry (`MediaViewer\w*\.swift`) stays open to new files, but one
    /// that matches no file is as dead as a missing folder.
    @Test
    func aPatternEntryMustMatchAFile() {
        #expect(!Self.matchesNothing(#"ElementX/Sources/Screens/FilePreviewScreen/View/MediaViewer\w*\.swift"#))
        #expect(Self.matchesNothing(#"ElementX/Sources/Screens/FilePreviewScreen/View/NoSuchViewer\w*\.swift"#))
        #expect(Self.matchesNothing(#"ElementX/Sources/NoSuchFolder/\w+\.swift"#))
    }

    @Test
    func everySpiralRuleUsesTheScope() throws {
        for rule in Self.spiralRules {
            let scope = try #require(Self.ruleLines(rule).first)
            #expect(scope.hasSuffix("&spiral_code") || scope.hasSuffix("*spiral_code"), "\(rule) is not scoped to Spiral's code: \(scope)")
        }
    }

    @Test
    func everySpiralRuleFailsTheBuild() throws {
        for rule in Self.spiralRules {
            let severity = try Self.ruleLines(rule).first { $0.hasPrefix("severity:") }
            #expect(severity == "severity: error", "\(rule) doesn't fail the build: \(severity ?? "no severity, so a warning")")
        }
    }

    // MARK: - Helpers

    /// The lines of a custom rule in `.swiftlint.yml`, trimmed, up to the blank line that ends it.
    private static func ruleLines(_ rule: String) throws -> [String] {
        let config = try String(contentsOf: repoRoot.appendingPathComponent(".swiftlint.yml"), encoding: .utf8)
        let body = try #require(config.components(separatedBy: "\n  \(rule):\n").dropFirst().first, "\(rule) is not in .swiftlint.yml")
        return body.components(separatedBy: "\n\n")[0]
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Whether no file is covered by a `&spiral_code` entry. SwiftLint reads every
    /// entry as a regex over the file's path; a plain path is checked as a path, an
    /// entry with regex metacharacters (`.` aside, file names have it) as a regex.
    private static func matchesNothing(_ entry: String) -> Bool {
        guard entry.rangeOfCharacter(from: CharacterSet(charactersIn: #"\*+?[]{}^$"#)) != nil else {
            return !FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(entry).path)
        }
        guard let regex = try? NSRegularExpression(pattern: entry) else { return true }

        // Only the folder before the first metacharacter can hold a match.
        let literalPrefix = entry.prefix { !#"\*+?[]{}^$("#.contains($0) }
        let folder = repoRoot.appendingPathComponent(literalPrefix.lastIndex(of: "/").map { String(literalPrefix[...$0]) } ?? "")
        guard let files = FileManager.default.enumerator(atPath: folder.path) else { return true }

        let base = folder.path.dropFirst(repoRoot.path.count)
        return !files.contains { file in
            let path = "\(base)/\(file)"
            return regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
        }
    }

    /// The entries of the `&spiral_code` list as SwiftLint reads them (YAML's `\\`
    /// unescaped), each `(a|b)` group expanded.
    private static func scopedFolders() throws -> [String] {
        let config = try String(contentsOf: repoRoot.appendingPathComponent(".swiftlint.yml"), encoding: .utf8)
        let lines = config.components(separatedBy: "\n")
            .drop { !$0.hasSuffix("&spiral_code") }
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") }

        return lines.prefix { $0.hasPrefix("- \"") }
            .map { String($0.dropFirst(3).dropLast()).replacingOccurrences(of: #"\\"#, with: #"\"#) }
            .flatMap(expandingGroup)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    }

    private static func expandingGroup(_ pattern: String) -> [String] {
        guard let open = pattern.firstIndex(of: "("), let close = pattern.firstIndex(of: ")") else { return [pattern] }
        let prefix = pattern[..<open]
        let suffix = pattern[pattern.index(after: close)...]
        return pattern[pattern.index(after: open)..<close]
            .split(separator: "|")
            .map { "\(prefix)\($0)\(suffix)" }
    }
}
