//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): where "New" may draw, row by row. `TimelineNewDividerTests` has the chat around it.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
final class TimelineSeenRowsTests {
    private static let me = "@me:spiral.test"
    private static let them = "@alice:spiral.test"
    private static let cameBackAt = Date(timeIntervalSince1970: 1000)
    private static let marker = ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init("marker")))
    
    private static let watching = TimelineSeenRows.Moment(isWatching: true, cameBackAt: cameBackAt, isNewShowing: false)
    private static let scrolledUp = TimelineSeenRows.Moment(isWatching: false, cameBackAt: cameBackAt, isNewShowing: false)
    
    private var seenRows = TimelineSeenRows(ownUserID: me)
    
    @Test
    func aFirstLoadAddsNothing() {
        let arrivals = seenRows.noteArrivals(in: [row("1"), Self.marker, row("2")], isSwitchingTimelines: false, moment: Self.watching)
        
        #expect(arrivals == .init())
        #expect(ids(seenRows.placingReadMarker(in: [row("1"), Self.marker, row("2")])) == ["1", "marker", "2"])
    }
    
    @Test
    func aSwitchOfTimelineAddsNothing() {
        load([row("1")])
        
        let arrivals = seenRows.noteArrivals(in: [row("1"), row("2")], isSwitchingTimelines: true, moment: Self.watching)
        
        #expect(arrivals == .init())
    }
    
    @Test
    func aRowWatchedArrivingGetsNoMarker() {
        load([row("1")])
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2")]
        let arrivals = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.watching)
        
        #expect(arrivals == .init(hasRowFromOthers: true))
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "2"])
    }
    
    @Test
    func aRowWhileScrolledUpKeepsTheMarker() {
        load([row("1")])
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2")]
        let arrivals = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(arrivals == .init(hasRowFromOthers: true))
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "marker", "2"])
    }
    
    @Test
    func aRowSentBeforeYouCameBackIsNotWatchedHoweverLateItArrives() {
        load([row("1")])
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2", at: Self.cameBackAt - 1)]
        _ = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.watching)
        
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "marker", "2"])
    }
    
    @Test
    func aRowBehindAnUnseenOneInTheSameBuildIsNotWatched() {
        load([row("1")])
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2", at: Self.cameBackAt - 1), row("3")]
        _ = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.watching)
        
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "marker", "2", "3"])
    }
    
    @Test
    func aMarkerShowingStaysThroughAWatchedRow() {
        load([row("1"), Self.marker, row("2")])
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2"), row("3")]
        let moment = TimelineSeenRows.Moment(isWatching: true, cameBackAt: Self.cameBackAt, isNewShowing: true)
        _ = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: moment)
        
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "marker", "2", "3"])
    }
    
    // The operator, 2026-11-12: "New" stands for the whole visit, through what you write.
    @Test(arguments: [true, false])
    func yourOwnRowLeavesAMarkerStandingWhereItIs(isWatching: Bool) {
        load([row("1"), Self.marker, row("2")])
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2"), row("3", from: Self.me)]
        let moment = TimelineSeenRows.Moment(isWatching: isWatching, cameBackAt: Self.cameBackAt, isNewShowing: true)
        let arrivals = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: moment)
        
        #expect(arrivals == .init(hasOwnRow: true))
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "marker", "2", "3"])
    }
    
    @Test
    func aReplyWatchedArrivingAfterYouWroteUnderAMarkerLeavesItWhereItIs() {
        load([row("1"), Self.marker, row("2")])
        let showing = TimelineSeenRows.Moment(isWatching: true, cameBackAt: Self.cameBackAt, isNewShowing: true)
        _ = seenRows.noteArrivals(in: [row("1"), Self.marker, row("2"), row("3", from: Self.me)], isSwitchingTimelines: false, moment: showing)
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2"), row("3", from: Self.me), row("4")]
        _ = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: showing)
        
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "marker", "2", "3", "4"])
    }
    
    @Test
    func aRowYouWroteUnderAMarkerIsReadAsFarAsFullyReadGoes() {
        load([row("1"), Self.marker, row("2")])
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2"), row("3", from: Self.me)]
        let moment = TimelineSeenRows.Moment(isWatching: false, cameBackAt: Self.cameBackAt, isNewShowing: true)
        _ = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: moment)
        
        #expect(seenRows.newestSeenRow?.eventID == "$3")
        #expect(seenRows.fullyReadTarget(from: "$1", sentAt: nil) == "$3")
    }
    
    @Test
    func yourOwnRowBehindAnUnseenOneInTheSameBuildLeavesItsMarker() {
        load([row("1")])
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2"), row("3", from: Self.me)]
        let arrivals = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(arrivals == .init(hasOwnRow: true, hasRowFromOthers: true))
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "marker", "2", "3"])
    }
    
    @Test
    func aMarkerTheSDKStillHoldsAboveTheSeenRowComesDownToTheNextUnseenOne() {
        load([row("1")])
        _ = seenRows.noteArrivals(in: [row("1"), Self.marker, row("2")], isSwitchingTimelines: false, moment: Self.watching)
        
        // `m.fully_read` hasn't moved, or failed to, so the SDK leaves its marker where it was.
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2"), row("3", from: Self.me), row("4")]
        _ = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "2", "3", "marker", "4"])
    }
    
    @Test
    func aMarkerBelowTheSeenRowIsTheSDKsToMove() {
        load([row("1")])
        _ = seenRows.noteArrivals(in: [row("1"), Self.marker, row("2")], isSwitchingTimelines: false, moment: Self.watching)
        
        // `m.fully_read` lands on 2 with 3 already in: the SDK moves the same marker down, while you're scrolled up.
        let items: [RoomTimelineItemProtocol] = [row("1"), row("2"), Self.marker, row("3")]
        _ = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "2", "marker", "3"])
    }
    
    @Test
    func aMarkerBroughtInByBackPaginationAfterYouWroteStaysAway() {
        load([row("3")])
        _ = seenRows.noteArrivals(in: [row("3"), row("4", from: Self.me)], isSwitchingTimelines: false, moment: Self.watching)
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2"), row("3"), row("4", from: Self.me)]
        let arrivals = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(arrivals == .init())
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "2", "3", "4"])
    }
    
    @Test
    func aMarkerBroughtInByBackPaginationStays() {
        load([row("3")])
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2"), row("3")]
        let arrivals = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(arrivals == .init())
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "marker", "2", "3"])
    }
    
    @Test
    func aRowRemovedAddsNothing() {
        load([row("1"), row("2")])
        
        let arrivals = seenRows.noteArrivals(in: [row("1")], isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(arrivals == .init())
    }
    
    @Test
    func rowsAllUnderNewIDsAreAReplacedTimeline() {
        load([row("1"), row("2")])
        
        let arrivals = seenRows.noteArrivals(in: [row("30"), row("31", from: Self.me)], isSwitchingTimelines: false, moment: Self.watching)
        
        #expect(arrivals == .init(hasRowFromOthers: true, isTimelineReplaced: true))
    }
    
    @Test
    func aClearLandingApartFromItsRefillIsAReplacedTimeline() {
        load([row("1")])
        _ = seenRows.noteArrivals(in: [], isSwitchingTimelines: false, moment: Self.watching)
        
        let arrivals = seenRows.noteArrivals(in: [row("30")], isSwitchingTimelines: false, moment: Self.watching)
        
        #expect(arrivals.isTimelineReplaced)
    }
    
    @Test
    func aLocalEchoSurvivingAClearStillLeavesAReplacedTimeline() {
        let echo = localEcho("2")
        load([row("1"), echo])
        
        let arrivals = seenRows.noteArrivals(in: [row("30"), echo], isSwitchingTimelines: false, moment: Self.watching)
        
        #expect(arrivals.isTimelineReplaced)
    }
    
    @Test
    func aSwitchBackOntoRowsAllUnderNewIDsIsAReplacedTimeline() {
        load([row("1")])
        
        // Jumped to a detached timeline, and a limited sync came meanwhile. Landing at the end gives no dot.
        let arrivals = seenRows.noteArrivals(in: [row("30")], isSwitchingTimelines: true, moment: Self.watching)
        
        #expect(arrivals == .init(isTimelineReplaced: true))
    }
    
    @Test
    func aSwitchBackOntoTheSameRowsIsNoReplacement() {
        load([row("1")])
        
        let arrivals = seenRows.noteArrivals(in: [row("1"), row("2")], isSwitchingTimelines: true, moment: Self.watching)
        
        #expect(!arrivals.isTimelineReplaced)
    }
    
    @Test
    func aFirstLoadAfterNothingIsNoReplacement() {
        load([])
        
        let arrivals = seenRows.noteArrivals(in: [row("1")], isSwitchingTimelines: false, moment: Self.watching)
        
        #expect(!arrivals.isTimelineReplaced)
    }
    
    @Test
    func aRowFoldedIntoAnExistingGroupCounts() {
        let group = CollapsibleTimelineItem(items: [stateRow("1")])
        load([group])
        
        let grown = CollapsibleTimelineItem(items: [stateRow("1"), stateRow("2")])
        let arrivals = seenRows.noteArrivals(in: [grown], isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(arrivals == .init(hasRowFromOthers: true))
    }
    
    @Test
    func anAgentsEchoOfYourToolChangeIsNoRowFromSomeoneElseAndNoWriting() {
        load([row("1"), Self.marker, row("2")])
        
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2"), stateRow("3", isAgentToolChangeByYou: true)]
        let arrivals = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(arrivals == .init())
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "marker", "2", "3"])
    }
    
    @Test
    func aNoticeOrACallIsARowToo() throws {
        load([row("1")])
        
        let items: [RoomTimelineItemProtocol] = try [row("1"), noticeRow("2")]
        let arrivals = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.scrolledUp)
        #expect(arrivals == .init(hasRowFromOthers: true))
        
        let moreItems = items + [callRow("3", from: Self.me)]
        #expect(seenRows.noteArrivals(in: moreItems, isSwitchingTimelines: false, moment: Self.scrolledUp) == .init(hasOwnRow: true))
    }
    
    // MARK: - The newest row you've seen
    
    @Test
    func theNewestSeenRowSkipsALocalEcho() {
        let echo = localEcho("2")
        load([row("1"), echo])
        
        seenRows.noteOnScreen(echo.id)
        
        #expect(seenRows.newestSeenRow?.eventID == "$1")
    }
    
    @Test
    func noRowOnScreenIsNoSeenRow() {
        load([row("1")])
        
        #expect(seenRows.newestSeenRow == nil)
    }
    
    @Test
    func aRowOnScreenIsSeenWithoutMovingNew() {
        let items: [RoomTimelineItemProtocol] = [row("1"), Self.marker, row("2"), row("3")]
        load(items)
        
        seenRows.noteOnScreen(row("3").id)
        
        #expect(seenRows.newestSeenRow?.eventID == "$3")
        #expect(ids(seenRows.placingReadMarker(in: items)) == ["1", "marker", "2", "3"])
    }
    
    @Test
    func anOlderRowOnScreenTakesNothingBack() {
        load([row("1"), row("2"), row("3")])
        
        seenRows.noteOnScreen(row("3").id)
        seenRows.noteOnScreen(row("1").id)
        
        #expect(seenRows.newestSeenRow?.eventID == "$3")
    }
    
    @Test
    func anythingButARowOnScreenAddsNothing() {
        load([row("1")])
        
        seenRows.noteOnScreen(Self.marker.id)
        
        #expect(seenRows.newestSeenRow == nil)
    }
    
    @Test
    func aRowYouWroteIsSeenPastTheScreen() {
        load([row("1"), row("2")])
        seenRows.noteOnScreen(row("1").id)
        
        _ = seenRows.noteArrivals(in: [row("1"), row("2"), row("3", from: Self.me)], isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(seenRows.newestSeenRow?.eventID == "$3")
    }
    
    @Test
    func aReplacedTimelineTakesTheSeenRowsWithIt() {
        load([row("1")])
        seenRows.noteOnScreen(row("1").id)
        
        _ = seenRows.noteArrivals(in: [row("30")], isSwitchingTimelines: false, moment: Self.watching)
        
        #expect(seenRows.newestSeenRow == nil)
    }
    
    @Test
    func aRowFoldedIntoAGroupCountsOnScreen() {
        let fold = CollapsibleTimelineItem(items: [stateRow("2"), stateRow("3")])
        load([row("1"), fold])
        
        seenRows.noteOnScreen(stateRow("3").id)
        
        #expect(seenRows.newestSeenRow?.eventID == "$3")
    }
    
    @Test
    func theNewestRowIsTheNewestTheServerHas() {
        let echo = localEcho("3")
        load([row("1"), row("2"), echo])
        
        #expect(seenRows.isNewestRow(row("2").id))
        #expect(!seenRows.isNewestRow(row("1").id))
        #expect(!seenRows.isNewestRow(echo.id))
    }
    
    // MARK: - How far `m.fully_read` goes
    
    @Test
    func fullyReadGoesToTheSeenRowPastIt() {
        load([row("1"), row("2")])
        seenRows.noteOnScreen(row("2").id)
        
        #expect(seenRows.fullyReadTarget(from: "$1", sentAt: nil) == "$2")
    }
    
    @Test(arguments: ["$2", "$3"])
    func fullyReadStaysOnOrAheadOfTheSeenRow(fullyRead: String) {
        load([row("1"), row("2"), row("3")])
        seenRows.noteOnScreen(row("2").id)
        
        #expect(seenRows.fullyReadTarget(from: fullyRead, sentAt: nil) == nil)
    }
    
    @Test
    func noFullyReadYetIsNoLocalEcho() {
        let echo = localEcho("2")
        load([row("1"), echo])
        seenRows.noteOnScreen(row("1").id)
        
        // A local echo has no event either, and isn't where `m.fully_read` stands.
        #expect(seenRows.fullyReadTarget(from: nil, sentAt: nil) == "$1")
    }
    
    @Test
    func anEventWithNoRowIsPlacedByItsTime() {
        load([row("1", at: Self.cameBackAt), row("2", at: Self.cameBackAt + 20)])
        seenRows.noteOnScreen(row("1").id)
        #expect(seenRows.fullyReadTarget(from: "$reaction", sentAt: Self.cameBackAt + 10) == nil)
        
        seenRows.noteOnScreen(row("2").id)
        #expect(seenRows.fullyReadTarget(from: "$reaction", sentAt: Self.cameBackAt + 10) == "$2")
    }
    
    @Test
    func anEventsTimeSaysWhetherItsAmongTheRows() {
        load([localEcho("0"), row("1", at: Self.cameBackAt + 10)])
        
        #expect(seenRows.isEventAmongRows(sentAt: Self.cameBackAt + 10, hasReachedStart: false))
        #expect(!seenRows.isEventAmongRows(sentAt: Self.cameBackAt, hasReachedStart: false))
        #expect(seenRows.isEventAmongRows(sentAt: Self.cameBackAt, hasReachedStart: true))
    }
    
    @Test
    func noRowsSayNothingOfAnEvent() {
        #expect(!seenRows.isEventAmongRows(sentAt: Self.cameBackAt, hasReachedStart: true))
    }
    
    // MARK: - "New" after an event with no row
    
    @Test
    func newStandsAboveTheFirstRowFromSomeoneElseAfterTheEvent() {
        let items: [RoomTimelineItemProtocol] = [row("1", at: Self.cameBackAt),
                                                 row("2", from: Self.me, at: Self.cameBackAt + 20),
                                                 row("3", at: Self.cameBackAt + 30)]
        load(items)
        
        #expect(ids(seenRows.placingReadMarker(in: items, afterRowLessEventSentAt: Self.cameBackAt + 10)) == ["1", "2", "marker", "3"])
    }
    
    @Test
    func nothingFromOthersAfterTheEventGetsNoNew() {
        let items: [RoomTimelineItemProtocol] = [row("1", at: Self.cameBackAt), row("2", from: Self.me, at: Self.cameBackAt + 20)]
        load(items)
        
        #expect(ids(seenRows.placingReadMarker(in: items, afterRowLessEventSentAt: Self.cameBackAt + 10)) == ["1", "2"])
    }
    
    @Test
    func theSDKsMarkerIsNotDoubled() {
        let items: [RoomTimelineItemProtocol] = [row("1", at: Self.cameBackAt), Self.marker, row("2", at: Self.cameBackAt + 20)]
        load(items)
        
        #expect(ids(seenRows.placingReadMarker(in: items, afterRowLessEventSentAt: Self.cameBackAt + 10)) == ["1", "marker", "2"])
    }
    
    // MARK: - Rows reaching the end unseen
    
    @Test
    func aRowArrivingWithNobodyLookingIsMissedAtTheEnd() {
        load([row("1")])
        let away = TimelineSeenRows.Moment(isAtEnd: true, isWatching: false, cameBackAt: Self.cameBackAt, isNewShowing: false)
        
        let arrivals = seenRows.noteArrivals(in: [row("1"), row("2"), row("3")], isSwitchingTimelines: false, moment: away)
        
        #expect(arrivals.firstRowMissedAtEnd == .init("2"))
    }
    
    @Test
    func aRowSentWhileAwayIsMissedAtTheEndHoweverLateItLands() {
        load([row("1")])
        let back = TimelineSeenRows.Moment(isAtEnd: true, isWatching: true, cameBackAt: Self.cameBackAt, isNewShowing: false)
        
        let arrivals = seenRows.noteArrivals(in: [row("1"), row("2", at: Self.cameBackAt - 1)], isSwitchingTimelines: false, moment: back)
        
        #expect(arrivals.firstRowMissedAtEnd == .init("2"))
    }
    
    @Test
    func aRowWatchedArrivingIsNotMissed() {
        load([row("1")])
        let watching = TimelineSeenRows.Moment(isAtEnd: true, isWatching: true, cameBackAt: Self.cameBackAt, isNewShowing: true)
        
        let arrivals = seenRows.noteArrivals(in: [row("1"), row("2")], isSwitchingTimelines: false, moment: watching)
        
        #expect(arrivals.firstRowMissedAtEnd == nil)
    }
    
    @Test
    func aRowArrivingScrolledUpIsNotMissedAtTheEnd() {
        load([row("1")])
        
        let arrivals = seenRows.noteArrivals(in: [row("1"), row("2")], isSwitchingTimelines: false, moment: Self.scrolledUp)
        
        #expect(arrivals.firstRowMissedAtEnd == nil)
    }
    
    // MARK: - Helpers
    
    private func load(_ items: [RoomTimelineItemProtocol]) {
        _ = seenRows.noteArrivals(in: items, isSwitchingTimelines: false, moment: Self.scrolledUp)
    }
    
    private func ids(_ items: [RoomTimelineItemProtocol]) -> [String] {
        items.map { $0 is ReadMarkerRoomTimelineItem ? "marker" : $0.id.uniqueID.value }
    }
    
    private func row(_ id: String, from sender: String = them, at timestamp: Date = cameBackAt + 1) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)")),
                             timestamp: timestamp,
                             isOutgoing: sender == Self.me,
                             isEditable: false,
                             canBeRepliedTo: true,
                             sender: .init(id: sender),
                             content: .init(body: "Hello"))
    }
    
    private func localEcho(_ id: String) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: .event(uniqueID: .init(id), eventOrTransactionID: .transactionID("transaction")),
                             timestamp: .now,
                             isOutgoing: true,
                             isEditable: false,
                             canBeRepliedTo: true,
                             sender: .init(id: Self.me),
                             content: .init(body: "Hello"))
    }
    
    private func stateRow(_ id: String, isAgentToolChangeByYou: Bool = false) -> StateRoomTimelineItem {
        StateRoomTimelineItem(id: .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)")),
                              body: "Alice joined",
                              timestamp: Self.cameBackAt + 1,
                              isOutgoing: false,
                              isEditable: false,
                              canBeRepliedTo: false,
                              sender: .init(id: Self.them),
                              isAgentToolChangeByYou: isAgentToolChangeByYou)
    }
    
    private func noticeRow(_ id: String) throws -> SpiralNoticeRoomTimelineItem {
        let notice = try #require(SpiralNotice(msgtype: SpiralNotice.msgtype, data: #"{"com.spiral.notice":{"kind":"reply_failed"}}"#))
        return SpiralNoticeRoomTimelineItem(id: .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)")),
                                            timestamp: Self.cameBackAt + 1,
                                            sender: .init(id: Self.them),
                                            notice: notice)
    }
    
    private func callRow(_ id: String, from sender: String) -> CallInviteRoomTimelineItem {
        CallInviteRoomTimelineItem(id: .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)")),
                                   timestamp: Self.cameBackAt + 1,
                                   isEditable: false,
                                   canBeRepliedTo: false,
                                   sender: .init(id: sender))
    }
}
