//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 357): the table snaps its offset to device pixels, so "at the newest message"
// allows for a bar whose height isn't on one. The jump-to-bottom button hangs on this.
//

import CoreGraphics
@testable import Spiral
import Testing

struct TimelineTableViewControllerTests {
    /// Measured on iOS 27 in a room with the "Not encrypted" line: the bar is 96.0868 pt and the table rests at -142.
    @Test
    func anOffsetSnappedShortOfAFractionalInsetIsAtTheNewestItem() {
        #expect(TimelineTableViewController.isAtNewestItem(offset: -142, bottomOffset: -142.086833, displayScale: 3))
    }
    
    @Test
    func theOffsetKeptPastTheNewestItemIsAtIt() {
        #expect(TimelineTableViewController.isAtNewestItem(offset: -143, bottomOffset: -142, displayScale: 3))
    }
    
    @Test
    func aPixelAwayIsNotAtTheNewestItem() {
        #expect(!TimelineTableViewController.isAtNewestItem(offset: -141.66, bottomOffset: -142, displayScale: 3))
        #expect(!TimelineTableViewController.isAtNewestItem(offset: -100, bottomOffset: -142, displayScale: 3))
    }
    
    @Test
    func aScaleNotKnownYetCountsAsOne() {
        #expect(TimelineTableViewController.isAtNewestItem(offset: -141.5, bottomOffset: -142, displayScale: 0))
    }
    
    @Test
    func aFingerOnTheEdgeIsLeftAlone() {
        #expect(!TimelineTableViewController.shouldStepOffNewestEdge(offset: -142, bottomOffset: -142.086833, displayScale: 3, isTracking: true))
    }
    
    @Test
    func theTableAtRestOnTheEdgeStepsOffIt() {
        #expect(TimelineTableViewController.shouldStepOffNewestEdge(offset: -142, bottomOffset: -142.086833, displayScale: 3, isTracking: false))
    }
    
    @Test
    func theOffsetKeptPastTheEdgeStaysThere() {
        #expect(!TimelineTableViewController.shouldStepOffNewestEdge(offset: -143, bottomOffset: -142, displayScale: 3, isTracking: false))
    }
    
    // MARK: - What counts as seen (question 364)
    
    @Test
    func aRowUnderTheComposerIsNotSeen() {
        // The bar covers 100 pt, and the table's scrolled up 30: the newest 30 pt are under it.
        #expect(!TimelineTableViewController.isClearOfComposer(rowMinY: 0, offset: -70, bottomOffset: -100, displayScale: 3))
        #expect(TimelineTableViewController.isClearOfComposer(rowMinY: 30, offset: -70, bottomOffset: -100, displayScale: 3))
    }
    
    @Test
    func theNewestRowIsSeenAtTheEnd() {
        #expect(TimelineTableViewController.isClearOfComposer(rowMinY: 0, offset: -101, bottomOffset: -100, displayScale: 3))
        #expect(TimelineTableViewController.isClearOfComposer(rowMinY: 0, offset: -142, bottomOffset: -142.086833, displayScale: 3))
    }
    
    // MARK: - Room above the composer (1.0.2, operator 2026-11-15)

    @Test
    func beforeLiquidGlassTheNewestMessageKeepsTheGapItHasAtRestOnIOS26() {
        // iOS 18's bar is the table's safe area, so the bar height the environment carries is zero.
        #expect(TimelineTableViewController.composerClearance(supportsGlass: false, composerBarHeight: 0, safeAreaBottom: 90) == 12)
        // The keyboard up: no edge effect to clear, so the gap doesn't grow.
        #expect(TimelineTableViewController.composerClearance(supportsGlass: false, composerBarHeight: 0, safeAreaBottom: 0) == 12)
    }

    @Test
    func withLiquidGlassTheNewestMessageClearsTheEdgeEffect() {
        #expect(TimelineTableViewController.composerClearance(supportsGlass: true, composerBarHeight: 96, safeAreaBottom: 34) == 12)
        #expect(TimelineTableViewController.composerClearance(supportsGlass: true, composerBarHeight: 60, safeAreaBottom: 0) == 32)
        #expect(TimelineTableViewController.composerClearance(supportsGlass: true, composerBarHeight: 0, safeAreaBottom: 34) == 0)
    }

    @Test
    func aFoldNamesItsNewestEvent() {
        let fold = CollapsibleTimelineItem(items: ["0", "1", "2"].map(stateRow))
        
        let viewState = RoomTimelineItemViewState(item: fold, groupStyle: .single)
        
        #expect(viewState.newestEventItemID?.eventID == "$2")
    }
    
    @Test
    func aVirtualRowNamesNoEvent() {
        let marker = ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init("marker")))
        
        let viewState = RoomTimelineItemViewState(item: marker, groupStyle: .single)
        
        #expect(viewState.newestEventItemID == nil)
    }
    
    private func stateRow(_ id: String) -> StateRoomTimelineItem {
        StateRoomTimelineItem(id: .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)")),
                              body: "Alice joined",
                              timestamp: .now,
                              isOutgoing: false,
                              isEditable: false,
                              canBeRepliedTo: false,
                              sender: .init(id: "@alice:spiral.test"))
    }
}
