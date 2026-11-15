//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 item 16): a row re-renders when what it draws changes, and nothing else reaches it.
// Each test here failed while the bubble read the view model's context, or the build assigned every row whether or not it changed.
//

import Combine
import Foundation
import MatrixRustSDK
@testable import Spiral
import SwiftUI
import Synchronization
import Testing

@MainActor
struct TimelineRowUpdateTests {
    private static let me = RoomMemberProxyMock.mockMe.userID
    private static let them = "@alice:spiral.test"
    /// A name whose initial isn't the MXID's, as a call shows only the initial until there's a picture.
    private static let member = RoomMemberProxyMock(with: .init(userID: "@bob:spiral.test", displayName: "Zed", membership: .join))
    
    // MARK: - On screen
    
    @Test
    func aTypingNoticeReachesNoRow() async throws {
        let screen = try await rowsOnScreen()
        
        let bodies = await screen.bodiesRun { screen.chat.viewModel.state.typingMembers = [Self.them] }
        
        #expect(bodies.all.isEmpty)
    }
    
    @Test
    func aChangeOutsideTheRowsReachesNoRow() async throws {
        let screen = try await rowsOnScreen()
        
        let bodies = await screen.bodiesRun { screen.chat.viewModel.state.showLoading = true }
        
        #expect(bodies.all.isEmpty)
    }
    
    @Test
    func aPinElsewhereReachesThatRowAlone() async throws {
        let screen = try await rowsOnScreen()
        
        let bodies = await screen.bodiesRun { screen.chat.viewModel.state.pinnedEventIDs = ["$\(Self.newest)"] }
        
        #expect(bodies.all == ["\(Self.newest)"])
    }
    
    @Test
    func aPinOfARowOffScreenReachesNoRow() async throws {
        let screen = try await rowsOnScreen()
        
        let bodies = await screen.bodiesRun { screen.chat.viewModel.state.pinnedEventIDs = ["$0"] }
        
        #expect(bodies.all.isEmpty)
    }
    
    @Test
    func aBuildThatChangesNothingReachesNoRow() async throws {
        let screen = try await rowsOnScreen()
        
        let bodies = await screen.bodiesRun { await screen.deliver(rows()) }
        
        #expect(bodies.all.isEmpty)
    }
    
    @Test
    func aReceiptThatMovesNoTickReachesNoRow() async throws {
        let screen = try await rowsOnScreen()
        
        let bodies = await screen.bodiesRun {
            // Read up to an incoming row: no own message is on the way.
            screen.chat.timelineController.readProgress = .init(events: [event(1, isOwn: false, readBy: [Self.them])], ownUserID: Self.me)
            await screen.deliver(rows())
        }
        
        #expect(bodies.all.isEmpty)
    }
    
    @Test
    func aReceiptReachesTheRowsWhoseTicksMove() async throws {
        let screen = try await rowsOnScreen()
        let newestOwn = Self.newest - 2
        
        let bodies = await screen.bodiesRun {
            screen.chat.timelineController.readProgress = .init(events: [event(newestOwn, isOwn: true, readBy: [Self.them])], ownUserID: Self.me)
            await screen.deliver(rows())
        }
        
        #expect(bodies.all == ["\(newestOwn)"])
    }
    
    @Test
    func aChangedRowReachesThatRowAlone() async throws {
        let screen = try await rowsOnScreen()
        var items = rows()
        items[Self.newest] = row(Self.newest, body: "Edited")
        
        let bodies = await screen.bodiesRun { await screen.deliver(items) }
        
        #expect(bodies.rows == ["\(Self.newest)"])
        #expect(bodies.bubbles == ["\(Self.newest)"])
    }
    
    @Test
    func aNewRowLeavesTheRowsBeforeItAlone() async throws {
        let screen = try await rowsOnScreen()
        
        // Rows from different people, so the new one changes no group.
        let bodies = await screen.bodiesRun { await screen.deliver(rows() + [row(Self.newest + 1)]) }
        
        #expect(bodies.all == ["\(Self.newest + 1)"])
    }
    
    @Test
    func anUpdateOfTheStateComparesNoRows() async throws {
        let screen = try await rowsOnScreen()
        var items = rows()
        items[Self.newest] = row(Self.newest, body: "Edited")
        await screen.deliver(items) // The table's rows and the state's are different dictionaries from here.
        await screen.pump()
        TimelineSignposts.rowComparisons = 0
        
        screen.chat.viewModel.state.typingMembers = [Self.them]
        await screen.pump()
        screen.chat.viewModel.state.typingMembers = []
        await screen.pump()
        
        #expect(TimelineSignposts.rowComparisons == 0)
    }
    
    @Test
    func aChangedRowLeavesTheTableWhereItWas() async throws {
        let screen = try await rowsOnScreen()
        let receipts = screen.receipts.count
        var items = rows()
        items[Self.newest] = row(Self.newest, body: "Edited")
        
        await screen.deliver(items)
        await screen.pump()
        
        // A table told of new rows sends its read receipt again.
        #expect(screen.receipts.count == receipts)
    }
    
    @Test
    func aNewRowReachesTheTable() async throws {
        let screen = try await rowsOnScreen()
        
        await screen.deliver(rows() + [row(Self.newest + 1)])
        await screen.pump()
        
        #expect(screen.table.numberOfRows(inSection: 0) == Self.newest + 2)
    }
    
    @Test
    func aRowShowsItsOwnTextInATextViewThatWasAnothers() async throws {
        let screen = try await TimelineTestScreen(items: rows(count: 200), isRendered: true)
        try await screen.waitForOpening()
        var textViews = Set<ObjectIdentifier>()
        var rowsSeen = Set<String>()
        
        for _ in 0..<30 {
            screen.table.contentOffset.y += 400
            screen.table.layoutIfNeeded()
            await screen.pump()
            
            for cell in screen.table.visibleCells {
                guard let item = (cell as? TimelineItemCell)?.item, case .text(let text) = item.type else { continue }
                let textView = try #require(Self.textView(in: cell))
                #expect(textView.attributedText.string.hasPrefix(text.body))
                #expect(textView.window != nil)
                textViews.insert(ObjectIdentifier(textView))
                rowsSeen.insert(item.id.value)
            }
        }
        
        #expect(rowsSeen.count > 100)
        #expect(textViews.count < rowsSeen.count / 2)
    }
    
    @Test
    func anEditShowsInTheRow() async throws {
        let screen = try await TimelineTestScreen(items: rows(), isRendered: true)
        try await screen.waitForOpening()
        var items = rows()
        items[Self.newest] = row(Self.newest, body: "Edited")
        
        await screen.deliver(items)
        
        let cell = try #require(screen.table.cellForRow(at: IndexPath(row: 0, section: 0)))
        #expect(try #require(Self.textView(in: cell)).attributedText.string.hasPrefix("Edited"))
    }
    
    // MARK: - The model
    
    @Test
    func aBuildAssignsOnlyTheRowThatChanged() async {
        let chat = TimelineTestChat(items: rows())
        let changes = RowChanges(chat)
        var items = rows()
        items[3] = row(3, body: "Edited")
        
        await chat.deliver(items)
        
        #expect(changes.rows == ["3"])
    }
    
    @Test
    func aBuildOfTheSameItemsAssignsNoRow() async {
        let chat = TimelineTestChat(items: rows())
        let changes = RowChanges(chat)
        
        await chat.deliver(rows())
        
        #expect(changes.rows.isEmpty)
    }
    
    @Test
    func aBuildThatChangesNothingLeavesTheStateAlone() async {
        let chat = TimelineTestChat(items: rows())
        await chat.mainQueue() // The room info's first value.
        var writes = 0
        let subscription = chat.viewModel.context.objectWillChange.sink { writes += 1 }
        
        await chat.deliver(rows())
        
        #expect(writes == 0)
        subscription.cancel()
    }
    
    @Test
    func aBuildThatChangesNothingKeepsItsID() async {
        let chat = TimelineTestChat(items: rows())
        let buildID = chat.viewModel.state.timelineState.buildID
        
        await chat.deliver(rows())
        
        #expect(chat.viewModel.state.timelineState.buildID == buildID)
    }
    
    @Test
    func aChangedRowMovesTheBuildIDAndWritesTheStateOnce() async {
        let chat = TimelineTestChat(items: rows())
        await chat.mainQueue() // The room info's first value.
        let buildID = chat.viewModel.state.timelineState.buildID
        var writes = 0
        let subscription = chat.viewModel.context.objectWillChange.sink { writes += 1 }
        var items = rows()
        items[3] = row(3, body: "Edited")
        
        await chat.deliver(items)
        
        #expect(chat.viewModel.state.timelineState.buildID == buildID + 1)
        #expect(writes == 1)
        subscription.cancel()
    }
    
    @Test
    func aRowThatComesAndGoesInOneBuildStillMovesTheBuildID() async {
        let chat = TimelineTestChat(items: [row(1), row(2)])
        let buildID = chat.viewModel.state.timelineState.buildID
        
        await chat.deliver([row(2), row(1)])
        
        #expect(chat.viewModel.state.timelineState.buildID != buildID)
    }
    
    @Test
    func aGroupStyleThatMovesReachesItsRow() async {
        let chat = TimelineTestChat(items: [row(1)])
        let changes = RowChanges(chat)
        
        await chat.deliver([row(1), row(2, sender: "@1:spiral.test")])
        
        #expect(changes.rows == ["1"])
    }
    
    @Test
    func aFoldHearsOfAChangeToARowInIt() async {
        let fold = CollapsibleTimelineItem(items: [stateRow(1, body: "Alice joined"), stateRow(2, body: "Bob joined")])
        let chat = TimelineTestChat(items: [fold])
        let changes = RowChanges(chat)
        
        await chat.deliver([CollapsibleTimelineItem(items: [stateRow(1, body: "Alicia joined"), stateRow(2, body: "Bob joined")])])
        
        #expect(changes.rows == ["1"])
    }
    
    @Test
    func aRowTakesWhatItShowsFromTheState() {
        let chat = TimelineTestChat(items: rows())
        chat.viewModel.state.pinnedEventIDs = ["$1"]
        chat.viewModel.state.messageSelection.isActive = true
        chat.viewModel.state.messageSelection.selectedEventIDs = ["$2"]
        chat.viewModel.state.stoppedLiveLocationIDs = [row(3).id]
        chat.viewModel.context.reactionsCollapsed[row(4).id] = false
        
        #expect(context(of: 1, in: chat).isPinned)
        #expect(!context(of: 2, in: chat).isPinned)
        #expect(context(of: 2, in: chat).isSelected)
        #expect(!context(of: 1, in: chat).isSelected)
        #expect(context(of: 1, in: chat).isSelecting)
        #expect(context(of: 1, in: chat).selectedCount == 1)
        #expect(context(of: 3, in: chat).isLiveLocationStopped)
        #expect(!context(of: 4, in: chat).areReactionsCollapsed)
        #expect(context(of: 1, in: chat).areReactionsCollapsed)
    }
    
    @Test
    func aPinnedTimelineDrawsNoPinMark() {
        let chat = TimelineTestChat(items: rows(), kind: .pinned)
        
        chat.viewModel.state.pinnedEventIDs = ["$1"]
        
        #expect(!context(of: 1, in: chat).isPinned)
        #expect(context(of: 1, in: chat).timelineKind == .pinned)
    }
    
    @Test
    func aNewRowComesWithItsContext() async {
        let chat = TimelineTestChat(items: rows())
        await chat.mainQueue() // The room info's first value, which has no pins.
        chat.viewModel.state.pinnedEventIDs = ["$\(Self.newest + 1)"]
        
        await chat.deliver(rows() + [row(Self.newest + 1)])
        
        #expect(context(of: Self.newest + 1, in: chat).isPinned)
    }
    
    @Test
    func aChangeOfTheMembersReachesTheQuotesAlone() async throws {
        let quoted = row(Self.newest, body: "A reply", replyDetails: .loaded(sender: .init(id: Self.them),
                                                                             eventID: "$quoted",
                                                                             eventContent: .message(.text(.init(body: "@bob:spiral.test", formattedBody: mention)))))
        let screen = try await TimelineTestScreen(items: rows().dropLast() + [quoted])
        try await screen.waitForOpening()
        let hasQuoteRedrawn = Mutex(false)
        withObservationTracking {
            _ = screen.chat.viewModel.state.buildMessagePreview(formattedBody: mention, plainBody: "")
        } onChange: {
            hasQuoteRedrawn.withLock { $0 = true }
        }
        
        let bodies = await screen.bodiesRun { screen.chat.members.send([RoomMemberProxyMock.mockBob]) }
        
        #expect(hasQuoteRedrawn.withLock { $0 })
        #expect(bodies.all.isEmpty) // A quote redraws by itself, inside the row.
    }
    
    @Test
    func aRelayedNoteNamesItsSenderOnceTheMembersAreIn() async throws {
        try await expectTheNewestRowRedrawsForTheMembers(rows().dropLast() + [relayedNote(Self.newest)])
    }
    
    @Test
    func aCallNamesItsMembersOnceTheMembersAreIn() async throws {
        try await expectTheNewestRowRedrawsForTheMembers(rows().dropLast() + [activeCall(Self.newest)])
    }
    
    @Test
    func aQuoteNamesAMentionOnceTheMembersAreIn() {
        let chat = TimelineTestChat(items: rows())
        #expect(chat.viewModel.state.buildMessagePreview(formattedBody: mention, plainBody: "") == "@bob:spiral.test")
        
        chat.viewModel.state.members = ["@bob:spiral.test": .init(displayName: "Bob", avatarURL: nil, status: .init(raw: nil, call: nil))]
        
        #expect(chat.viewModel.state.buildMessagePreview(formattedBody: mention, plainBody: "") == "@Bob")
    }
    
    @Test
    func theSameMembersAreNoChange() async {
        let chat = TimelineTestChat(items: rows())
        chat.members.send([RoomMemberProxyMock.mockAlice])
        await chat.mainQueue()
        let before = chat.viewModel.state.membersRevision.value
        
        chat.members.send([RoomMemberProxyMock.mockAlice])
        await chat.mainQueue()
        
        #expect(chat.viewModel.state.membersRevision.value == before)
    }
    
    @Test
    func aPurgeEmptiesThePoolOfTextViews() async {
        let chat = TimelineTestChat(items: rows())
        let textView = MessageTextView.pool.take()
        MessageTextView.pool.put(textView)
        await chat.mainQueue()
        
        TimelineCaches.purge()
        
        #expect(MessageTextView.pool.take() !== textView)
    }
    
    @Test
    func aDraftHearsOfTheRoomItPublishesTo() {
        let chat = TimelineTestChat(items: rows(), kind: .thread(rootEventID: "$root"))
        
        chat.viewModel.setSpiralPublishRoom(.init(id: "!other:spiral.test", name: "Other"))
        
        #expect(context(of: 1, in: chat).publishRoomName == "Other")
    }
    
    // MARK: - Helpers
    
    private static let newest = 59
    
    private func rowsOnScreen() async throws -> TimelineTestScreen {
        let screen = try await TimelineTestScreen(items: rows())
        try await screen.waitForOpening()
        await screen.pump()
        return screen
    }
    
    /// Own and other people's in turn, each from a sender of its own so no row's group hangs on another's.
    private func rows(count: Int = newest + 1) -> [RoomTimelineItemProtocol] {
        (0..<count).map { row($0) }
    }
    
    private static func textView(in view: UIView) -> MessageTextView? {
        if let textView = view as? MessageTextView {
            return textView
        }
        return view.subviews.lazy.compactMap(textView).first
    }
    
    private var mention: AttributedString {
        var attributedString = AttributedString("to be replaced")
        attributedString.userID = "@bob:spiral.test"
        return attributedString
    }
    
    private func row(_ index: Int, body: String? = nil, sender: String? = nil, replyDetails: TimelineItemReplyDetails? = nil) -> TextRoomTimelineItem {
        let isOutgoing = index.isMultiple(of: 3)
        return TextRoomTimelineItem(id: .event(uniqueID: .init("\(index)"), eventOrTransactionID: .eventID("$\(index)")),
                                    timestamp: Date(timeIntervalSince1970: 1000 + Double(index)),
                                    isOutgoing: isOutgoing,
                                    isEditable: false,
                                    canBeRepliedTo: true,
                                    sender: .init(id: sender ?? (isOutgoing ? Self.me : "@\(index):spiral.test")),
                                    content: .init(body: body ?? "Message \(index)"),
                                    properties: .init(replyDetails: replyDetails))
    }
    
    /// What's drawn of a row hangs on the members, and it's the row's own leaf that redraws: the row itself stays out of it.
    private func expectTheNewestRowRedrawsForTheMembers(_ items: [RoomTimelineItemProtocol]) async throws {
        let screen = try await TimelineTestScreen(items: items, isRendered: true)
        try await screen.waitForOpening()
        let before = try screen.picture(of: "\(Self.newest)")
        #expect(try screen.picture(of: "\(Self.newest)") == before) // So the change below can only be the name.
        
        let bodies = await screen.bodiesRun { screen.chat.members.send([Self.member]) }
        
        #expect(try screen.picture(of: "\(Self.newest)") != before)
        #expect(bodies.all.isEmpty)
    }
    
    private func relayedNote(_ index: Int) throws -> SpiralNoticeRoomTimelineItem {
        let data = #"{"com.spiral.notice":{"kind":"relayed_to_owner","note":"Late.","from_user_id":"\#(Self.member.userID)","room_id":"!dm:spiral.test"}}"#
        return try SpiralNoticeRoomTimelineItem(id: .event(uniqueID: .init("\(index)"), eventOrTransactionID: .eventID("$\(index)")),
                                                timestamp: Date(timeIntervalSince1970: 1000 + Double(index)),
                                                sender: .init(id: Self.them),
                                                notice: #require(SpiralNotice(msgtype: SpiralNotice.msgtype, data: data)))
    }
    
    private func activeCall(_ index: Int) -> CallNotificationRoomTimelineItem {
        CallNotificationRoomTimelineItem(id: .event(uniqueID: .init("\(index)"), eventOrTransactionID: .eventID("$\(index)")),
                                         timestamp: Date(timeIntervalSince1970: 1000 + Double(index)),
                                         sender: .init(id: Self.them),
                                         isDM: false,
                                         isVoiceCall: true,
                                         callState: .active(activeMembers: [Self.member.userID], isJoined: true, callStartTimestamp: nil))
    }
    
    private func stateRow(_ index: Int, body: String) -> StateRoomTimelineItem {
        StateRoomTimelineItem(id: .event(uniqueID: .init("\(index)"), eventOrTransactionID: .eventID("$\(index)")),
                              body: body,
                              timestamp: Date(timeIntervalSince1970: 1000 + Double(index)),
                              isOutgoing: false,
                              isEditable: false,
                              canBeRepliedTo: false,
                              sender: .init(id: Self.them))
    }
    
    private func event(_ index: Int, isOwn: Bool, readBy readers: [String]) -> TimelineReadProgress.Event {
        .init(uniqueID: .init("\(index)"), isOwn: isOwn, isOnServer: true, receipts: readers.map { .init(userID: $0, formattedTimestamp: nil) })
    }
    
    private func context(of index: Int, in chat: TimelineTestChat) -> TimelineRowContext {
        chat.viewModel.state.timelineState.itemsDictionary[.init("\(index)")]?.rowContext ?? .init()
    }
}

/// The rows that published a change.
@MainActor
private final class RowChanges {
    private(set) var rows = Set<String>()
    private var cancellables = Set<AnyCancellable>()
    
    init(_ chat: TimelineTestChat) {
        for (uniqueID, viewState) in chat.viewModel.state.timelineState.itemsDictionary {
            viewState.objectWillChange
                .sink { [weak self] _ in self?.rows.insert(uniqueID.value) }
                .store(in: &cancellables)
        }
    }
}
