//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, questions 363 and 364): the real table in a window, with real rows, as only it can say where a
// chat opens.
//

import MatrixRustSDK
@testable import Spiral
import SwiftUI
import Testing

@MainActor
struct TimelineOpeningTableTests {
    private static let them = "@alice:spiral.test"
    private static let marker = ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init("marker")))
    
    @Test
    func moreThanAScreenOfUnreadOpensWithNewAtTheTop() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker] + rows(20..<80))
        
        try await screen.waitForOpening()
        
        let markerFrame = try #require(screen.frameOnScreen(of: "marker"))
        #expect(abs(markerFrame.minY - screen.tableTop) < 2)
        #expect(screen.isDotShowing)
        #expect(!screen.isAtEnd)
        #expect(!screen.table.isHidden)
    }
    
    @Test
    func theEndIsNeverNamedOnOpening() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker] + rows(20..<80))
        
        try await screen.waitForOpening()
        
        let newestSeen = try #require(screen.receipts.last)
        #expect(!screen.receipts.contains("$79"))
        #expect(newestSeen < "$79")
    }
    
    @Test
    func unreadThatFitsOpensAtTheEnd() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<60) + [Self.marker] + rows(60..<62))
        
        try await screen.waitForOpening()
        
        #expect(screen.isAtEnd)
        #expect(!screen.isDotShowing)
        #expect(screen.frameOnScreen(of: "marker") != nil)
    }
    
    @Test
    func nothingUnreadOpensAtTheEnd() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<60))
        
        try await screen.waitForOpening()
        
        #expect(screen.isAtEnd)
        #expect(screen.frameOnScreen(of: "59") != nil)
    }
    
    @Test
    func aRowArrivingBelowLeavesYouWhereYouAre() async throws {
        let items: [RoomTimelineItemProtocol] = rows(0..<20) + [Self.marker] + rows(20..<80)
        let screen = try await TimelineTestScreen(items: items)
        try await screen.waitForOpening()
        let before = try #require(screen.frameOnScreen(of: "marker"))
        
        await screen.deliver(items + rows(80..<81))
        
        #expect(screen.table.numberOfRows(inSection: 0) == items.count + 1)
        let after = try #require(screen.frameOnScreen(of: "marker"))
        #expect(abs(after.minY - before.minY) < 1)
    }
    
    @Test
    func rowsLoadedAboveLeaveYouWhereYouAre() async throws {
        let items: [RoomTimelineItemProtocol] = rows(10..<20) + [Self.marker] + rows(20..<80)
        let screen = try await TimelineTestScreen(items: items)
        try await screen.waitForOpening()
        let before = try #require(screen.frameOnScreen(of: "marker"))
        
        await screen.deliver(rows(0..<10) + items)
        
        #expect(screen.table.numberOfRows(inSection: 0) == items.count + 10)
        let after = try #require(screen.frameOnScreen(of: "marker"))
        #expect(abs(after.minY - before.minY) < 1)
    }
    
    @Test
    func aHeaderMeasuredAfterwardsDoesNotCoverNew() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker] + rows(20..<80))
        try await screen.waitForOpening()
        
        try screen.tableViewController().headerBlockHeight = 60
        await screen.pump()
        
        let markerFrame = try #require(screen.frameOnScreen(of: "marker"))
        #expect(abs(markerFrame.minY - screen.tableTop - 60) < 2)
    }
    
    @Test
    func aHeaderMeasuredAfterYouScrolledLeavesYouThere() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker] + rows(20..<80))
        try await screen.waitForOpening()
        let viewController = try screen.tableViewController()
        viewController.scrollViewWillBeginDragging(screen.table)
        viewController.scrollViewDidEndDragging(screen.table, willDecelerate: false)
        let offset = screen.table.contentOffset.y
        
        viewController.headerBlockHeight = 60
        await screen.pump()
        
        #expect(screen.table.contentOffset.y == offset)
    }
    
    @Test
    func aHeaderMeasuredAfterAJumpLeavesYouThere() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker] + rows(20..<80))
        try await screen.waitForOpening()
        let viewController = try screen.tableViewController()
        viewController.scrollViewDidEndScrollingAnimation(screen.table)
        let offset = screen.table.contentOffset.y
        
        viewController.headerBlockHeight = 60
        await screen.pump()
        
        #expect(screen.table.contentOffset.y == offset)
    }
    
    @Test
    func aLinkAfterOpeningIsNotPulledBackToNew() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker] + rows(20..<80))
        try await screen.waitForOpening()
        
        await screen.chat.viewModel.focusOnEvent(eventID: "$70")
        for _ in 0..<20 {
            await screen.pump() // The scroll to it is animated.
        }
        let offset = screen.table.contentOffset.y
        try screen.tableViewController().headerBlockHeight = 60
        await screen.pump()
        
        #expect(screen.frameOnScreen(of: "70") != nil)
        #expect(screen.table.contentOffset.y == offset)
    }
    
    @Test
    func theRowsWaitBehindAnEmptyTableUntilNewIsLoaded() async throws {
        let screen = try await TimelineTestScreen(items: rows(40..<80), unreadMessagesCount: 40, fullyReadEventID: "$19") { chat in
            chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in
                try? await Task.sleep(for: .seconds(10))
                return .success(())
            }
        }
        #expect(screen.table.isHidden)
        #expect(screen.receipts.isEmpty)
        
        await screen.deliver(rows(0..<20) + [Self.marker] + rows(20..<80))
        try await screen.waitForOpening()
        
        #expect(!screen.table.isHidden)
        let markerFrame = try #require(screen.frameOnScreen(of: "marker"))
        #expect(abs(markerFrame.minY - screen.tableTop) < 2)
    }
    
    @Test
    func rowsArrivingWhileAwayStopAtNew() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20))
        try await screen.waitForOpening()
        screen.chat.appMediator.appState = .background
        
        await screen.deliver(rows(0..<20) + [Self.marker] + rows(20..<80))
        try await screen.waitForOpening()
        
        let markerFrame = try #require(screen.frameOnScreen(of: "marker"))
        #expect(abs(markerFrame.minY - screen.tableTop) < 2)
        #expect(screen.isDotShowing)
    }
    
    @Test
    func theSameRowAskedForAgainSettlesToo() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker] + rows(20..<80))
        try await screen.waitForOpening()
        
        screen.chat.viewModel.state.timelineState.opening = .atRow(.init("marker"))
        
        try await screen.waitForOpening()
    }
    
    @Test
    func rowsHeldBackByADragSettleWhenItEnds() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20))
        try await screen.waitForOpening()
        let viewController = try screen.tableViewController()
        screen.chat.appMediator.appState = .background
        
        viewController.scrollViewWillBeginDragging(screen.table)
        await screen.deliver(rows(0..<20) + [Self.marker] + rows(20..<80))
        viewController.scrollViewDidEndDragging(screen.table, willDecelerate: false)
        
        try await screen.waitForOpening()
    }
    
    @Test
    func rowsInBeforeTheTableAppearedSettleOnItsLayout() async throws {
        let chat = TimelineTestChat(items: rows(0..<20) + [Self.marker] + rows(20..<80), isSettled: false)
        let viewController = TimelineTableViewController(coordinator: .init(viewModelContext: chat.viewModel.context),
                                                         isScrolledToBottom: .constant(true),
                                                         isReadMarkerVisible: .constant(false),
                                                         hasNewMessagesAtBottom: .constant(false),
                                                         floatingDate: .constant(nil),
                                                         scrollToBottomPublisher: .init(),
                                                         scrollToFirstItemForDatePublisher: .init(),
                                                         scrollToReadMarkerPublisher: .init())
        viewController.opening = chat.viewModel.state.timelineState.opening
        viewController.timelineItemsDictionary = chat.viewModel.state.timelineState.itemsDictionary
        
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
        
        #expect(chat.viewModel.state.timelineState.opening == .settled)
    }
    
    @Test
    func aGiveUpOpensAtTheEndAndReadsTheChat() async throws {
        let screen = try await TimelineTestScreen(items: rows(40..<80), unreadMessagesCount: 40, fullyReadEventID: "$19") { chat in
            chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in .failure(.generic) }
        }
        
        try await screen.waitForOpening()
        await screen.pump()
        
        #expect(screen.isAtEnd)
        #expect(!screen.table.isHidden)
        #expect(screen.receipts.last == "$79")
        #expect(screen.chat.fullyReadRequests == ["$79"])
    }
    
    @Test
    func leavingWhileLoadingShowsNoRowsOnTheWayOut() async throws {
        let screen = try await TimelineTestScreen(items: rows(40..<80), unreadMessagesCount: 40, fullyReadEventID: "$19") { chat in
            chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in
                try? await Task.sleep(for: .seconds(10))
                return .success(())
            }
        }
        
        screen.chat.viewModel.stop()
        await screen.pump()
        
        #expect(screen.chat.viewModel.state.timelineState.opening == .abandoned)
        #expect(screen.table.isHidden)
        #expect(screen.receipts.isEmpty)
    }
    
    @Test
    func aFocussedEventShowsNoNew() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker] + rows(20..<80), focussedEventID: "$50")
        
        await screen.pump()
        
        #expect(screen.frameOnScreen(of: "50") != nil)
        #expect(screen.frameOnScreen(of: "marker") == nil)
    }
    
    @Test
    func theHighlightIsNotUsedForOpening() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker] + rows(20..<80))
        
        try await screen.waitForOpening()
        
        #expect(screen.chat.viewModel.state.timelineState.focussedEvent == nil)
    }
    
    // MARK: - Where the chat stands
    
    /// Two ticks in one turn, off the end and back: the second one is where the table is (2026-11-12, the jump button stayed up
    /// with its dot at the end of "Translation walk G1").
    @Test
    func aTickBackToTheEndInTheSameTurnLeavesTheChatAtTheEnd() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<60))
        try await screen.waitForOpening()
        let viewController = try screen.tableViewController()
        let end = screen.table.contentOffset.y
        #expect(screen.isAtEnd)
        
        screen.table.contentOffset.y = end + 300
        viewController.scrollViewDidScroll(screen.table)
        screen.table.contentOffset.y = end
        viewController.scrollViewDidScroll(screen.table)
        await screen.pump()
        
        #expect(screen.isAtEnd)
    }
    
    @Test
    func aTickToTheEndAndBackInTheSameTurnLeavesTheChatScrolledUp() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<60))
        try await screen.waitForOpening()
        let viewController = try screen.tableViewController()
        let end = screen.table.contentOffset.y
        screen.table.contentOffset.y = end + 300
        viewController.scrollViewDidScroll(screen.table)
        await screen.pump()
        #expect(!screen.isAtEnd)
        
        screen.table.contentOffset.y = end
        viewController.scrollViewDidScroll(screen.table)
        screen.table.contentOffset.y = end + 300
        viewController.scrollViewDidScroll(screen.table)
        await screen.pump()
        
        #expect(!screen.isAtEnd)
    }
    
    /// A dot set while the end shows points at nothing, so the next tick takes it, with no move to the end to wait for.
    @Test
    func aDotAtTheEndGoesWithTheNextTick() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<60))
        try await screen.waitForOpening()
        let viewController = try screen.tableViewController()
        #expect(screen.isAtEnd)
        
        screen.chat.viewModel.state.bindings.hasNewMessagesAtBottom = true
        viewController.scrollViewDidScroll(screen.table)
        await screen.pump()
        
        #expect(screen.isAtEnd)
        #expect(!screen.isDotShowing)
    }
    
    /// "New" under the header by less than the table's step off the end: the scroll to it stays at the end, so nothing is below.
    @Test
    func anOpeningThatStaysAtTheEndGivesNoDot() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<3) + [Self.marker] + rows(3..<5))
        try await screen.waitForOpening()
        let viewController = try screen.tableViewController()
        let markerFrame = try #require(screen.frameOnScreen(of: "marker"))
        viewController.headerBlockHeight = markerFrame.minY - screen.tableTop + 0.5
        await screen.pump()
        #expect(screen.isAtEnd)
        
        screen.chat.viewModel.state.timelineState.opening = .atRow(.init("marker"))
        try await screen.waitForOpening()
        
        #expect(screen.isAtEnd)
        #expect(!screen.isDotShowing)
    }
    
    /// Opening at "New" away from the end is the app's scroll, not yours: no date comes up over the chat (2026-11-12).
    @Test
    func openingAwayFromTheEndShowsNoDate() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker] + rows(20..<80))
        
        try await screen.waitForOpening()
        await screen.pump()
        
        #expect(!screen.isAtEnd)
        #expect(screen.chat.viewModel.state.bindings.floatingDate == nil)
    }
    
    /// A scroll the app makes, such as a jump, moves no date; one you make with your finger shows it, as before.
    @Test
    func onlyYourOwnScrollShowsTheDate() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<80))
        try await screen.waitForOpening()
        let viewController = try screen.tableViewController()
        let end = screen.table.contentOffset.y
        
        screen.table.contentOffset.y = end + 300
        viewController.scrollViewDidScroll(screen.table)
        await screen.pump()
        #expect(!screen.isAtEnd)
        #expect(screen.chat.viewModel.state.bindings.floatingDate == nil)
        
        viewController.scrollViewWillBeginDragging(screen.table)
        screen.table.contentOffset.y = end + 600
        viewController.scrollViewDidScroll(screen.table)
        await screen.pump()
        
        #expect(screen.chat.viewModel.state.bindings.floatingDate != nil)
    }
    
    /// Two ticks in one turn, onto the day before and back: the badge shows the day the second one is on.
    @Test
    func aTickOntoTheDayBeforeAndBackInTheSameTurnLeavesTheDayShown() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<40) + rows(40..<80, sentFrom: Self.nextDay))
        try await screen.waitForOpening()
        let viewController = try screen.tableViewController()
        let end = screen.table.contentOffset.y
        let oldest = screen.table.contentSize.height - screen.table.bounds.height + screen.table.adjustedContentInset.bottom
        viewController.scrollViewWillBeginDragging(screen.table)
        screen.table.contentOffset.y = end + 100
        viewController.scrollViewDidScroll(screen.table)
        await screen.pump()
        let shownDay = try #require(screen.chat.viewModel.state.bindings.floatingDate)
        #expect(Calendar.current.isDate(shownDay, inSameDayAs: Date(timeIntervalSince1970: Self.nextDay)))
        
        screen.table.contentOffset.y = oldest
        viewController.scrollViewDidScroll(screen.table)
        screen.table.contentOffset.y = end + 100
        viewController.scrollViewDidScroll(screen.table)
        await screen.pump()
        
        let floatingDay = try #require(screen.chat.viewModel.state.bindings.floatingDate)
        #expect(Calendar.current.isDate(floatingDay, inSameDayAs: shownDay))
    }
    
    /// The keyboard going down by as much as you'd scrolled up brings the end to the table, inside its range, so the table
    /// doesn't move and no tick of a scroll comes. (A larger drop takes the offset out of range, and the table's clamp ticks.)
    @Test
    func theKeyboardGoingDownOntoTheEndWithNoScrollLeavesTheChatAtTheEnd() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<60))
        try await screen.waitForOpening()
        let viewController = try screen.tableViewController()
        viewController.additionalSafeAreaInsets.bottom = 50
        await screen.pump()
        let end = screen.table.contentOffset.y
        #expect(screen.isAtEnd)
        screen.table.contentOffset.y = end + 1 + 20
        viewController.scrollViewDidScroll(screen.table)
        await screen.pump()
        #expect(!screen.isAtEnd)
        screen.chat.viewModel.state.bindings.hasNewMessagesAtBottom = true
        
        viewController.additionalSafeAreaInsets.bottom = 30
        await screen.pump()
        
        #expect(screen.table.contentOffset.y == end + 1 + 20)
        #expect(screen.isAtEnd)
        #expect(!screen.isDotShowing)
    }
    
    // MARK: - Helpers
    
    private static let nextDay: TimeInterval = 1000 + 24 * 60 * 60
    
    private func rows(_ range: Range<Int>, sentFrom start: TimeInterval = 1000) -> [RoomTimelineItemProtocol] {
        range.map { index in
            TextRoomTimelineItem(id: .event(uniqueID: .init("\(index)"), eventOrTransactionID: .eventID("$\(index)")),
                                 timestamp: Date(timeIntervalSince1970: start + Double(index)),
                                 isOutgoing: false,
                                 isEditable: false,
                                 canBeRepliedTo: true,
                                 sender: .init(id: Self.them),
                                 content: .init(body: "Message \(index)"))
        }
    }
}
