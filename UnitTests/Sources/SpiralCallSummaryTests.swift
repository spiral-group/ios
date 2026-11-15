//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import MatrixRustSDK
@testable import Spiral
import Testing

/// Decision 371: the facts of a call summary's card, as `summary_message_content` in the backend's
/// `src/worker/voice_summary.rs` writes them.
struct SpiralCallSummaryTests {
    private static let msgtype = "com.spiral.notice"
    
    @Test
    func readsTheFactsTheBackendPosts() throws {
        let data = #"""
        {"com.spiral.notice":{"kind":"call_summary","title":"Підсумок дзвінка","summary":"Ми домовилися.",
        "decisions_title":"Рішення","decisions":["Випускаємо в п'ятницю"],
        "action_items_title":"Завдання","action_items":["Надіслати план"]},
        "com.matrixagent.voice_summary":{"session_id":"sid"},"com.matrixagent.automation_output":"v=1"}
        """#
        
        let summary = try #require(SpiralCallSummary(msgtype: Self.msgtype, data: data))
        
        #expect(summary.title == "Підсумок дзвінка")
        #expect(summary.text == "Ми домовилися.")
        #expect(summary.decisionsTitle == "Рішення")
        #expect(summary.decisions == ["Випускаємо в п'ятницю"])
        #expect(summary.actionItemsTitle == "Завдання")
        #expect(summary.actionItems == ["Надіслати план"])
        #expect(!summary.isLong)
    }
    
    @Test
    func aSummaryStoredWithoutTitlesLeavesThemOut() throws {
        let data = #"{"com.spiral.notice":{"kind":"call_summary","summary":"We agreed.","decisions":["  "],"action_items":["Send it", "  "]}}"#
        
        let summary = try #require(SpiralCallSummary(msgtype: Self.msgtype, data: data))
        
        #expect(summary.title == nil)
        #expect(summary.decisionsTitle == nil)
        #expect(summary.decisions.isEmpty)
        #expect(summary.actionItemsTitle == nil)
        #expect(summary.actionItems == ["Send it"])
    }
    
    @Test(arguments: [
        #"{"com.spiral.notice":{"kind":"reply_failed"}}"#,
        #"{"com.spiral.notice":{"kind":"call_summary","decisions":[],"action_items":[]}}"#,
        #"{"com.spiral.notice":{"kind":"call_summary","summary":"  ","decisions":[],"action_items":[]}}"#,
        #"{"com.spiral.notice":{"kind":"call_summary","summary":"We agreed.","decisions":[]}}"#,
        #"{"com.spiral.notice":{"kind":"call_summary","summary":"We agreed.","action_items":[]}}"#,
        #"{"com.spiral.notice":{"kind":"call_summary","summary":"We agreed.","decisions":[{"text":"Ship"}],"action_items":[]}}"#,
        #"{"com.spiral.notice":{"kind":"call_summary","summary":"We agreed.","decisions":[],"action_items":[{"text":"Send it"}]}}"#,
        #"{"com.spiral.notice":{"kind":"call_summary","summary":["We agreed."],"decisions":[],"action_items":[]}}"#,
        "not json"
    ])
    func anUnknownShapeIsNoCard(data: String) {
        #expect(SpiralCallSummary(msgtype: Self.msgtype, data: data) == nil)
    }
    
    @Test
    func anotherMessageIsNoCard() {
        let data = #"{"com.spiral.notice":{"kind":"call_summary","summary":"We agreed.","decisions":[],"action_items":[]}}"#
        
        #expect(SpiralCallSummary(msgtype: "m.text", data: data) == nil)
    }
    
    @Test
    func aCallSummaryIsNoNotice() {
        let data = #"{"com.spiral.notice":{"kind":"call_summary","summary":"We agreed.","decisions":[],"action_items":[]}}"#
        
        #expect(SpiralNotice(msgtype: Self.msgtype, data: data) == nil)
    }
    
    @Test
    func onlyALongSummaryFolds() {
        #expect(!SpiralCallSummary(text: String(repeating: "a", count: 300)).isLong)
        #expect(SpiralCallSummary(text: String(repeating: "a", count: 301)).isLong)
        #expect(!SpiralCallSummary(text: "We agreed.", actionItems: ["1", "2", "3"]).isLong)
        #expect(SpiralCallSummary(text: "We agreed.", actionItems: ["1", "2", "3", "4"]).isLong)
        #expect(SpiralCallSummary(text: "We agreed.", actionItems: Array(repeating: String(repeating: "a", count: 151), count: 2)).isLong)
        #expect(!SpiralCallSummary(text: "We agreed.", decisions: ["1", "2", "3"], actionItems: ["1", "2", "3"]).isLong)
        #expect(SpiralCallSummary(text: "We agreed.", decisions: ["1", "2", "3", "4"]).isLong)
        #expect(SpiralCallSummary(text: "We agreed.",
                                  decisions: [String(repeating: "a", count: 151)],
                                  actionItems: [String(repeating: "a", count: 150)]).isLong)
    }
    
    @Test
    func voiceOverReadsAllAFoldHides() {
        let items = ["1", "2", "3", "4", "5"]
        let summary = SpiralCallSummary(title: "Call summary",
                                        text: String(repeating: "a", count: 400),
                                        decisionsTitle: "Decisions",
                                        decisions: ["Ship it"],
                                        actionItemsTitle: "Action items",
                                        actionItems: items)
        
        #expect(summary.isLong)
        #expect(summary.accessibilityText.components(separatedBy: "\n") ==
            ["Call summary", summary.text, "Decisions", "Ship it", "Action items"] + items)
    }
    
    @Test
    func voiceOverLeavesOutTheTitleOfAnEmptyList() {
        let summary = SpiralCallSummary(text: "We agreed.", decisionsTitle: "Decisions", actionItemsTitle: "Action items", actionItems: ["Send it"])
        
        #expect(summary.accessibilityText == "\(UntranslatedL10n.noticeSummaryMovedTitle)\nWe agreed.\nAction items\nSend it")
    }
    
    @Test
    func aForwardedSummaryIsPlainText() {
        let message = MessageContent(msgType: .other(msgtype: Self.msgtype, body: "The whole summary", data: #"{"com.spiral.notice":{}}"#),
                                     body: "The whole summary",
                                     isEdited: false,
                                     mentions: nil)
        
        guard case .text(let content) = message.forwardable.msgType else {
            Issue.record("Not a text message")
            return
        }
        #expect(content.body == "The whole summary")
    }
    
    @Test
    func anyOtherMessageIsForwardedAsItIs() {
        let message = MessageContent(msgType: .other(msgtype: "org.example.custom", body: "Hello", data: "{}"),
                                     body: "Hello",
                                     isEdited: false,
                                     mentions: nil)
        
        guard case .other = message.forwardable.msgType else {
            Issue.record("Not left alone")
            return
        }
    }
    
    @Test
    func aRowKnowsItsOwnSummaryIsOpen() {
        let open = TimelineItemIdentifier.randomEvent
        let context = TimelineViewModel.mock.context
        context.expandedCallSummaries = [open]
        
        let inputs = TimelineRowContextInputs(context.viewState)
        
        #expect(inputs.rowContext(for: open).isCallSummaryExpanded)
        #expect(!inputs.rowContext(for: .randomEvent).isCallSummaryExpanded)
    }
}
