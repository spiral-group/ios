//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: a room opened right after accepting an invite gets a burst
// of updates — the initial items, pagination state flips and the event that
// arrived with the join. The controller must end on the provider's last state:
// the dev E2E saw a chat stay empty with the SDK holding its first message.
//

import Combine
import Foundation
import MatrixRustSDK
@testable import Spiral
import Testing

@MainActor
struct TimelineControllerUpdateTests {
    private static let ownUserID = "@alice:matrix.org"
    private static let peerID = "@bob:matrix.org"

    @Test
    func aBurstOfUpdatesEndsOnTheProvidersLastItems() async throws {
        let provider = LiveShapedTimelineItemProvider()
        let room = RoomWithChangingInfo()
        let controller = makeController(provider: provider, roomProxy: room.proxy)
        try await waitUntil { controller.paginationState == provider.paginationState }

        // The shape of a room opened just after the join: its info changes
        // as the members arrive (a DM stops and starts being one) while the
        // cached items, back-pagination and the joined event come in — all
        // within one turn of the main actor.
        room.isDM = false
        provider.items = [.text("joined", sender: Self.ownUserID)]
        room.isDM = true
        provider.pagination = .init(backward: .paginating, forward: .endReached)
        provider.items = [.text("joined", sender: Self.ownUserID), .text("first message", sender: Self.peerID)]
        provider.pagination = .init(backward: .endReached, forward: .endReached)

        try await waitUntil { Self.bodies(controller.timelineItems) == provider.items.count }
        // The controller keeps building off the main actor; let any late
        // build land before checking that it did not undo the last state.
        try await Task.sleep(for: .milliseconds(300))
        #expect(Self.bodies(controller.timelineItems) == 2)
    }

    @Test
    func manyBurstsEachEndOnTheLastItems() async throws {
        let provider = LiveShapedTimelineItemProvider()
        let room = RoomWithChangingInfo()
        let controller = makeController(provider: provider, roomProxy: room.proxy)
        try await waitUntil { controller.paginationState == provider.paginationState }

        var items = [TimelineItemProxy]()
        for burst in 1...20 {
            room.isDM.toggle()
            items.append(.text("message \(burst)", sender: Self.peerID))
            provider.items = items
            provider.pagination = .init(backward: .paginating, forward: .endReached)
            room.isDM.toggle()
            provider.pagination = .init(backward: .idle, forward: .endReached)
            await Task.yield()
        }

        try await waitUntil { Self.bodies(controller.timelineItems) == items.count }
        try await Task.sleep(for: .milliseconds(300))
        #expect(Self.bodies(controller.timelineItems) == 20)
    }

    // AGENT-PLATFORM (Brief 0083, question 359)
    @Test
    func updatesInQuickSuccessionLandTogether() async throws {
        let provider = LiveShapedTimelineItemProvider()
        let controller = makeController(provider: provider, roomProxy: RoomWithChangingInfo().proxy)
        try await waitUntil { controller.paginationState == provider.paginationState }
        var builds = 0
        let subscription = controller.callbacks.sink { callback in
            if case .updatedTimelineItems = callback { builds += 1 }
        }

        var items = [TimelineItemProxy]()
        for message in 1...30 {
            items.append(.text("message \(message)", sender: Self.peerID))
            provider.items = items
            try await Task.sleep(for: .milliseconds(5))
        }

        try await waitUntil { Self.bodies(controller.timelineItems) == items.count }
        subscription.cancel()
        // 150 ms of updates or more, at one build a window.
        #expect(builds < 15)
    }

    @Test
    func aLoneUpdateLandsAtOnce() async throws {
        let provider = LiveShapedTimelineItemProvider()
        let controller = makeController(provider: provider, roomProxy: RoomWithChangingInfo().proxy)
        try await waitUntil { controller.paginationState == provider.paginationState }
        try await Task.sleep(for: TimelineController.rebuildWindow * 2)

        let start = ContinuousClock.now
        provider.items = [.text("alone", sender: Self.peerID)]
        try await waitUntil { Self.bodies(controller.timelineItems) == 1 }

        #expect(start.duration(to: .now) < TimelineController.rebuildWindow)
    }

    @Test
    func theLastOfABurstLandsWithoutAnotherUpdate() async throws {
        let provider = LiveShapedTimelineItemProvider()
        let controller = makeController(provider: provider, roomProxy: RoomWithChangingInfo().proxy)
        try await waitUntil { controller.paginationState == provider.paginationState }

        provider.items = [.text("first", sender: Self.peerID)]
        try await waitUntil { Self.bodies(controller.timelineItems) == 1 }
        provider.items = [.text("first", sender: Self.peerID), .text("second", sender: Self.peerID)]

        try await waitUntil { Self.bodies(controller.timelineItems) == 2 }
        #expect(Self.bodies(controller.timelineItems) == 2)
    }

    // MARK: - Helpers

    private static func bodies(_ items: [RoomTimelineItemProtocol]) -> Int {
        items.count { $0 is TextRoomTimelineItem }
    }

    /// Polls for up to 2 s: the controller builds items off the main actor.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(2)
        while !condition(), Date() < end {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func makeController(provider: TimelineItemProviderProtocol, roomProxy: JoinedRoomProxyMock) -> TimelineController {
        TimelineController(roomProxy: roomProxy,
                           timelineProxy: TimelineProxyMock(.init(timelineItemProvider: provider)),
                           initialFocussedEventID: nil,
                           timelineItemFactory: RoomTimelineItemFactory(userID: Self.ownUserID,
                                                                        attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                                                        stateEventStringBuilder: RoomStateEventStringBuilder(userID: Self.ownUserID)),
                           mediaProvider: MediaProviderMock(.init()),
                           userSettings: .mock())
    }
}

/// A DM whose `isDM` can flip, as it does while a just-joined room's members load.
@MainActor
private final class RoomWithChangingInfo {
    let proxy = JoinedRoomProxyMock(.init(name: "Bob", isDirect: true))
    private let infoSubject: CurrentValueSubject<RoomInfoProxyProtocol, Never>

    var isDM = true {
        didSet {
            let info = RoomInfoProxyMock(.init(name: "Bob", isDirect: true))
            info.isDM = isDM
            infoSubject.send(info)
        }
    }

    init() {
        infoSubject = CurrentValueSubject(RoomInfoProxyMock(.init(name: "Bob", isDirect: true)))
        proxy.infoPublisher = infoSubject.asCurrentValuePublisher()
    }
}

/// Publishes like `TimelineItemProvider`: the items and the pagination state
/// are two current-value subjects, combined.
private final class LiveShapedTimelineItemProvider: TimelineItemProviderProtocol {
    private let itemsSubject = CurrentValueSubject<[TimelineItemProxy], Never>([])
    private let paginationSubject = CurrentValueSubject<TimelinePaginationState, Never>(.init(backward: .idle, forward: .endReached))

    var items: [TimelineItemProxy] {
        get { itemsSubject.value }
        set { itemsSubject.send(newValue) }
    }

    var pagination: TimelinePaginationState {
        get { paginationSubject.value }
        set { paginationSubject.send(newValue) }
    }

    var updatePublisher: AnyPublisher<([TimelineItemProxy], TimelinePaginationState), Never> {
        itemsSubject.combineLatest(paginationSubject).eraseToAnyPublisher()
    }

    var itemProxies: [TimelineItemProxy] {
        itemsSubject.value
    }

    var paginationState: TimelinePaginationState {
        paginationSubject.value
    }

    let kind = TimelineKind.live
    let membershipChangePublisher = Empty<Void, Never>().eraseToAnyPublisher()
}

private extension TimelineItemProxy {
    static func text(_ body: String, sender: String) -> TimelineItemProxy {
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: .text(content: .init(body: body, formatted: nil)),
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        return .event(EventTimelineItemProxy(item: EventTimelineItem(configuration: .init(sender: sender, isOwn: sender == "@alice:matrix.org", content: content)),
                                             uniqueID: .init(UUID().uuidString)))
    }
}
