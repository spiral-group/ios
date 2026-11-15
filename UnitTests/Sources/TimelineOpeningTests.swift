//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, questions 363 and 364): where a chat opens, and what leaving it marks as read.
// `TimelineOpeningTableTests` has the real table.
//

import Foundation
import MatrixRustSDK
import MatrixRustSDKMocks
@testable import Spiral
import Testing

@MainActor
struct TimelineOpeningTests {
    private static let me = RoomMemberProxyMock.mockMe.userID
    private static let them = "@alice:spiral.test"
    private static let marker = ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init("marker")))
    private static let markerID = TimelineItemIdentifier.UniqueID("marker")
    private static let rowLessMarkerID = TimelineItemIdentifier.UniqueID("spiral-row-less-read-marker")
    private static let start = Date.now + 60
    
    // MARK: - Where it opens
    
    @Test
    func aChatWithNewOpensAtIt() {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")], isSettled: false)
        
        #expect(chat.opening == .atRow(Self.markerID))
    }
    
    @Test
    func aChatWithNothingUnreadOpensAtTheEnd() {
        let chat = TimelineTestChat(items: [row("1"), row("2")], fullyReadEventID: "$2", isSettled: false)
        
        #expect(chat.opening == .settled)
    }
    
    @Test
    func aChatWithoutRowsYetWaitsForThem() async {
        let chat = TimelineTestChat(items: [], isSettled: false)
        #expect(chat.opening == .undecided)
        
        await chat.deliver([row("1"), Self.marker, row("2")])
        
        #expect(chat.opening == .atRow(Self.markerID))
    }
    
    @Test
    func theCountAloneOpensNothing() {
        // `m.fully_read` is on the newest row, and the count is stale.
        let chat = TimelineTestChat(items: [row("1"), row("2")], unreadMessagesCount: 3, fullyReadEventID: "$2", isSettled: false)
        
        #expect(chat.opening == .settled)
        #expect(!chat.timelineController.paginateBackwardsRequestSizeCalled)
    }
    
    @Test
    func aLinksTargetComesFirst() {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")], unreadMessagesCount: 1, focussedEventID: "$1", isSettled: false)
        
        #expect(chat.opening == .settled)
    }
    
    @Test(arguments: [TimelineKind.thread(rootEventID: "$root"), .pinned, .detached])
    func otherTimelinesOpenAsTheyDid(kind: TimelineKind) {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")], kind: kind, unreadMessagesCount: 1, fullyReadEventID: "$0", isSettled: false)
        
        #expect(chat.opening == .settled)
        #expect(!chat.timelineController.paginateBackwardsRequestSizeCalled)
    }
    
    @Test
    func theDotShowsOnlyAwayFromTheEnd() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")], isSettled: false)
        
        chat.viewModel.context.send(viewAction: .hasSettledOpening(isAwayFromEnd: false))
        await chat.mainQueue()
        #expect(chat.opening == .settled)
        #expect(!chat.isDotShowing)
        
        chat.viewModel.state.timelineState.opening = .atRow(Self.markerID)
        chat.viewModel.context.send(viewAction: .hasSettledOpening(isAwayFromEnd: true))
        await chat.mainQueue()
        #expect(chat.isDotShowing)
    }
    
    @Test
    func newIsNotTakenAwayByOpeningAtIt() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")], fullyReadEventID: "$1")
        
        await chat.settle()
        
        #expect(chat.isDividerShowing)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    // MARK: - Nothing counts until it's settled
    
    @Test
    func noReceiptBeforeTheChatHasSettled() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")], fullyReadEventID: "$1", isSettled: false)
        
        await chat.show("2")
        
        #expect(!chat.timelineController.sendReadReceiptForCalled)
        await chat.leave()
        #expect(chat.readRequests.isEmpty)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    // MARK: - The unread above the loaded rows
    
    @Test
    func unreadAboveTheRowsLoadsThemFirst() async {
        let chat = TimelineTestChat(items: [row("8"), row("9")], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        chat.timelineController.paginateBackwardsRequestSizeClosure = { [weak chat] _ in
            await chat?.deliver([row("1"), Self.marker, row("2"), row("8"), row("9")])
            return .success(())
        }
        #expect(chat.opening == .loadingRows)
        
        await chat.waitFor { chat.opening == .atRow(Self.markerID) }
        
        #expect(chat.timelineController.paginateBackwardsRequestSizeReceivedInvocations == [100])
    }
    
    @Test
    func unreadAboveTheRowsCountsNothingWhileLoading() async {
        let chat = TimelineTestChat(items: [row("8"), row("9")], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in
            try? await Task.sleep(for: .seconds(10))
            return .success(())
        }
        
        await chat.show("9")
        
        #expect(chat.opening == .loadingRows)
        #expect(!chat.timelineController.sendReadReceiptForCalled)
    }
    
    // MARK: - Giving up on the first unread
    
    @Test
    func theLastPageGoneTheNewestRowReadsTheChat() async {
        let chat = TimelineTestChat(items: [row("8"), row("9")], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        
        await chat.waitFor { chat.opening == .settled }
        await chat.show("9")
        
        #expect(chat.timelineController.paginateBackwardsRequestSizeCallsCount == 5)
        #expect(chat.readRequests == ["$9"])
        #expect(chat.fullyReadRequests == ["$9"])
    }
    
    @Test
    func aFailedPageGivesUpAndTheNewestRowReadsTheChat() async {
        let chat = TimelineTestChat(items: [row("8"), row("9")], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in .failure(.generic) }
        
        await chat.waitFor { chat.opening == .settled }
        await chat.show("9")
        
        #expect(chat.timelineController.paginateBackwardsRequestSizeCallsCount == 1)
        #expect(chat.readRequests == ["$9"])
        #expect(chat.fullyReadRequests == ["$9"])
    }
    
    @Test
    func theTimeLimitGivesUpAndTheNewestRowReadsTheChat() async {
        let chat = TimelineTestChat(items: [], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        chat.viewModel.openingTimeLimit = .milliseconds(1)
        chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in
            try? await Task.sleep(for: .seconds(10))
            return .success(())
        }
        await chat.deliver([row("8"), row("9")])
        #expect(chat.opening == .loadingRows)
        
        await chat.waitFor { chat.opening == .settled }
        await chat.show("9")
        
        #expect(chat.readRequests == ["$9"])
        #expect(chat.fullyReadRequests == ["$9"])
    }
    
    @Test
    func aGiveUpHoldsUntilTheNewestRow() async {
        let chat = await chatThatGaveUp()
        
        await chat.show("8")
        #expect(!chat.timelineController.sendReadReceiptForCalled)
        
        await chat.show("9")
        #expect(chat.readRequests == ["$9"])
    }
    
    @Test
    func leavingAfterAGiveUpNamesTheNewestRowToo() async {
        let chat = await chatThatGaveUp()
        chat.scrollUp()
        await chat.show("9")
        #expect(chat.fullyReadRequests.isEmpty)
        
        await chat.leave()
        
        #expect(chat.fullyReadRequests == ["$9"])
    }
    
    @Test
    func aGiveUpLeftBeforeTheNewestRowPassesNothing() async {
        let chat = await chatThatGaveUp()
        
        await chat.leave()
        
        #expect(chat.readRequests.isEmpty)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aLimitedSyncAfterAGiveUpKeepsItsHold() async {
        let chat = await chatThatGaveUp()
        await chat.show("9")
        chat.timelineController.sendReadReceiptForReceivedInvocations = []
        chat.timelineProxy.sendReadReceiptForTypeReceivedInvocations = []
        
        await chat.deliver([row("30"), row("31")])
        await chat.show("31")
        await chat.leave()
        
        #expect(chat.readRequests.isEmpty)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aLimitedSyncBeforeTheNewestRowKeepsItsHold() async {
        let chat = await chatThatGaveUp()
        
        await chat.deliver([row("30"), row("31")])
        await chat.show("31")
        await chat.leave()
        
        #expect(chat.readRequests.isEmpty)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aLinkWhileLoadingIsNoGiveUp() async {
        let chat = await loadingChat()
        await chat.viewModel.focusOnEvent(eventID: "$9")
        
        await chat.show("9")
        
        #expect(!chat.timelineController.sendReadReceiptForCalled)
    }
    
    @Test
    func aLimitedSyncsHoldIsNoGiveUp() async {
        let chat = TimelineTestChat(items: [row("1")], fullyReadEventID: "$1")
        await chat.deliver([row("30"), row("31")])
        
        // The newest row is on screen, and the next opening can still reach what's above.
        await chat.show("31")
        await chat.leave()
        
        #expect(chat.readRequests.isEmpty)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aFailedOpeningPageSaysNothing() async {
        let chat = TimelineTestChat(items: [row("8"), row("9")], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in .failure(.generic) }
        
        await chat.waitFor { chat.opening == .settled }
        
        #expect(!chat.toasts.contains(L10n.errorFailedLoadingMessages))
    }
    
    @Test
    func aFailedPageYouScrolledForStillSaysSo() async {
        let chat = TimelineTestChat(items: [row("8"), row("9")])
        chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in .failure(.generic) }
        
        chat.viewModel.context.send(viewAction: .paginateBackwards)
        
        await chat.waitFor { chat.toasts.contains(L10n.errorFailedLoadingMessages) }
    }
    
    @Test
    func aLinkWhileLoadingComesFirst() async {
        let chat = TimelineTestChat(items: [row("8"), row("9")], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in
            try? await Task.sleep(for: .seconds(10))
            return .success(())
        }
        
        await chat.viewModel.focusOnEvent(eventID: "$9")
        
        #expect(chat.opening == .settled)
        #expect(chat.viewModel.state.timelineState.focussedEvent?.eventID == "$9")
    }
    
    @Test
    func writingEndsTheHoldOnBothReceipts() async {
        let chat = TimelineTestChat(items: [row("1")], fullyReadEventID: "$1")
        await chat.deliver([row("8"), row("9")])
        
        await chat.deliver([row("8"), row("9"), row("10", from: Self.me)])
        await chat.show("10")
        
        #expect(chat.timelineController.sendReadReceiptForCalled)
        #expect(chat.fullyReadRequests == ["$10"])
    }
    
    @Test
    func aLimitedSyncsGapHoldsTheReadReceiptToo() async {
        let chat = TimelineTestChat(items: [row("1")], fullyReadEventID: "$1")
        
        await chat.deliver([row("30"), row("31")])
        await chat.show("31")
        
        #expect(!chat.timelineController.sendReadReceiptForCalled)
    }
    
    // MARK: - Leaving before it has settled
    
    @Test
    func leavingWhileLoadingTakesItsToastDown() async {
        let chat = await loadingChat()
        await chat.waitFor { chat.userIndicatorController.submitIndicatorDelayCalled }
        let toastID = chat.userIndicatorController.submitIndicatorDelayReceivedArguments?.indicator.id
        
        chat.viewModel.stop()
        
        #expect(chat.userIndicatorController.retractIndicatorWithIdReceivedInvocations.contains { $0 == toastID })
    }
    
    @Test
    func leavingBeforeTheToastKeepsItAway() async {
        let chat = await loadingChat()
        await chat.mainQueue()
        
        chat.viewModel.stop()
        try? await Task.sleep(for: .milliseconds(700))
        
        #expect(!chat.userIndicatorController.submitIndicatorDelayCalled)
    }
    
    @Test
    func aPageLandingAfterYouLeftAsksForNoMore() async {
        let chat = TimelineTestChat(items: [row("8"), row("9")], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in
            try? await Task.sleep(for: .milliseconds(20))
            return .success(())
        }
        await chat.waitFor { chat.timelineController.paginateBackwardsRequestSizeCalled }
        
        chat.viewModel.stop()
        try? await Task.sleep(for: .milliseconds(100))
        
        #expect(chat.timelineController.paginateBackwardsRequestSizeCallsCount == 1)
        #expect(chat.opening == .abandoned)
    }
    
    @Test
    func aPageLandingAfterYouLeftReadsNothing() async {
        let chat = await loadingChat()
        chat.viewModel.stop()
        
        // `m.fully_read` comes in with this, which would end the hold on the receipts.
        await chat.deliver([row("1"), Self.marker, row("2"), row("8"), row("9")])
        await chat.show("9")
        
        #expect(chat.opening == .abandoned)
        #expect(!chat.timelineController.sendReadReceiptForCalled)
    }
    
    @Test
    func rowsArrivingAfterYouLeftStartNothing() async {
        let chat = TimelineTestChat(items: [], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        chat.viewModel.stop()
        
        await chat.deliver([row("8"), row("9")])
        
        #expect(chat.opening == .abandoned)
        #expect(!chat.timelineController.paginateBackwardsRequestSizeCalled)
    }
    
    @Test
    func theTablesWordComingInAfterYouLeftOpensNothing() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")], isSettled: false)
        
        chat.viewModel.context.send(viewAction: .hasSettledOpening(isAwayFromEnd: true))
        chat.viewModel.stop()
        await chat.mainQueue()
        
        #expect(chat.opening == .abandoned)
        #expect(!chat.isDotShowing)
    }
    
    @Test
    func leavingASettledChatLeavesItSettled() {
        let chat = TimelineTestChat(items: [row("1"), row("2")], fullyReadEventID: "$2", isSettled: false)
        let retractions = chat.userIndicatorController.retractIndicatorWithIdCallsCount
        
        chat.viewModel.stop()
        
        #expect(chat.opening == .settled)
        #expect(chat.userIndicatorController.retractIndicatorWithIdCallsCount == retractions)
    }
    
    // MARK: - Coming back to a chat left at the end
    
    @Test
    func rowsArrivingWhileAwayAtTheEndOpenAtNew() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.appMediator.appState = .background
        
        await chat.deliver([row("1"), Self.marker, row("2"), row("3")])
        
        #expect(chat.opening == .atRow(Self.markerID))
    }
    
    @Test
    func rowsSentWhileAwayAndSyncedLaterOpenAtNew() async {
        let chat = TimelineTestChat(items: [row("1")])
        
        await chat.deliver([row("1"), Self.marker, row("2", at: .now - 60)])
        
        #expect(chat.opening == .atRow(Self.markerID))
    }
    
    @Test
    func anOlderNewStaysAndTheChatOpensAtTheRowsThatArrived() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")])
        chat.appMediator.appState = .background
        
        await chat.deliver([row("1"), Self.marker, row("2"), row("3")])
        
        #expect(chat.opening == .atRow(.init("3")))
    }
    
    @Test
    func aRowWatchedArrivingMovesNothing() async {
        let chat = TimelineTestChat(items: [row("1")])
        
        await chat.deliver([row("1"), Self.marker, row("2")])
        
        #expect(chat.opening == .settled)
    }
    
    @Test
    func rowsArrivingScrolledUpMoveNothing() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.scrollUp()
        chat.appMediator.appState = .background
        
        await chat.deliver([row("1"), Self.marker, row("2")])
        
        #expect(chat.opening == .settled)
    }
    
    @Test
    func yourOwnRowEndsWhatArrivedAwayFromIt() async {
        let chat = TimelineTestChat(items: [row("1")])
        chat.appMediator.appState = .background
        
        await chat.deliver([row("1"), row("2"), row("3", from: Self.me)])
        
        #expect(chat.opening == .settled)
    }
    
    // MARK: - Leaving
    
    @Test
    func leavingNamesTheNewestRowYouveSeen() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2"), row("3"), row("4")], fullyReadEventID: "$1")
        
        await chat.show("2")
        await chat.show("3")
        await chat.leave()
        
        #expect(chat.readRequests.last == "$3")
        #expect(chat.fullyReadRequests == ["$3"])
        #expect(!chat.roomProxy.markAsReadReceiptTypeCalled)
    }
    
    @Test
    func scrollingBackUpTakesNothingBack() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2"), row("3"), row("4")], fullyReadEventID: "$1")
        
        await chat.show("3")
        await chat.show("2")
        await chat.leave()
        
        #expect(chat.fullyReadRequests == ["$3"])
    }
    
    @Test
    func havingSeenNothingNewItStays() async {
        let chat = TimelineTestChat(items: [row("1"), row("2"), Self.marker, row("3")], fullyReadEventID: "$2")
        
        await chat.show("2")
        await chat.leave()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func itNeverMovesBackwards() async {
        let chat = TimelineTestChat(items: [row("1"), row("2"), row("3")], fullyReadEventID: "$3")
        chat.scrollUp()
        
        await chat.show("2")
        await chat.leave()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func havingSeenNoRowLeavingSendsNothing() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2")], fullyReadEventID: "$1")
        
        await chat.leave()
        
        #expect(chat.readRequests.isEmpty)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func itPassesNoRowsThatWereNeverLoaded() async {
        let chat = TimelineTestChat(items: [row("1")], fullyReadEventID: "$1")
        await chat.show("1")
        chat.timelineProxy.sendReadReceiptForTypeReceivedInvocations = []
        await chat.deliver([row("30"), row("31")])
        
        await chat.show("31")
        await chat.leave()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aFailedReadReceiptPassesNothingElse() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2"), row("3")], fullyReadEventID: "$1")
        chat.timelineProxy.sendReadReceiptForTypeClosure = { _, _ in .failure(.sdkError(TimelineOpeningTestError.failed)) }
        
        await chat.show("2")
        await chat.leave()
        
        // Tried once more, for the same row.
        #expect(chat.fullyReadRequests == ["$2", "$2"])
    }
    
    @Test
    func aRowYouWroteIsARowYouSaw() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2"), row("3")], fullyReadEventID: "$1")
        chat.scrollUp()
        
        await chat.deliver([row("1"), Self.marker, row("2"), row("3"), row("4", from: Self.me)])
        await chat.leave()
        
        #expect(chat.fullyReadRequests == ["$4"])
    }
    
    @Test
    func onADetachedTimelineLeavingNamesOnlyWhatTheLiveOneSaw() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2"), row("3")], fullyReadEventID: "$1")
        await chat.show("2")
        chat.timelineController.sendReadReceiptForReceivedInvocations = []
        chat.timelineController.callbacks.send(.isLive(false))
        await chat.deliver([row("7"), row("8")])
        
        await chat.show("8")
        chat.timelineController.sendReadReceiptForReceivedInvocations = []
        await chat.leave()
        
        #expect(chat.timelineController.sendReadReceiptForReceivedInvocations.isEmpty)
        #expect(chat.fullyReadRequests == ["$2"])
    }
    
    @Test
    func aThreadLeavesNothing() async {
        let chat = TimelineTestChat(items: [row("1"), row("2")], kind: .thread(rootEventID: "$root"))
        
        await chat.show("2")
        chat.timelineController.sendReadReceiptForReceivedInvocations = []
        await chat.leave()
        
        #expect(chat.timelineController.sendReadReceiptForReceivedInvocations.isEmpty)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aLinkBelowNewCountsNothingUntilYouScrollOn() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2"), row("3"), row("4")], fullyReadEventID: "$1", focussedEventID: "$3")
        
        await chat.show("3")
        await chat.leave()
        
        #expect(!chat.timelineController.sendReadReceiptForCalled)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func aLinkWithNewOnScreenCounts() async {
        let chat = TimelineTestChat(items: [row("1"), Self.marker, row("2"), row("3")], fullyReadEventID: "$1", focussedEventID: "$3")
        chat.viewModel.context.isReadMarkerVisible = true
        
        await chat.show("3")
        await chat.leave()
        
        #expect(chat.fullyReadRequests == ["$3"])
    }
    
    @Test
    func leavingTheRoomScreenMarksWhatWasSeen() async {
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        // swiftlint:disable:next force_cast
        let timelineProxy = roomProxy.timeline as! TimelineProxyMock
        let timelineController = TimelineControllerMock(.init(roomProxy: roomProxy,
                                                              timelineItems: [row("1")],
                                                              paginationState: .init(backward: .idle, forward: .endReached)))
        let coordinator = RoomScreenCoordinator(parameters: .init(userSession: UserSessionMock(.init()),
                                                                  roomProxy: roomProxy,
                                                                  timelineController: timelineController,
                                                                  mediaPlayerProvider: MediaPlayerProviderMock(),
                                                                  emojiProvider: EmojiProvider(userSettings: .mock()),
                                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                                  completionSuggestionService: CompletionSuggestionServiceMock(configuration: .init()),
                                                                  ongoingCallRoomIDPublisher: .init(.init(nil)),
                                                                  appMediator: AppMediatorMock(.init()),
                                                                  analytics: AnalyticsServiceMock(.init()),
                                                                  composerDraftService: ComposerDraftServiceMock(.init()),
                                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()),
                                                                  userIndicatorController: UserIndicatorControllerMock()))
        timelineController.callbacks.send(.updatedTimelineItems(timelineItems: [row("1"), row("2", from: Self.me)], isSwitchingTimelines: false))
        try? await Task.sleep(for: .milliseconds(20))
        
        coordinator.stop()
        try? await Task.sleep(for: .milliseconds(20))
        
        #expect(timelineProxy.sendReadReceiptForTypeReceivedInvocations.filter { $0.type == .fullyRead }.map(\.eventID) == ["$2"])
    }
    
    // MARK: - `m.fully_read` on an event with no row
    
    @Test
    func aLoadedFullyReadIsNotLookedUp() async {
        let chat = TimelineTestChat(items: [row("1"), row("2")], fullyReadEventID: "$1")
        
        await chat.deliver([row("1"), row("2"), row("3")])
        
        #expect(!chat.roomProxy.loadOrFetchEventDetailsForCalled)
    }
    
    @Test
    func anEventWithNoRowAmongTheRowsIsNotAboveThem() async {
        let chat = TimelineTestChat(items: [row("1", at: Self.start), row("2", at: Self.start + 20)], fullyReadEventID: "$reaction")
        chat.answerLookup(sentAt: Self.start + 30)
        
        await chat.deliver([row("1", at: Self.start), row("2", at: Self.start + 20), row("3", at: Self.start + 40)])
        await chat.waitFor { chat.viewModel.state.timelineState.isFullyReadWithoutRow }
        
        #expect(!chat.viewModel.state.timelineState.isReadMarkerAboveLoadedRows)
    }
    
    @Test
    func newStandsAboveTheFirstRowAfterAnEventWithNoRow() async {
        let chat = TimelineTestChat(items: [], unreadMessagesCount: 2, fullyReadEventID: "$reaction", isSettled: false)
        chat.answerLookup(sentAt: Self.start + 30)
        
        await chat.deliver([row("1", at: Self.start), row("2", at: Self.start + 20), row("3", at: Self.start + 40), row("4", at: Self.start + 50)])
        await chat.waitFor { chat.opening == .atRow(Self.rowLessMarkerID) }
        
        #expect(chat.itemIDs == ["1", "2", "marker", "3", "4"])
    }
    
    @Test
    func anEventWithNoRowIsFoundWhenTheRowsReachIt() async {
        let chat = TimelineTestChat(items: [], unreadMessagesCount: 2, fullyReadEventID: "$reaction", isSettled: false)
        chat.answerLookup(sentAt: Self.start + 30)
        let newest: [RoomTimelineItemProtocol] = [row("3", at: Self.start + 40), row("4", at: Self.start + 50)]
        let older = [row("2", at: Self.start + 20)] + newest
        chat.timelineController.paginateBackwardsRequestSizeClosure = { [weak chat] _ in
            await chat?.deliver(older)
            return .success(())
        }
        
        await chat.deliver(newest)
        await chat.waitFor { chat.opening == .atRow(Self.rowLessMarkerID) }
        
        #expect(chat.itemIDs == ["2", "marker", "3", "4"])
    }
    
    @Test
    func anEventWithNoRowBehindTheFirstRowIsFoundAtTheStart() async {
        let chat = TimelineTestChat(items: [], unreadMessagesCount: 2, fullyReadEventID: "$hidden", isSettled: false)
        chat.answerLookup(sentAt: Self.start)
        let items: [RoomTimelineItemProtocol] = [row("3", at: Self.start + 40), row("4", at: Self.start + 50)]
        chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in
            try? await Task.sleep(for: .seconds(10))
            return .success(())
        }
        await chat.deliver(items)
        await chat.waitFor { chat.roomProxy.loadOrFetchEventDetailsForCallsCount == 1 }
        await chat.mainQueue()
        
        await chat.reachStart()
        
        #expect(chat.itemIDs == ["marker", "3", "4"])
    }
    
    @Test
    func anEventThatCantBeFoundHoldsNothingAtTheStart() async {
        let chat = await loadingChat()
        await chat.waitForLookup()
        
        await chat.reachStart()
        await chat.waitFor { chat.opening == .settled }
        await chat.show("9")
        
        #expect(chat.readRequests == ["$9"])
        #expect(chat.fullyReadRequests == ["$9"])
    }
    
    @Test
    func aLookupFailingAfterTheStartHoldsNothingEither() async {
        let chat = await loadingChat { _ in
            try? await Task.sleep(for: .milliseconds(50))
            return .failure(.eventNotFound)
        }
        
        await chat.reachStart()
        #expect(chat.opening == .loadingRows)
        
        await chat.waitFor { chat.opening == .settled }
        await chat.show("9")
        
        #expect(chat.fullyReadRequests == ["$9"])
    }
    
    @Test
    func anEventThatCantBeFoundDrawsNoNew() async {
        let chat = await loadingChat()
        await chat.waitForLookup()
        
        await chat.reachStart()
        await chat.waitFor { chat.opening == .settled }
        
        #expect(!chat.isDividerShowing)
    }
    
    @Test
    func aFailedLookupAloneEndsNothing() async {
        let chat = await loadingChat()
        
        await chat.waitForLookup()
        
        // It could be the network, so rows may still lie above.
        #expect(chat.opening == .loadingRows)
        #expect(!chat.viewModel.state.timelineState.isFullyReadWithoutRow)
    }
    
    @Test
    func aFailedLookupKeepsALimitedSyncsHoldUntilTheStart() async {
        let chat = TimelineTestChat(items: [row("1")], fullyReadEventID: "$1")
        await chat.deliver([row("30"), row("31")])
        await chat.waitForLookup()
        
        await chat.show("31")
        #expect(!chat.timelineController.sendReadReceiptForCalled)
        
        await chat.reachStart()
        await chat.show("31")
        #expect(chat.readRequests == ["$31"])
    }
    
    @Test
    func aNewFullyReadStartsAfresh() async {
        let chat = await loadingChat()
        await chat.waitForLookup()
        await chat.reachStart()
        await chat.waitFor { chat.viewModel.state.timelineState.isFullyReadWithoutRow }
        chat.roomProxy.loadOrFetchEventDetailsForClosure = { _ in
            try? await Task.sleep(for: .seconds(10))
            return .failure(.eventNotFound)
        }
        
        chat.roomInfo.send(RoomInfoProxyMock(.init(name: "", fullyReadEventID: "$elsewhere")))
        await chat.mainQueue()
        
        #expect(!chat.viewModel.state.timelineState.isFullyReadWithoutRow)
    }
    
    @Test
    func atTheStartARunningLookupDecidesWhereItOpens() async {
        let chat = TimelineTestChat(items: [], unreadMessagesCount: 2, fullyReadEventID: "$hidden", isSettled: false)
        let event = TimelineEventSDKMock()
        event.timestampReturnValue = UInt64(Self.start.timeIntervalSince1970 * 1000)
        chat.roomProxy.loadOrFetchEventDetailsForClosure = { _ in
            try? await Task.sleep(for: .milliseconds(100))
            return .success(event)
        }
        chat.timelineController.paginateBackwardsRequestSizeClosure = { [weak chat] _ in
            await chat?.reachStart()
            return .success(())
        }
        
        await chat.deliver([row("3", at: Self.start + 40), row("4", at: Self.start + 50)])
        await chat.waitFor { chat.timelineController.paginateBackwardsRequestSizeCalled }
        await chat.mainQueue()
        #expect(chat.opening == .loadingRows)
        
        await chat.waitFor { chat.opening == .atRow(Self.rowLessMarkerID) }
        
        #expect(chat.timelineController.paginateBackwardsRequestSizeCallsCount == 1)
    }
    
    @Test
    func itMovesOnFromAnEventWithNoRow() async {
        let chat = TimelineTestChat(items: [row("1", at: Self.start), row("2", at: Self.start + 40)], fullyReadEventID: "$reaction")
        chat.answerLookup(sentAt: Self.start + 30)
        await chat.deliver([row("1", at: Self.start), row("2", at: Self.start + 40), row("3", at: Self.start + 50)])
        await chat.waitFor { chat.viewModel.state.timelineState.isFullyReadWithoutRow }
        
        await chat.show("3")
        await chat.leave()
        
        #expect(chat.fullyReadRequests.last == "$3")
    }
    
    @Test
    func aFailedLookupHoldsItAsAboveTheRows() async {
        let chat = TimelineTestChat(items: [row("1", at: Self.start), row("2", at: Self.start + 40)], fullyReadEventID: "$reaction")
        await chat.waitFor { chat.roomProxy.loadOrFetchEventDetailsForCallsCount == 1 }
        await chat.mainQueue()
        
        await chat.show("2")
        await chat.leave()
        
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    @Test
    func anEventAboveTheRowsStaysAboveThem() async {
        let chat = TimelineTestChat(items: [], fullyReadEventID: "$old")
        chat.answerLookup(sentAt: Self.start)
        
        await chat.deliver([row("8", at: Self.start + 40), row("9", at: Self.start + 50)])
        await chat.waitFor { chat.roomProxy.loadOrFetchEventDetailsForCallsCount == 1 }
        await chat.mainQueue()
        await chat.show("9")
        await chat.leave()
        
        #expect(chat.viewModel.state.timelineState.isReadMarkerAboveLoadedRows)
        #expect(chat.fullyReadRequests.isEmpty)
    }
    
    // MARK: - Helpers
    
    /// A chat that couldn't reach its "New", at the end with nothing sent yet.
    private func chatThatGaveUp() async -> TimelineTestChat {
        let chat = TimelineTestChat(items: [row("8"), row("9")], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in .failure(.generic) }
        await chat.waitFor { chat.opening == .settled }
        return chat
    }
    
    /// A chat whose "New" is above the loaded rows, with a page that doesn't come back. The time limit is out of reach: a
    /// give-up would end the hold, and pass a test of anything else that does.
    private func loadingChat(lookup: ((String) async -> Result<TimelineEvent, RoomProxyError>)? = nil) async -> TimelineTestChat {
        let chat = TimelineTestChat(items: [], unreadMessagesCount: 40, fullyReadEventID: "$1", isSettled: false)
        chat.viewModel.openingTimeLimit = .seconds(60)
        chat.roomProxy.loadOrFetchEventDetailsForClosure = lookup
        chat.timelineController.paginateBackwardsRequestSizeClosure = { _ in
            try? await Task.sleep(for: .seconds(10))
            return .success(())
        }
        await chat.deliver([row("8"), row("9")])
        return chat
    }
    
    private func row(_ id: String, from sender: String = them, at timestamp: Date = .now + 60) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)")),
                             timestamp: timestamp,
                             isOutgoing: sender == Self.me,
                             isEditable: false,
                             canBeRepliedTo: true,
                             sender: .init(id: sender),
                             content: .init(body: "Hello"))
    }
}

private enum TimelineOpeningTestError: Error {
    case failed
}

private extension TimelineTestChat {
    var opening: TimelineState.Opening {
        viewModel.state.timelineState.opening
    }
    
    var readRequests: [String] {
        timelineController.sendReadReceiptForReceivedInvocations.compactMap(\.eventID)
    }
    
    var toasts: [String] {
        userIndicatorController.submitIndicatorDelayReceivedInvocations.map(\.indicator.title)
    }
    
    /// What the table sends with this row the newest on screen.
    func show(_ id: String) async {
        await viewModel.sendReadReceiptIfNeeded(for: .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)")))
    }
    
    /// The SDK's word that every row is in.
    func reachStart() async {
        timelineController.callbacks.send(.paginationState(.init(backward: .endReached, forward: .endReached)))
        await mainQueue()
    }
    
    /// Past the lookup of a `m.fully_read` that isn't loaded, and the build that follows it.
    func waitForLookup() async {
        await waitFor { roomProxy.loadOrFetchEventDetailsForCalled }
        await mainQueue()
    }
    
    func answerLookup(sentAt date: Date) {
        let event = TimelineEventSDKMock()
        event.timestampReturnValue = UInt64(date.timeIntervalSince1970 * 1000)
        roomProxy.loadOrFetchEventDetailsForReturnValue = .success(event)
    }
    
    func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
