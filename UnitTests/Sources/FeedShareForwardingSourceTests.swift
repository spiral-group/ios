//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Share to chat (lane I3, D-P12): the
// picker leaves out chats with a bridge's puppet or bot, the message sent is
// the one the server built for each chat, and a refused share never says
// "sent".
//

import Combine
import Foundation
import MatrixRustSDK
import MatrixRustSDKMocks
@testable import Spiral
import Testing

@MainActor
struct FeedShareForwardingSourceTests {
    private let service = FeedServiceMock()

    private static func room(id: String, heroes: [String], isSpace: Bool = false) -> RoomSummary {
        RoomSummary(room: RoomSDKMock(), id: id, joinRequestType: nil, isJoined: true, name: id, isDirect: heroes.count == 1, isSpace: isSpace,
                    avatarURL: nil, heroes: heroes.map { UserProfile(userID: $0) }, activeMembersCount: UInt(heroes.count + 1),
                    lastMessage: nil, lastMessageDate: nil, lastMessageState: nil, unreadMessagesCount: 0, unreadMentionsCount: 0,
                    unreadNotificationsCount: 0, notificationMode: nil, canonicalAlias: nil, alternativeAliases: [],
                    hasOngoingCall: false, activeCallIntent: nil, isMarkedUnread: false, isFavourite: false, isTombstoned: false)
    }

    @Test(arguments: [("@telegram_123:spiral.md", true), ("@whatsapp_380:spiral.md", true), ("@instagram_ann:spiral.md", true),
                      ("@telegrambot:spiral.md", true), ("@instagram-login-bot:spiral.md", true),
                      ("@ann:spiral.md", false), ("@telegramfan:spiral.md", false), ("telegram_1", false)])
    func bridgeUsersAreToldByTheirNamespace(userID: String, isBridged: Bool) {
        #expect(SpiralBridgeUsers.isBridgeUser(userID) == isBridged)
    }

    @Test
    func thePickerLeavesOutBridgedChatsOnly() {
        let source = FeedShareForwardingSource(postID: FeedPreviewData.textPost.id, feedService: service)

        #expect(!source.excludes(Self.room(id: "!spiral:spiral.md", heroes: ["@ann:spiral.md", "@bob:spiral.md"])))
        #expect(source.excludes(Self.room(id: "!tg:spiral.md", heroes: ["@telegram_123:spiral.md"])))
        #expect(source.excludes(Self.room(id: "!group:spiral.md", heroes: ["@ann:spiral.md", "@whatsappbot:spiral.md"])))
        #expect(source.excludes(Self.room(id: "!space:spiral.md", heroes: [], isSpace: true)))
    }

    @Test
    func theMessageIsTheOneTheServerBuiltForTheChat() async throws {
        service.sharePostIDRoomIDLanguageReturnValue = .success(FeedShareMessage(body: "Hello\n\nView the post in Spiral: https://spiral.md/feed/x",
                                                                                 shares: 1))
        let source = FeedShareForwardingSource(postID: FeedPreviewData.textPost.id, feedService: service, language: "uk")

        // The SDK's content has no getter: what it was built from is the server's answer.
        _ = try await source.contents(for: "!room:spiral.md").get()

        #expect(service.sharePostIDRoomIDLanguageReceivedArguments?.roomID == "!room:spiral.md")
        #expect(service.sharePostIDRoomIDLanguageReceivedArguments?.language == "uk")
    }

    @Test(arguments: [(FeedError.shareBridgedRoom, UntranslatedL10n.screenFeedShareBridgedRoom),
                      (.notFound, UntranslatedL10n.screenFeedPostNotAvailableTitle),
                      (.temporarilyUnavailable(retryAfterSeconds: 5), UntranslatedL10n.screenFeedShareFailed)])
    func aRefusedShareSaysWhy(error: FeedError, message: String) async {
        service.sharePostIDRoomIDLanguageReturnValue = .failure(error)
        let source = FeedShareForwardingSource(postID: FeedPreviewData.textPost.id, feedService: service)

        let result = await source.contents(for: "!room:spiral.md")

        guard case .failure(let failure) = result else {
            Issue.record("A refused share must not build a message")
            return
        }
        #expect(failure.message == message)
    }

    /// A failure is not an answer: the picker never reports a chat the server refused as sent.
    @Test
    func aRefusedShareIsNeverSent() async throws {
        service.sharePostIDRoomIDLanguageClosure = { _, roomID, _ in
            roomID == "1" ? .failure(.shareBridgedRoom) : .success(FeedShareMessage(body: "Hello", shares: 1))
        }
        let timeline = TimelineProxyMock(.init())
        timeline.sendMessageEventContentReturnValue = .success(())
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomForIdentifierClosure = { id in
            let room = JoinedRoomProxyMock(.init(id: id))
            room.timeline = timeline
            return .joined(room)
        }
        let source = FeedShareForwardingSource(postID: FeedPreviewData.textPost.id, feedService: service)
        let viewModel = MessageForwardingScreenViewModel(forwardingPayload: source,
                                                         userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                                         roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(.mockRooms))),
                                                         userIndicatorController: UserIndicatorControllerMock())
        #expect(viewModel.context.viewState.title == UntranslatedL10n.screenFeedShareTitle)
        #expect(viewModel.context.viewState.rooms.count == [RoomSummary].mockRooms.count { !$0.isTombstoned }, "A feed post has no source room to leave out")

        let sent = deferFulfillment(viewModel.actions) { action in
            if case .sent(let roomIDs) = action { roomIDs == ["2"] } else { false }
        }
        viewModel.context.send(viewAction: .selectRoom(roomID: "1"))
        viewModel.context.send(viewAction: .selectRoom(roomID: "2"))
        viewModel.context.send(viewAction: .send)
        try await sent.fulfill()

        #expect(timeline.sendMessageEventContentCallsCount == 1)
        #expect(service.sharePostIDRoomIDLanguageCallsCount == 2)
        #expect(source.failedRoomCount == 1, "The final toast names the chat refused")
    }

    /// The last toast of a send names what could not be shared instead of hiding it.
    @Test
    func theToastNamesBothCountsWhenSomeChatsWereRefused() {
        #expect(FeedShareForwardingSource.sharedMessage(sent: 2, failed: 0) == "Shared to 2 chats")
        #expect(FeedShareForwardingSource.sharedMessage(sent: 2, failed: 1) == "Shared to 2 chats, 1 couldn't be shared")
        #expect(FeedShareForwardingSource.sharedMessage(sent: 1, failed: 3) == "Shared to 1 chat, 3 couldn't be shared")
    }

    // MARK: - One send at a time (the forwarding screen's guard)

    /// A forward through the patched screen, an ordinary one unless `source` says otherwise, with its timeline under the test's control.
    private static func forwardingViewModel(source: (any MessageForwardingSource)? = nil, timeline: TimelineProxyMock) -> MessageForwardingScreenViewModel {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomForIdentifierClosure = { id in
            let room = JoinedRoomProxyMock(.init(id: id))
            room.timeline = timeline
            return .joined(room)
        }
        let payload = MessageForwardingPayload(ids: [.event(uniqueID: .init("t1"), eventOrTransactionID: .eventID("t1"))],
                                               roomID: "source",
                                               contents: [RoomMessageEventContentWithoutRelationSDKMock()])
        return MessageForwardingScreenViewModel(forwardingPayload: source ?? payload,
                                                userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                                roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(.mockRooms))),
                                                userIndicatorController: UserIndicatorControllerMock())
    }

    @Test
    func aSecondSendWhileSendingSendsNothingMore() async throws {
        let timeline = TimelineProxyMock(.init())
        var viewModel: MessageForwardingScreenViewModel!
        var forwardingDuringSend = false
        timeline.sendMessageEventContentClosure = { _ in
            if timeline.sendMessageEventContentCallsCount == 1 {
                forwardingDuringSend = viewModel.context.viewState.isForwarding
                viewModel.context.send(viewAction: .send)
            }
            return .success(())
        }
        viewModel = Self.forwardingViewModel(timeline: timeline)
        var sentCount = 0
        let cancellable = viewModel.actions.sink { if case .sent = $0 { sentCount += 1 } }
        defer { cancellable.cancel() }

        let sent = deferFulfillment(viewModel.actions) { if case .sent = $0 { true } else { false } }
        viewModel.context.send(viewAction: .selectRoom(roomID: "2"))
        viewModel.context.send(viewAction: .send)
        try await sent.fulfill()
        try await Task.sleep(for: .milliseconds(100))

        #expect(forwardingDuringSend)
        #expect(timeline.sendMessageEventContentCallsCount == 1)
        #expect(sentCount == 1)
        #expect(!viewModel.context.viewState.isForwarding)
    }

    @Test
    func cancelDoesNothingWhileSending() async throws {
        let timeline = TimelineProxyMock(.init())
        var viewModel: MessageForwardingScreenViewModel!
        timeline.sendMessageEventContentClosure = { _ in
            viewModel.context.send(viewAction: .cancel)
            return .success(())
        }
        viewModel = Self.forwardingViewModel(timeline: timeline)
        var dismissed = false
        let cancellable = viewModel.actions.sink { if case .dismiss = $0 { dismissed = true } }
        defer { cancellable.cancel() }

        let sent = deferFulfillment(viewModel.actions) { if case .sent = $0 { true } else { false } }
        viewModel.context.send(viewAction: .selectRoom(roomID: "2"))
        viewModel.context.send(viewAction: .send)
        try await sent.fulfill()

        #expect(!dismissed)
    }

    /// A share swiped away mid-send: the next chat is not shared to, and only the chats sent count.
    @Test
    func aDismissalStopsAFeedShareBeforeTheNextRoom() async throws {
        service.sharePostIDRoomIDLanguageReturnValue = .success(FeedShareMessage(body: "Hello", shares: 1))
        let timeline = TimelineProxyMock(.init())
        var viewModel: MessageForwardingScreenViewModel!
        timeline.sendMessageEventContentClosure = { _ in
            viewModel.stop()
            return .success(())
        }
        let source = FeedShareForwardingSource(postID: FeedPreviewData.textPost.id, feedService: service)
        viewModel = Self.forwardingViewModel(source: source, timeline: timeline)

        let sent = deferFulfillment(viewModel.actions) { if case .sent(let roomIDs) = $0 { roomIDs.count == 1 } else { false } }
        for roomID in ["1", "2", "3"] {
            viewModel.context.send(viewAction: .selectRoom(roomID: roomID))
        }
        viewModel.context.send(viewAction: .send)
        try await sent.fulfill()

        #expect(timeline.sendMessageEventContentCallsCount == 1)
        #expect(service.sharePostIDRoomIDLanguageCallsCount == 1, "No share is built for a chat after the dismissal")
    }

    /// Upstream's forward is not the feed's: a dismissal mid-send still reaches every room picked.
    @Test
    func aDismissalLetsAnOrdinaryForwardFinishEveryRoom() async throws {
        let timeline = TimelineProxyMock(.init())
        var viewModel: MessageForwardingScreenViewModel!
        timeline.sendMessageEventContentClosure = { _ in
            viewModel.stop()
            return .success(())
        }
        viewModel = Self.forwardingViewModel(timeline: timeline)

        let sent = deferFulfillment(viewModel.actions) { if case .sent(let roomIDs) = $0 { Set(roomIDs) == ["1", "2", "3"] } else { false } }
        for roomID in ["1", "2", "3"] {
            viewModel.context.send(viewAction: .selectRoom(roomID: roomID))
        }
        viewModel.context.send(viewAction: .send)
        try await sent.fulfill()

        #expect(timeline.sendMessageEventContentCallsCount == 3)
    }

    @Test
    func theShareSheetOpensFromLatestOnly() {
        #expect(FeedTabFlowCoordinator.nextState(from: .feed, on: .presentShare) == .shareSheet)
        #expect(FeedTabFlowCoordinator.nextState(from: .shareSheet, on: .dismissedShare) == .feed)
        #expect(FeedTabFlowCoordinator.nextState(from: .authorSheet, on: .presentShare) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .shareSheet, on: .presentComposer) == nil)
        #expect(FeedTabFlowCoordinator.nextState(from: .composerSheet, on: .dismissedShare) == nil)
    }
}
