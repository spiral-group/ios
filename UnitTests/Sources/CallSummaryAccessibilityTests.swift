//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import SwiftUI
import Testing

/// Decision 371: the row is one element, so VoiceOver gets all a fold hides from its label, and the fold from its actions.
@Suite(AccessibilityTree())
struct CallSummaryAccessibilityTests {
    private static let long = SpiralCallSummary(title: "Call summary",
                                                text: String(repeating: "We went through the plan. ", count: 20),
                                                decisionsTitle: "Decisions",
                                                decisions: ["Ship on Friday"],
                                                actionItemsTitle: "Action items",
                                                actionItems: ["One", "Two", "Three", "Four", "The fifth item"])
    
    @Test
    func aFoldedRowReadsWholeAndOpensByAnAction() async throws {
        let context = TimelineViewModel.mock.context
        let item = Self.item(Self.long)
        let host = try await Self.host(item, context: context)
        
        let row = try #require(Self.row(in: host.view))
        #expect(row.accessibilityLabel?.contains("The fifth item") == true)
        #expect(row.accessibilityLabel?.contains("Ship on Friday") == true)
        
        let action = try #require(row.accessibilityCustomActions?.first { $0.name == L10n.screenRoomTimelineReactionsShowMore })
        _ = action.actionHandler?(action)
        
        #expect(context.expandedCallSummaries == [item.id])
    }
    
    @Test
    func aShortRowHasNoFoldToOffer() async throws {
        let context = TimelineViewModel.mock.context
        let host = try await Self.host(Self.item(SpiralCallSummary(text: "We agreed.")), context: context)
        
        let row = try #require(Self.row(in: host.view))
        #expect(row.accessibilityCustomActions?.contains { $0.name == L10n.screenRoomTimelineReactionsShowMore } != true)
    }
    
    private static func item(_ summary: SpiralCallSummary) -> CallSummaryRoomTimelineItem {
        CallSummaryRoomTimelineItem(id: .randomEvent,
                                    timestamp: .mock,
                                    isOutgoing: false,
                                    isEditable: false,
                                    canBeRepliedTo: true,
                                    sender: .init(id: "@assistant-alice:spiral.md", displayName: "Alice's Assistant"),
                                    content: .init(body: summary.text),
                                    summary: summary)
    }
    
    private static func host(_ item: CallSummaryRoomTimelineItem, context: TimelineViewModel.Context) async throws -> UIViewController {
        let view = CallSummaryRoomTimelineView(timelineItem: item)
            .environment(\.timelineContext, context)
            .environment(\.timelineRowContext, TimelineRowContext(isDM: true))
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100)) // The tree is built on the next pass of the run loop.
        return host
    }
    
    /// The element that reads the sender's name, which only the row's label holds.
    private static func row(in object: NSObject) -> NSObject? {
        if object.accessibilityLabel?.contains("Alice's Assistant") == true {
            return object
        }
        let count = object.accessibilityElementCount()
        let elements = count == NSNotFound ? [] : (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
        let views = (object as? UIView)?.subviews ?? []
        return (elements + views).lazy.compactMap(row).first
    }
}
