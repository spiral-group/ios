//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (coverage walk F6): an agent's Markdown body renders as
// formatted text, the way an HTML message does.
//

import Foundation
import MatrixRustSDK
@testable import Spiral
import Testing

@MainActor
struct SpiralAgentMarkdownTests {
    /// What `messenger.compose_structured_reply` posts for a heading, two bullets and a quote.
    static let structuredReply = "**Summary**\n\n• First point\n\n• Second point\n\n> Worth a look"
    
    // AGENT-PLATFORM (Brief 0083, question 359)
    @Test
    func aBodyAskedForAgainReadsTheSame() {
        let body = "**Twice** \(UUID())"
        
        #expect(SpiralAgentMarkdown.html(fromBody: body) != nil)
        #expect(SpiralAgentMarkdown.html(fromBody: body) == SpiralAgentMarkdown.html(fromBody: body))
    }
    
    @Test
    func aBodyWithNoMarkdownStaysPlainWhenAskedForAgain() {
        let body = "Plain \(UUID())"
        
        #expect(SpiralAgentMarkdown.html(fromBody: body) == nil)
        #expect(SpiralAgentMarkdown.html(fromBody: body) == nil)
    }
    
    @Test
    func aBodyIsRenderedOnce() {
        let line = "**Heading**\n> a quote\n- an item with `code` in it\n"
        let bodies = (0..<200).map { String(repeating: line, count: 20) + "\($0) \(UUID())" }
        let clock = ContinuousClock()
        
        let first = clock.measure { bodies.forEach { _ = SpiralAgentMarkdown.html(fromBody: $0) } }
        let again = clock.measure { bodies.forEach { _ = SpiralAgentMarkdown.html(fromBody: $0) } }
        
        #expect(again * 3 < first)
    }
    
    @Test
    func aStructuredReplyBecomesHTML() throws {
        let html = try #require(SpiralAgentMarkdown.html(fromBody: Self.structuredReply))
        // The bullets are one real list, though the blocks are a blank line apart.
        #expect(html == "<p><strong>Summary</strong></p><ul><li>First point</li><li>Second point</li></ul><blockquote>Worth a look</blockquote>")
    }
    
    @Test
    func plainTextStaysPlain() {
        #expect(SpiralAgentMarkdown.html(fromBody: "Hello! See you at 5.\nBring snacks • please") == nil)
        #expect(SpiralAgentMarkdown.html(fromBody: "a snake_case_name and 2 * 3 = 6") == nil)
    }
    
    @Test
    func aModelsOwnMarkdownBecomesHTML() throws {
        let body = "## Plan\nDo **this** and *that*:\n- one\n- `two`\n\n1. first\n2. second\n```\nlet x = 1 < 2\n```"
        let html = try #require(SpiralAgentMarkdown.html(fromBody: body))
        #expect(html == "<p><strong>Plan</strong></p><p>Do <strong>this</strong> and <em>that</em>:</p>"
            + "<ul><li>one</li><li><code>two</code></li></ul>"
            + "<ol><li>first</li><li>second</li></ol>"
            + "<pre><code>let x = 1 &lt; 2</code></pre>")
    }
    
    @Test
    func aLinkKeepsWhereItGoesInView() throws {
        let html = try #require(SpiralAgentMarkdown.html(fromBody: "Read [the terms](https://evil.example/x) <b>now</b>"))
        #expect(html == "<p>Read the terms (https://evil.example/x) &lt;b&gt;now&lt;/b&gt;</p>")
    }
    
    // MARK: - In the timeline
    
    private static func textItem(body: String, sender: String) -> EventTimelineItemProxy {
        let messageType = MessageType.text(content: TextMessageContent(body: body, formatted: nil))
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        return EventTimelineItemProxy(item: .init(configuration: .init(sender: sender, content: content)), uniqueID: .init(sender))
    }
    
    private let factory = RoomTimelineItemFactory(userID: "@alice:spiral.md",
                                                  attributedStringBuilder: AttributedStringBuilder(cacheKey: "SpiralAgentMarkdownTests",
                                                                                                   mentionBuilder: MentionBuilder()),
                                                  stateEventStringBuilder: RoomStateEventStringBuilder(userID: "@alice:spiral.md"))
    
    @Test
    func anAgentsStructuredReplyShowsNoAsterisks() throws {
        let item = try #require(factory.buildTimelineItem(for: Self.textItem(body: Self.structuredReply, sender: "@assistant-alice:spiral.md"),
                                                          isDM: true) as? TextRoomTimelineItem)
        let formatted = try #require(item.content.formattedBody)
        let text = String(formatted.characters)
        #expect(!text.contains("**"))
        #expect(!text.contains("> "))
        #expect(text.hasPrefix("Summary"))
        #expect(formatted.runs.contains { $0.blockquote == true })
        #expect(item.content.body == Self.structuredReply, "the body, for copy and reply, stays as sent")
    }
    
    @Test
    func aPersonsAsterisksStayAsTyped() throws {
        let item = try #require(factory.buildTimelineItem(for: Self.textItem(body: "**not bold**", sender: "@bob:spiral.md"),
                                                          isDM: true) as? TextRoomTimelineItem)
        #expect(item.content.formattedBody.map { String($0.characters) } == "**not bold**")
    }
}
