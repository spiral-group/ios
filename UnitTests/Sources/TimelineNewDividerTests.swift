//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): "New" and the scroll button's dot in the chat, one test per rule of the
// operator's. `TimelineSeenRowsTests` has the row by row detail.
//

import Combine
import Foundation
import MatrixRustSDK
@testable import Spiral
import SwiftUI
import Testing

@MainActor
struct TimelineNewDividerTests {
    private static let me = RoomMemberProxyMock.mockMe.userID
    private static let them = "@alice:spiral.test"
    private static let marker = ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init("marker")))
    
    // MARK: - At the end, with the app active
    
    @Test
    func aReplyAtTheEndGetsNoDividerAndMovesFullyRead() async {
        let chat = TimelineTestChat(items: [row("1")])
        
        await chat.deliver([row("1"), Self.marker, row("2")])
        await chat.settle()
        
        #expect(!chat.isDividerShowing)
        #expect(!chat.isDotShowing)
        #expect(chat.fullyReadRequests == ["$2"])
    }
    
    @Test
    func aDividerShowingStaysAtTheEndAndHoldsFullyRead() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")])
        
        await chat.deliver([row("1"), Self.marker, row("2"), row("3")])
        await chat.settle()
        
        #expect(chat.isDividerShowing)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func theDividerGoesWhenTheSDKDropsIt() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")])
        
        // Read on another device: `m.fully_read` comes in through sync and the SDK takes its marker away.
        await chat.deliver([row("1"), row("2")])
        
        #expect(!chat.isDividerShowing)
    }
    
    // MARK: - Scrolled up
    
    @Test
    func aRowFromSomeoneElseWhileScrolledUpGetsTheDividerAndTheDot() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.scrollUp()
        
        await chat.deliver([row("1"), Self.marker, row("2")])
        
        #expect(chat.isDividerShowing)
        #expect(chat.isDotShowing)
    }
    
    @Test
    func theDotDoesNotHangOnTheDeveloperFlag() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.viewModel.state.jumpToReadMarkerEnabled = false
        chat.scrollUp()
        
        await chat.deliver([row("1"), row("2")])
        
        #expect(chat.isDotShowing)
    }
    
    @Test
    func yourOwnRowGivesNoDot() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.scrollUp()
        
        await chat.deliver([row("1"), row("2", from: Self.me)])
        
        #expect(!chat.isDotShowing)
    }
    
    @Test
    func anEditGivesNoDotAndLeavesTheDivider() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")])
        chat.scrollUp()
        
        await chat.deliver([row("1"), Self.marker, row("2", body: "Edited")])
        
        #expect(chat.isDividerShowing)
        #expect(!chat.isDotShowing)
    }
    
    @Test
    func anAgentsEchoOfYourToolChangeGivesNoDot() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.scrollUp()
        
        await chat.deliver([row("1"), toolChangeByYou("2")])
        
        #expect(!chat.isDotShowing)
    }
    
    @Test
    func noFullyReadWhileScrolledUp() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.scrollUp()
        
        await chat.deliver([row("1"), row("2")])
        await chat.settle()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    // MARK: - Reaching the end
    
    @Test
    func theDividerStaysOnReachingTheEnd() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.scrollUp()
        await chat.deliver([row("1"), Self.marker, row("2")])
        
        chat.viewModel.context.isScrolledToBottom = true
        await chat.settle()
        
        #expect(chat.isDividerShowing)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    // MARK: - Writing
    
    // The operator, 2026-11-12 ("as in Telegram"): "New" stands for the whole visit, through what you write, and goes on leaving.
    
    @Test
    func yourOwnRowLeavesTheDividerWhereItIs() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")])
        
        await chat.deliver([row("1"), Self.marker, row("2"), row("3", from: Self.me)])
        await chat.settle()
        
        // Same place, nothing moved: only your row is new, at the end.
        #expect(chat.itemIDs == ["1", "marker", "2", "3"])
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aReplyWatchedArrivingAfterYouWroteKeepsTheOneDivider() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")])
        await chat.deliver([row("1"), Self.marker, row("2"), row("3", from: Self.me)])
        
        await chat.deliver([row("1"), Self.marker, row("2"), row("3", from: Self.me), row("4")])
        await chat.settle()
        
        #expect(chat.itemIDs == ["1", "marker", "2", "3", "4"])
        #expect(!chat.isDotShowing)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func leavingMovesFullyReadToWhatYouSawUnderTheDivider() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")])
        await chat.deliver([row("1"), Self.marker, row("2"), row("3", from: Self.me)])
        await chat.deliver([row("1"), Self.marker, row("2"), row("3", from: Self.me), row("4")])
        await chat.settle()
        #expect(chat.fullyReadRequests.isEmpty)
        
        await chat.leave()
        
        #expect(chat.fullyReadRequests == ["$4"])
    }
    
    @Test
    func comingBackShowsNoDividerForWhatYouSawAndOneForWhatCameMeanwhile() async {
        let visit = TimelineTestChat(items: [row("1"), Self.marker, row("2")])
        await visit.deliver([row("1"), Self.marker, row("2"), row("3", from: Self.me)])
        await visit.deliver([row("1"), Self.marker, row("2"), row("3", from: Self.me), row("4")])
        await visit.settle()
        await visit.leave()
        let fullyRead = visit.fullyReadRequests.last
        #expect(fullyRead == "$4")
        
        // The SDK places its marker from `m.fully_read`: nothing from someone else after it, no marker.
        let seen = TimelineTestChat(items: [row("1"), row("2"), row("3", from: Self.me), row("4")], fullyReadEventID: fullyRead)
        #expect(!seen.isDividerShowing)
        
        // A row that came while you were away has one, above it.
        let away = TimelineTestChat(items: [row("1"), row("2"), row("3", from: Self.me), row("4"), Self.marker, row("5", at: .now - 30)],
                                    fullyReadEventID: fullyRead)
        #expect(away.itemIDs == ["1", "2", "3", "4", "marker", "5"])
    }
    
    @Test
    func leavingWithYourOwnRowNewestMovesFullyReadToIt() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")])
        await chat.deliver([row("1"), Self.marker, row("2"), row("3", from: Self.me)])
        await chat.settle()
        
        await chat.leave()
        
        #expect(chat.fullyReadRequests == ["$3"])
    }
    
    @Test
    func theAgentsReplyToYourRowGetsNoDivider() async {
        let chat = TimelineTestChat(items: [row("1")])
        
        await chat.deliver([row("1"), row("2", from: Self.me)])
        await chat.deliver([row("1"), row("2", from: Self.me), Self.marker, row("3")])
        
        #expect(!chat.isDividerShowing)
    }
    
    // MARK: - Going to the background
    
    // The operator, 2026-11-12, «Так, як вихід»: going to the background ends the visit, as leaving does.
    
    @Test
    func goingToTheBackgroundMovesFullyReadToWhatYouSawAndTakesTheDividerAway() async {
        let chat = await TimelineTestChat.afterWritingUnderTheDivider()
        
        chat.goToTheBackground()
        await chat.mainQueue()
        try? await Task.sleep(for: .milliseconds(20))
        
        #expect(chat.fullyReadRequests == ["$4"])
        #expect(chat.itemIDs == ["1", "2", "3", "4"])
    }
    
    @Test
    func comingBackShowsNoOldDividerAndAReplyYouWatchGetsNone() async {
        let chat = await TimelineTestChat.afterWritingUnderTheDivider()
        chat.goToTheBackground()
        
        chat.comeBack()
        await chat.settle()
        #expect(chat.itemIDs == ["1", "2", "3", "4"])
        
        // `m.fully_read` hasn't come back through sync: the SDK still has its marker where it was.
        await chat.deliver([row("1"), Self.marker, row("2"), row("3", from: Self.me), row("4"), row("5")])
        #expect(chat.itemIDs == ["1", "2", "3", "4", "5"])
    }
    
    @Test
    func whatArrivedInTheBackgroundGetsItsOwnDividerAndAReplyAfterGetsNone() async {
        let chat = await TimelineTestChat.afterWritingUnderTheDivider()
        chat.goToTheBackground()
        
        // Sent while away, and the SDK's marker is still the old one.
        await chat.deliver([row("1"), Self.marker, row("2"), row("3", from: Self.me), row("4"), row("5", at: .now - 30)])
        chat.comeBack()
        #expect(chat.itemIDs == ["1", "2", "3", "4", "marker", "5"])
        
        // Once `m.fully_read` lands the SDK puts its marker in the same place.
        await chat.deliver([row("1"), row("2"), row("3", from: Self.me), row("4"), Self.marker, row("5", at: .now - 30)])
        #expect(chat.itemIDs == ["1", "2", "3", "4", "marker", "5"])
        
        await chat.deliver([row("1"), row("2"), row("3", from: Self.me), row("4"), Self.marker, row("5", at: .now - 30), row("6")])
        await chat.settle()
        #expect(chat.itemIDs == ["1", "2", "3", "4", "marker", "5", "6"])
    }
    
    @Test
    func aLaunchAfterTheAppWasEndedInTheBackgroundShowsNoOldDivider() async {
        let chat = await TimelineTestChat.afterWritingUnderTheDivider()
        chat.goToTheBackground()
        await chat.mainQueue()
        try? await Task.sleep(for: .milliseconds(20))
        
        // No `stop()`: iOS ended the app. The next launch's SDK places its marker from the `m.fully_read` written above.
        let fullyRead = chat.fullyReadRequests.last
        let launch = TimelineTestChat(items: [row("1"), row("2"), row("3", from: Self.me), row("4")], fullyReadEventID: fullyRead)
        
        #expect(fullyRead == "$4")
        #expect(!launch.isDividerShowing)
    }
    
    @Test
    func theBackgroundAfterLeavingSendsNothingMore() async {
        let chat = await TimelineTestChat.afterWritingUnderTheDivider()
        await chat.leave()
        
        chat.goToTheBackground()
        try? await Task.sleep(for: .milliseconds(20))
        
        #expect(chat.fullyReadRequests == ["$4"])
    }
    
    @Test
    func aThreadHasNoVisitToEnd() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")], kind: .thread(rootEventID: "$root"))
        await chat.settle()
        
        chat.goToTheBackground()
        try? await Task.sleep(for: .milliseconds(20))
        
        #expect(chat.isDividerShowing)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aFailedFullyReadOnLeavingIsTriedOnceMore() async {
        let chat = await TimelineTestChat.afterWritingUnderTheDivider()
        chat.timelineProxy.sendReadReceiptForTypeClosure = { _, _ in .failure(.sdkError(TimelineTestError.failed)) }
        
        await chat.leave()
        
        #expect(chat.fullyReadRequests == ["$4", "$4"])
    }
    
    // MARK: - Away
    
    @Test
    func aRowArrivingInTheBackgroundGetsTheDivider() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.appMediator.appState = .background
        
        await chat.deliver([row("1"), Self.marker, row("2")])
        
        #expect(chat.isDividerShowing)
    }
    
    @Test
    func aRowFromTheBackgroundThatOnlySyncsOnComingBackGetsTheDivider() async {
        let chat = TimelineTestChat(items: [row("1")])
        
        // A suspended app hears nothing: the row turns up once it's active again, sent before that.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await chat.deliver([row("1"), Self.marker, row("2", at: .now - 60)])
        await chat.settle()
        
        #expect(chat.isDividerShowing)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func noFullyReadIfTheAppLeavesDuringTheReceiptsRoundTrip() async {
        let chat = TimelineTestChat(items: [row("1")])
        await chat.deliver([row("1"), row("2")])
        chat.timelineController.sendReadReceiptForClosure = { [appMediator = chat.appMediator] _ in
            appMediator.appState = .background
        }
        
        await chat.settle()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func noFullyReadInTheBackground() async {
        let chat = TimelineTestChat(items: [row("1")])
        await chat.deliver([row("1"), row("2")])
        chat.appMediator.appState = .background
        
        await chat.settle()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    // MARK: - Opening
    
    @Test
    func aChatOpensWithItsDivider() {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")])
        
        #expect(chat.isDividerShowing)
        #expect(!chat.isDotShowing)
    }
    
    @Test
    func aDividerAboveTheLoadedRowsHoldsFullyRead() async {
        let chat = TimelineTestChat(items: [row("5")], unreadMessagesCount: 40, fullyReadEventID: "$1")
        
        await chat.settle()
        await chat.deliver([row("5"), row("6")])
        await chat.settle()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aRowAtTheEndLeavesADividerStillAboveTheLoadedRowsItsPlace() async {
        let chat = TimelineTestChat(items: [row("5")], unreadMessagesCount: 40, fullyReadEventID: "$1")
        await chat.deliver([row("5"), row("6")])
        
        await chat.deliver([row("1"), Self.marker, row("2"), row("5"), row("6")])
        
        #expect(chat.isDividerShowing)
    }
    
    @Test
    func writingEndsADividerAboveTheLoadedRowsToo() async {
        let chat = TimelineTestChat(items: [row("5")], unreadMessagesCount: 40, fullyReadEventID: "$1")
        
        await chat.deliver([row("5"), row("6", from: Self.me)])
        await chat.settle()
        
        #expect(chat.fullyReadRequests == ["$6"])
    }
    
    @Test
    func aFullyReadOnARowlessEventHoldsItToo() async {
        // The last thing on leaving was a reaction. It can't be told from an event above the loaded rows, so this errs on the safe side.
        let chat = TimelineTestChat(items: [row("1")], fullyReadEventID: "$reaction")
        
        await chat.deliver([row("1"), row("2")])
        await chat.settle()
        #expect(chat.fullyReadRequests.isEmpty)
        
        await chat.deliver([row("1"), row("2"), row("3", from: Self.me)])
        await chat.settle()
        #expect(chat.fullyReadRequests == ["$3"])
    }
    
    @Test
    func aColdStartWithAStaleCountHoldsFullyRead() async {
        // Opened from a push before the sync: the count is still 0, and the rows are the latest page.
        let chat = TimelineTestChat(items: [row("30"), row("31")], unreadMessagesCount: 0, fullyReadEventID: "$1")
        
        await chat.settle()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aPageOfRowsTheCountLeavesOutHoldsFullyRead() async {
        // Agent notices and posts aren't in the count, so 0 says nothing about what lies above.
        let chat = TimelineTestChat(items: [row("30")], unreadMessagesCount: 0, fullyReadEventID: "$1")
        
        await chat.deliver([row("30"), row("31")])
        await chat.settle()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    // MARK: - A limited sync
    
    @Test
    func aTimelineReplacedWhileAwayHoldsFullyRead() async {
        let chat = TimelineTestChat(items: [row("1")], fullyReadEventID: "$1")
        await chat.settle()
        chat.timelineProxy.sendReadReceiptForTypeReceivedInvocations = []
        
        await chat.deliver([row("30"), row("31")])
        await chat.settle()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func writingEndsTheHoldAfterATimelineIsReplaced() async {
        let chat = TimelineTestChat(items: [row("1")], fullyReadEventID: "$1")
        await chat.deliver([row("30"), row("31")])
        
        await chat.deliver([row("30"), row("31"), row("32", from: Self.me)])
        await chat.settle()
        
        #expect(chat.fullyReadRequests == ["$32"])
    }
    
    @Test
    func writingBeforeATimelineIsReplacedDoesNotEndTheHold() async {
        let chat = TimelineTestChat(items: [row("1")], fullyReadEventID: "$1")
        await chat.deliver([row("1"), row("2", from: Self.me)])
        await chat.settle()
        chat.timelineProxy.sendReadReceiptForTypeReceivedInvocations = []
        
        await chat.deliver([row("30"), row("31")])
        await chat.settle()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aTimelineReplacedWhileScrolledUpGivesTheDot() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.scrollUp()
        
        await chat.deliver([row("30"), row("31")])
        
        #expect(chat.isDotShowing)
    }
    
    // MARK: - m.fully_read
    
    @Test
    func oneRequestPerSettledState() async {
        let chat = TimelineTestChat(items: [row("1")])
        await chat.deliver([row("1"), row("2")])
        
        await chat.settle()
        await chat.settle()
        await chat.settle()
        
        #expect(chat.fullyReadRequests == ["$2"])
    }
    
    @Test
    func aFailedRequestIsNotRetriedUntilThereIsSomethingNew() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.timelineProxy.sendReadReceiptForTypeClosure = { _, _ in .failure(.sdkError(TimelineTestError.failed)) }
        await chat.deliver([row("1"), Self.marker, row("2")])
        
        await chat.settle()
        await chat.settle()
        #expect(chat.fullyReadRequests == ["$2"])
        
        await chat.deliver([row("1"), Self.marker, row("2"), row("3")])
        await chat.settle()
        #expect(chat.fullyReadRequests == ["$2", "$3"])
    }
    
    @Test
    func aFailedRequestLosesNoDivider() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.timelineProxy.sendReadReceiptForTypeClosure = { _, _ in .failure(.sdkError(TimelineTestError.failed)) }
        await chat.deliver([row("1"), Self.marker, row("2")])
        await chat.settle()
        
        // The SDK's marker stays above the row you watched arrive, and the next one is still marked.
        chat.scrollUp()
        await chat.deliver([row("1"), Self.marker, row("2"), row("3")])
        
        #expect(chat.itemIDs == ["1", "2", "marker", "3"])
    }
    
    @Test
    func aFailedRequestLeavesADividerShowing() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.timelineProxy.sendReadReceiptForTypeClosure = { _, _ in .failure(.sdkError(TimelineTestError.failed)) }
        chat.scrollUp()
        await chat.deliver([row("1"), Self.marker, row("2")])
        
        chat.viewModel.context.isScrolledToBottom = true
        await chat.settle()
        
        #expect(chat.isDividerShowing)
    }
    
    @Test
    func fullyReadIsNeverAPublicReceipt() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.timelineController.sendReadReceiptForClosure = nil // The controller's own part, with the setting in it, is `TimelineControllerTests`.
        await chat.deliver([row("1"), row("2")])
        
        await chat.settle()
        
        #expect(chat.timelineProxy.sendReadReceiptForTypeReceivedInvocations.map(\.type) == [.fullyRead])
    }
    
    // MARK: - Other timelines
    
    @Test
    func aThreadStaysAsItWas() async {
        let chat = TimelineTestChat(items: [row("1")], kind: .thread(rootEventID: "$root"))
        
        await chat.deliver([row("1"), Self.marker, row("2")])
        await chat.settle()
        #expect(chat.isDividerShowing)
        
        chat.scrollUp()
        await chat.deliver([row("1"), Self.marker, row("2"), row("3")])
        await chat.settle()
        #expect(!chat.isDotShowing)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func thePinnedTimelineStaysAsItWas() async {
        let chat = TimelineTestChat(items: [row("1")], kind: .pinned)
        chat.scrollUp()
        
        await chat.deliver([row("1"), row("2")])
        await chat.settle()
        
        #expect(!chat.isDotShowing)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aDetachedTimelineHasNoDotOrFullyRead() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.scrollUp()
        await chat.deliver([row("1"), row("2")])
        #expect(chat.isDotShowing)
        
        chat.timelineController.callbacks.send(.isLive(false))
        await chat.deliver([row("7"), row("8")])
        await chat.settle()
        
        #expect(!chat.isDotShowing)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    // MARK: - The button
    
    @Test
    func markAsReadStaysBehindTheDeveloperFlag() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.scrollUp()
        await chat.deliver([row("1"), row("2")])
        
        chat.viewModel.state.jumpToReadMarkerEnabled = false
        #expect(!chat.viewModel.state.offersMarkAsReadOnScrollToBottom)
        
        chat.viewModel.state.jumpToReadMarkerEnabled = true
        #expect(chat.viewModel.state.offersMarkAsReadOnScrollToBottom)
    }
    
    @Test
    func theDotIsSaidToVoiceOver() {
        #expect(TimelineScrollButton(showsBadge: true) { }.accessibilityValueText == L10n.a11yNotificationsNewMessages)
        #expect(TimelineScrollButton(showsBadge: false) { }.accessibilityValueText.isEmpty)
    }
    
    // MARK: - Helpers
    
    private func row(_ id: String, from sender: String = them, at timestamp: Date = .now + 60, body: String = "Hello") -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)")),
                             timestamp: timestamp,
                             isOutgoing: sender == Self.me,
                             isEditable: false,
                             canBeRepliedTo: true,
                             sender: .init(id: sender),
                             content: .init(body: body))
    }
    
    private func toolChangeByYou(_ id: String) -> StateRoomTimelineItem {
        StateRoomTimelineItem(id: .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)")),
                              body: "You turned a tool on",
                              timestamp: .now + 60,
                              isOutgoing: false,
                              isEditable: false,
                              canBeRepliedTo: false,
                              sender: .init(id: Self.them),
                              isAgentToolChangeByYou: true)
    }
}

private enum TimelineTestError: Error {
    case failed
}

/// A chat with its timeline, at the end with the app active until a test says otherwise.
@MainActor
final class TimelineTestChat {
    let roomProxy: JoinedRoomProxyMock
    let roomInfo: CurrentValueSubject<RoomInfoProxyProtocol, Never>
    let members = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([])
    let timelineProxy: TimelineProxyMock
    let timelineController: TimelineControllerMock
    let appMediator = AppMediatorMock(.init())
    let userIndicatorController = UserIndicatorControllerMock()
    let viewModel: TimelineViewModel
    
    var isDividerShowing: Bool {
        viewModel.state.timelineState.readMarkerUniqueID != nil
    }
    
    var isDotShowing: Bool {
        viewModel.state.bindings.hasNewMessagesAtBottom
    }
    
    var itemIDs: [String] {
        viewModel.state.timelineState.itemViewStates.map { viewState in
            if case .readMarker = viewState.type { "marker" } else { viewState.identifier.uniqueID.value }
        }
    }
    
    var fullyReadRequests: [String] {
        timelineProxy.sendReadReceiptForTypeReceivedInvocations.filter { $0.type == .fullyRead }.map(\.eventID)
    }
    
    init(items: [RoomTimelineItemProtocol],
         kind: TimelineKind = .live,
         unreadMessagesCount: UInt = 0,
         fullyReadEventID: String? = nil,
         focussedEventID: String? = nil,
         isSettled: Bool = true) {
        let configuration = JoinedRoomProxyMockConfiguration(name: "", unreadMessagesCount: unreadMessagesCount, fullyReadEventID: fullyReadEventID)
        roomProxy = JoinedRoomProxyMock(configuration)
        roomInfo = .init(RoomInfoProxyMock(configuration))
        roomProxy.infoPublisher = roomInfo.asCurrentValuePublisher()
        roomProxy.membersPublisher = members.asCurrentValuePublisher()
        // swiftlint:disable:next force_cast
        timelineProxy = roomProxy.timeline as! TimelineProxyMock
        timelineController = TimelineControllerMock(.init(roomProxy: roomProxy,
                                                          timelineKind: kind,
                                                          timelineItems: items,
                                                          paginationState: .init(backward: .idle, forward: .endReached)))
        viewModel = TimelineViewModel(roomProxy: roomProxy,
                                      focussedEventID: focussedEventID,
                                      timelineController: timelineController,
                                      userSession: UserSessionMock(.init()),
                                      mediaPlayerProvider: MediaPlayerProviderMock(),
                                      userIndicatorController: userIndicatorController,
                                      appMediator: appMediator,
                                      analyticsService: AnalyticsServiceMock(.init()),
                                      emojiProvider: EmojiProvider(userSettings: .mock()),
                                      linkMetadataProvider: LinkMetadataProvider(),
                                      timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        if isSettled {
            viewModel.state.timelineState.opening = .settled
        }
    }
    
    func scrollUp() {
        viewModel.context.isScrolledToBottom = false
    }
    
    /// A build from the timeline controller, past its hop to the main queue.
    func deliver(_ items: [RoomTimelineItemProtocol]) async {
        timelineController.timelineItems = items
        timelineController.callbacks.send(.updatedTimelineItems(timelineItems: items, isSwitchingTimelines: false))
        await mainQueue()
    }
    
    /// A chat opened with "New" above 2, where you wrote 3 and watched the reply 4 arrive.
    static func afterWritingUnderTheDivider() async -> TimelineTestChat {
        let me = RoomMemberProxyMock.mockMe.userID
        let marker = ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init("marker")))
        let chat = TimelineTestChat(items: [Self.row("1"), marker, Self.row("2")])
        await chat.deliver([Self.row("1"), marker, Self.row("2"), Self.row("3", from: me)])
        await chat.deliver([Self.row("1"), marker, Self.row("2"), Self.row("3", from: me), Self.row("4")])
        await chat.settle()
        return chat
    }
    
    private static func row(_ id: String, from sender: String = "@alice:spiral.test") -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)")),
                             timestamp: .now + 60,
                             isOutgoing: sender == RoomMemberProxyMock.mockMe.userID,
                             isEditable: false,
                             canBeRepliedTo: true,
                             sender: .init(id: sender),
                             content: .init(body: "Hello"))
    }
    
    /// What `didEnterBackgroundNotification` does, without telling every other chat in the process.
    func goToTheBackground() {
        appMediator.appState = .background
        viewModel.endVisit()
    }
    
    /// Active again, as `didBecomeActiveNotification` says.
    func comeBack() {
        appMediator.appState = .active
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    /// What the room's coordinator does on leaving, past the task it starts.
    func leave() async {
        viewModel.stop()
        try? await Task.sleep(for: .milliseconds(20))
    }
    
    /// What the table does after every change, scroll and appearance.
    func settle() async {
        guard let visibleItemID = viewModel.state.timelineState.itemViewStates.last?.identifier else { return }
        await viewModel.sendReadReceiptIfNeeded(for: visibleItemID)
    }
    
    func mainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
