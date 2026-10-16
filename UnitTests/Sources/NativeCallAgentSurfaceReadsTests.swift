//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
import Testing

// AGENT-PLATFORM (Brief 0063 closeout): the architectural guard behind
// `NativeCallAgentPresentation`. A call surface reads agent facts ONLY
// through `viewState.agents`; the owner-scoped REST snapshot and the raw
// claims are inputs to the derive and to nothing else. SwiftLint's
// `native_call_agent_surface_reads` says the same at lint time — this test
// says it where SwiftLint may not be installed, and covers the view-state
// file too, where the lint rule's `included` does not reach.

struct NativeCallAgentSurfaceReadsTests {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // UnitTests
        .deletingLastPathComponent() // repo
        .appendingPathComponent("ElementX/Sources/Screens/NativeCallScreen")

    /// Any read of the two inputs, or of a per-agent `live` fact that has
    /// a `shown` verdict, from a surface. Preview fixtures WRITE them
    /// through `viewModel.state.` and are exempt.
    private static let forbidden = #"(?<!viewModel\.state)\.(agentCenter|agentClaims)\b|\.live\.(isAiring|isRecording|isSummaryArmed|isConversationActive|isLeaving|languages|style)\b"#

    @Test
    func noCallSurfaceReadsTheRestSnapshotOrTheRawClaims() throws {
        let files = try FileManager.default.subpathsOfDirectory(atPath: Self.sourceRoot.path)
            .filter { $0.hasSuffix(".swift") && $0.hasPrefix("View/") }
        #expect(files.count > 5, "scanned: \(files)")

        var violations: [String] = []
        for file in files {
            let text = try String(contentsOf: Self.sourceRoot.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated()
                where line.range(of: Self.forbidden, options: .regularExpression) != nil {
                violations.append("\(file):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(violations.isEmpty, "Surfaces must read viewState.agents:\n\(violations.joined(separator: "\n"))")
    }

    /// The view state's own derived accessors are surfaces too: the two
    /// inputs are named ONLY as bare arguments of the one derive call.
    @Test
    func theViewStateFeedsTheInputsOnlyIntoTheDerive() throws {
        let text = try String(contentsOf: Self.sourceRoot.appendingPathComponent("NativeCallScreenModels.swift"), encoding: .utf8)
        let readers = text.components(separatedBy: "\n").enumerated().filter { _, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("///"), !trimmed.hasPrefix("//") else { return false }
            return trimmed.range(of: Self.forbidden, options: .regularExpression) != nil
                || trimmed.range(of: #"\b(agentCenter|agentClaims)\s*\."#, options: .regularExpression) != nil
        }
        #expect(readers.isEmpty, "Only `agents` may consume the inputs:\n\(readers.map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n"))")
    }
}
