//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0044, ADR-0058): the all-participant tools
// banner rotates over EACH active tool (not per agent). These pin the
// flat-list model: SpiralToolsStateReader.flatten unrolls per-agent
// entries into one item per tool (stable ids, agent order preserved),
// and ActiveToolsBannerState rotates / preserves selection over them.

import Compound
import Foundation
@testable import Spiral
import SwiftUI
import Testing

@MainActor
struct ActiveToolsBannerStateTests {
    // MARK: - flatten (reader → flat tool list)

    private static func entry(_ agent: String, owner: String, at: Double,
                              tools: [ToolsBannerEntry.Tool]) -> ToolsBannerEntry {
        ToolsBannerEntry(agentMatrixUserID: agent, ownerUserID: owner,
                         updatedAt: Date(timeIntervalSince1970: at), tools: tools)
    }

    private static func tool(_ kind: String, id: String? = nil, language: String? = nil) -> ToolsBannerEntry.Tool {
        ToolsBannerEntry.Tool(toolID: id, kind: kind, trigger: "on_message", targetLanguage: language)
    }

    @Test
    func flattenUnrollsEachToolInAgentOrder() {
        // Two agents; the first has TWO tools. Order = entry order, with
        // each agent's tools kept together in tool order.
        let entries = [
            Self.entry("@a-me:host", owner: "@me:host", at: 2000,
                       tools: [Self.tool("translate", id: "t1", language: "English"),
                               Self.tool("summarize", id: "t2")]),
            Self.entry("@a-bob:host", owner: "@bob:host", at: 1000,
                       tools: [Self.tool("rephrase", id: "t3")])
        ]
        let flat = SpiralToolsStateReader.flatten(entries: entries)
        #expect(flat.count == 3)
        #expect(flat.map(\.id) == ["@a-me:host#t1", "@a-me:host#t2", "@a-bob:host#t3"])
        #expect(flat[0].tool.kind == "translate")
        #expect(flat[1].tool.kind == "summarize")
        #expect(flat[2].entry.agentMatrixUserID == "@a-bob:host")
    }

    @Test
    func flattenFallsBackToOrdinalIDWhenToolIDMissing() {
        // Two same-kind tools without backend tool_ids must still get
        // distinct, stable ids (ordinal-based).
        let entries = [
            Self.entry("@a-me:host", owner: "@me:host", at: 1,
                       tools: [Self.tool("summarize"), Self.tool("summarize")])
        ]
        let flat = SpiralToolsStateReader.flatten(entries: entries)
        #expect(flat.map(\.id) == ["@a-me:host#0", "@a-me:host#1"])
    }

    // MARK: - rotation over tools

    private static func item(_ id: String, _ title: String,
                             icon: KeyPath<CompoundIcons, Image> = \.translate,
                             agent: String = "@a:host") -> BannerToolItem {
        BannerToolItem(id: id, title: title, icon: icon, agentMatrixUserID: agent)
    }

    @Test
    func selectedIconTracksTheSelectedTool() {
        // Each tool carries the icon of its capability; rotating changes both
        // the title and the icon so the banner never shows a stale glyph.
        var state = ActiveToolsBannerState.loaded(state: .init(items: [Self.item("i0", "Translating to English", icon: \.translate),
                                                                       Self.item("i1", "Summarise calls", icon: \.document),
                                                                       Self.item("i2", "Record calls", icon: \.voiceCallSolid)],
                                                               selectedID: "i0"))
        #expect(state.selectedIcon == \CompoundIcons.translate)

        state.rotate()
        #expect(state.selectedIcon == \CompoundIcons.document)

        state.rotate()
        #expect(state.selectedIcon == \CompoundIcons.voiceCallSolid)
    }

    @Test
    func iconResolvesFromToolKind() {
        #expect(ToolDisplayName.icon(forKind: "translate") == \CompoundIcons.translate)
        #expect(ToolDisplayName.icon(forKind: "live_translate") == \CompoundIcons.voiceCall)
        #expect(ToolDisplayName.icon(forKind: "call_summary") == \CompoundIcons.document)
        #expect(ToolDisplayName.icon(forKind: "call_recording") == \CompoundIcons.micOn)
        // Unknown kind falls back to the translate icon.
        #expect(ToolDisplayName.icon(forKind: "made_up") == \CompoundIcons.extensions)
    }

    @Test
    func toolDisplayNameLocalizesEveryKind() {
        // The call-artifact kinds have names of their own, so they must be
        // resolved here too — never rendered as the raw "call_summary" tag.
        #expect(ToolDisplayName.name(forKind: "call_summary") == UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle)
        #expect(ToolDisplayName.name(forKind: "call_recording") == UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle)
        #expect(ToolDisplayName.name(forKind: "summarize") == UntranslatedL10n.screenArmToolKindSummarize)
        #expect(ToolDisplayName.name(forKind: "call_summary") != "Call_summary")
        #expect(ToolDisplayName.name(forKind: "call_recording") != "Call_recording")
    }

    @Test
    func toolDisplayNameGivesANewerKindAGenericLabel() {
        // Decision 96: a kind newer than the app degrades to a word, never the raw tag.
        #expect(ToolDisplayName.name(forKind: "teleport") == UntranslatedL10n.screenAgentToolsListTitleUnknown)
    }

    @Test
    func toolDisplayNameCoversEveryKnownToolKind() throws {
        // Guard against the regression that shipped call_summary/call_recording
        // as raw tags: every kind AgentToolKind knows about MUST resolve to a
        // real localized name here, never the raw-tag fallback. Adding a new
        // backend kind to AgentToolKind without a name here fails
        // this test. Comparison is against the explicit L10n contract (the old
        // `!= kind.localizedCapitalized` proxy false-fails on English, where
        // fallback and genuine name legitimately coincide for one-word kinds).
        let expectedNames: [String: String] = [
            "translate": UntranslatedL10n.screenArmToolKindTranslate,
            "live_translate": UntranslatedL10n.screenArmToolKindTranslate,
            "simplify": UntranslatedL10n.screenArmToolKindSimplify,
            "correct": UntranslatedL10n.screenArmToolKindCorrect,
            "rephrase": UntranslatedL10n.screenArmToolKindRephrase,
            "summarize": UntranslatedL10n.screenArmToolKindSummarize,
            "custom": UntranslatedL10n.screenArmToolKindCustom,
            "call_summary": UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle,
            "call_recording": UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle
        ]
        let knownKinds = AgentToolKind.allCases.map(\.rawValue)
        for kind in knownKinds {
            let expected = try #require(expectedNames[kind],
                                        "Tool kind '\(kind)' has no localized name in ToolDisplayName")
            #expect(ToolDisplayName.name(forKind: kind) == expected)
        }
    }

    @Test
    func rotatesThroughEveryToolAndWraps() {
        var state = ActiveToolsBannerState.loaded(state: .init(items: [Self.item("i0", "Translating to English"),
                                                                       Self.item("i1", "Summarise"),
                                                                       Self.item("i2", "Rephrase")],
                                                               selectedID: "i0"))
        #expect(state.count == 3)
        #expect(state.selectedIndex == 0)
        #expect(state.displayedMessage == "Translating to English")

        state.rotate()
        #expect(state.selectedIndex == 1)
        #expect(state.displayedMessage == "Summarise")

        state.rotate()
        #expect(state.selectedIndex == 2)
        #expect(state.displayedMessage == "Rephrase")

        // Wrap back to the first tool.
        state.rotate()
        #expect(state.selectedIndex == 0)
        #expect(state.displayedMessage == "Translating to English")
    }

    @Test
    func loadingToLoadedSelectsFirstTool() {
        var state = ActiveToolsBannerState.loading
        #expect(state.isLoading)
        state.setItems([Self.item("i0", "Translating to English"), Self.item("i1", "Summarise")])
        #expect(!state.isLoading)
        #expect(state.count == 2)
        #expect(state.selectedIndex == 0)
        #expect(state.displayedMessage == "Translating to English")
    }

    @Test
    func setItemsPreservesSelectionByIDAndClearsWhenGone() {
        var state = ActiveToolsBannerState.loaded(state: .init(items: [Self.item("i0", "Translating to English"),
                                                                       Self.item("i1", "Summarise"),
                                                                       Self.item("i2", "Rephrase")],
                                                               selectedID: "i1"))
        #expect(state.displayedMessage == "Summarise")

        // A timeline refresh that keeps i1 must keep it selected even as
        // its position shifts (i0 dropped → i1 now at index 0).
        state.setItems([Self.item("i1", "Summarise"), Self.item("i2", "Rephrase")])
        #expect(state.selectedIndex == 0)
        #expect(state.displayedMessage == "Summarise")

        // Dropping the selected tool falls back to the first item.
        state.setItems([Self.item("i2", "Rephrase")])
        #expect(state.selectedIndex == 0)
        #expect(state.displayedMessage == "Rephrase")
        // count == 1 → the view hides the dots/indicator.
        #expect(state.count == 1)
    }

    @Test
    func emptyItemsCollapseToLoading() {
        var state = ActiveToolsBannerState.loaded(state: .init(items: [Self.item("i0", "Summarise")],
                                                               selectedID: "i0"))
        #expect(!state.isEmpty)
        state.setItems([])
        #expect(state.isLoading)
        #expect(state.isEmpty)
    }
}
