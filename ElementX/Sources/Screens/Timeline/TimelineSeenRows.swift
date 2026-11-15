//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, questions 359 and 364): what you've seen of the room's live timeline, and so where "New" may
// draw and how far `m.fully_read` may go.
//

import Foundation

/// "New" marks what you hadn't seen when you came back. It's never drawn over something you watched arrive, and it stands
/// for the whole visit, through what you write, until you leave or go to the background (the operator's choices, 2026-11-12,
/// "as in Telegram" and «Так, як вихід»).
///
/// The SDK can't do this alone. It places its marker from `m.fully_read`, which moves only through a sync round trip, and
/// inserts the marker together with the row that needs it. So this goes by the rows: the newest row you watched arrive, or wrote
/// with no "New" standing, is the seen row, and "New" is never drawn above it. A marker the SDK still holds up there comes down to the first unseen row
/// from someone else, so that nothing here waits for `m.fully_read`, or needs it to succeed.
///
/// `m.fully_read` itself goes to the newest row you've seen: one you wrote or watched arrive, or the furthest the screen reached.
/// That last one is kept apart from the seen row, as reading down to a row, or writing under "New", mustn't take it down with you.
struct TimelineSeenRows {
    /// The chat at the moment a build of the timeline lands.
    struct Moment {
        /// At the end of the live timeline, whether or not anyone's looking.
        var isAtEnd = false
        /// At the end of the live timeline, with the app active.
        let isWatching: Bool
        /// When the chat opened or the app last became active. A row older than this was sent while you were away, however
        /// late it reaches the timeline: a suspended app only hears of it from the sync that follows.
        let cameBackAt: Date
        /// Whether a "New" is standing already, as a row arriving then belongs to what it marks.
        let isNewShowing: Bool
    }
    
    struct Arrivals: Equatable {
        var hasOwnRow = false
        var hasRowFromOthers = false
        /// A limited sync cleared the timeline and refilled it with the latest rows, under new IDs. What came between
        /// them was never loaded, and the SDK has forgotten `m.fully_read`, so it draws no marker for them.
        var isTimelineReplaced = false
        /// The first of the rows that reached the end with nobody looking, which the table would run past.
        var firstRowMissedAtEnd: TimelineItemIdentifier.UniqueID?
    }
    
    private let ownUserID: String
    private var rows = [Row]()
    private var knownRowIDs = Set<TimelineItemIdentifier.UniqueID>()
    /// Kept through a build with no remote rows, as a clear can land apart from what refills it. Local echoes survive a clear.
    private var knownRemoteRowIDs = Set<TimelineItemIdentifier.UniqueID>()
    private var seenRowID: TimelineItemIdentifier.UniqueID?
    /// The furthest row you've read without it moving "New": the screen reached it, or you wrote it with "New" standing.
    /// Scrolling back up takes nothing back.
    private var furthestRowOnScreenID: TimelineItemIdentifier.UniqueID?
    
    var hasRows: Bool {
        !rows.isEmpty
    }
    
    func hasRow(eventID: String) -> Bool {
        rows.contains { $0.id.eventID == eventID }
    }
    
    /// Whether this is the newest row the server has.
    func isNewestRow(_ id: TimelineItemIdentifier) -> Bool {
        rows.last { $0.id.eventID != nil }?.id.uniqueID == id.uniqueID
    }
    
    /// The newest row you've seen that the server has, as a local echo has no event yet.
    var newestSeenRow: TimelineItemIdentifier? {
        let seenIDs = [seenRowID, furthestRowOnScreenID]
        guard let newestIndex = rows.lastIndex(where: { seenIDs.contains($0.id.uniqueID) }) else { return nil }
        return rows[...newestIndex].last { $0.id.eventID != nil }?.id
    }
    
    init(ownUserID: String) {
        self.ownUserID = ownUserID
    }
    
    /// Takes a new build of the timeline and returns what it added. A first load or a switch of timeline adds nothing, and an
    /// edit or a reaction changes no row's ID.
    mutating func noteArrivals(in items: [RoomTimelineItemProtocol], isSwitchingTimelines: Bool, moment: Moment) -> Arrivals {
        let rows = items.flatMap(Self.rows)
        let remoteRowIDs = Set(rows.filter { $0.id.eventID != nil }.map(\.id.uniqueID))
        let isTimelineReplaced = !remoteRowIDs.isEmpty && !knownRemoteRowIDs.isEmpty && remoteRowIDs.isDisjoint(with: knownRemoteRowIDs)
        defer {
            self.rows = rows
            knownRowIDs = Set(rows.map(\.id.uniqueID))
            if !remoteRowIDs.isEmpty {
                knownRemoteRowIDs = remoteRowIDs
            }
        }
        
        guard !isSwitchingTimelines else { return Arrivals(isTimelineReplaced: isTimelineReplaced) }
        guard !isTimelineReplaced else {
            return Arrivals(hasRowFromOthers: rows.contains(where: isFromSomeoneElse), isTimelineReplaced: true)
        }
        guard !knownRowIDs.isEmpty else { return Arrivals() }
        
        var arrivals = Arrivals()
        var isNewShowing = moment.isNewShowing
        
        // Back-pagination only adds rows above the first known one.
        for row in rows.drop(while: { !knownRowIDs.contains($0.id.uniqueID) }) where !knownRowIDs.contains(row.id.uniqueID) {
            if row.senderID == ownUserID {
                arrivals.hasOwnRow = true
                // A "New" standing stays where it is, above what was unread when you came in: what you write is read, as far as
                // `m.fully_read` goes on leaving, but doesn't take "New" down with it.
                if isNewShowing {
                    noteRead(row.id.uniqueID, in: rows)
                } else {
                    seenRowID = row.id.uniqueID
                }
            } else if isFromSomeoneElse(row) {
                arrivals.hasRowFromOthers = true
                let isWatched = moment.isWatching && row.timestamp >= moment.cameBackAt
                if isWatched, !isNewShowing {
                    seenRowID = row.id.uniqueID
                } else {
                    isNewShowing = true
                }
                if !isWatched, moment.isAtEnd, arrivals.firstRowMissedAtEnd == nil {
                    arrivals.firstRowMissedAtEnd = row.id.uniqueID
                }
            }
        }
        
        return arrivals
    }
    
    /// A row has come into view. Anything that isn't one of the rows adds nothing.
    mutating func noteOnScreen(_ id: TimelineItemIdentifier) {
        noteRead(id.uniqueID, in: rows)
    }
    
    /// Going to the background ends the visit, as leaving does: all you've read is seen, so a "New" above it goes, and what
    /// arrives next is marked afresh.
    mutating func endVisit() {
        let readIDs = [seenRowID, furthestRowOnScreenID]
        guard let newestIndex = rows.lastIndex(where: { readIDs.contains($0.id.uniqueID) }) else { return }
        seenRowID = rows[newestIndex].id.uniqueID
    }
    
    /// The event `m.fully_read` should move to, if you've seen past where it stands. It never moves backwards.
    /// - Parameters:
    ///   - fullyReadEventID: Where it stands.
    ///   - fullyReadDate: When that event was sent, which places one that has no row.
    func fullyReadTarget(from fullyReadEventID: String?, sentAt fullyReadDate: Date?) -> String? {
        guard let newestSeenRow, let seenIndex = rows.firstIndex(where: { $0.id.uniqueID == newestSeenRow.uniqueID }) else { return nil }
        
        if let fullyReadEventID, let fullyReadIndex = rows.firstIndex(where: { $0.id.eventID == fullyReadEventID }) {
            return seenIndex > fullyReadIndex ? newestSeenRow.eventID : nil
        }
        if let fullyReadDate {
            return rows[seenIndex].timestamp > fullyReadDate ? newestSeenRow.eventID : nil
        }
        return newestSeenRow.eventID
    }
    
    /// Whether an event sent then lies among the loaded rows, or behind them all when they reach the timeline's start.
    /// One that isn't loaded and passes this has no row, so no back-pagination will bring it in.
    func isEventAmongRows(sentAt date: Date, hasReachedStart: Bool) -> Bool {
        guard let oldestRow = rows.first(where: { $0.id.eventID != nil }) else { return false }
        return hasReachedStart || oldestRow.timestamp <= date
    }
    
    /// The items with "New" where it belongs. The SDK has no marker for an event with no row, so one is placed here, by
    /// when that event was sent. A marker is kept below the seen row, and one the SDK has further down is left alone.
    func placingReadMarker(in items: [RoomTimelineItemProtocol], afterRowLessEventSentAt fullyReadDate: Date? = nil) -> [RoomTimelineItemProtocol] {
        var items = items
        if let fullyReadDate, !items.contains(where: { $0 is ReadMarkerRoomTimelineItem }),
           let firstUnreadIndex = items.firstIndex(where: { item in Self.rows(of: item).contains { isFromSomeoneElse($0) && $0.timestamp > fullyReadDate } }) {
            items.insert(ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: Self.rowLessMarkerID)), at: firstUnreadIndex)
        }
        
        guard let seenRowID,
              let markerIndex = items.firstIndex(where: { $0 is ReadMarkerRoomTimelineItem }),
              let seenIndex = items.lastIndex(where: { item in Self.rows(of: item).contains { $0.id.uniqueID == seenRowID } }),
              markerIndex < seenIndex else {
            return items
        }
        
        let marker = items.remove(at: markerIndex)
        
        // The removal moved the seen row up by one, so this is what follows it.
        let firstUnseenIndex = items[seenIndex...].firstIndex { Self.rows(of: $0).contains(where: isFromSomeoneElse) }
        if let firstUnseenIndex {
            items.insert(marker, at: firstUnseenIndex)
        }
        return items
    }
    
    // MARK: - Private
    
    private static let rowLessMarkerID = TimelineItemIdentifier.UniqueID("spiral-row-less-read-marker")
    
    private struct Row {
        let id: TimelineItemIdentifier
        let senderID: String
        let timestamp: Date
        var isAgentToolChangeByYou = false
    }
    
    private mutating func noteRead(_ id: TimelineItemIdentifier.UniqueID, in rows: [Row]) {
        guard let index = rows.firstIndex(where: { $0.id.uniqueID == id }) else { return }
        let furthestIndex = rows.firstIndex { $0.id.uniqueID == furthestRowOnScreenID }
        if furthestIndex.map({ $0 < index }) ?? true {
            furthestRowOnScreenID = id
        }
    }
    
    private func isFromSomeoneElse(_ row: Row) -> Bool {
        row.senderID != ownUserID && !row.isAgentToolChangeByYou
    }
    
    /// Everything drawn for an event, folded or not. Dates and the marker itself aren't anyone's rows.
    private static func rows(of item: RoomTimelineItemProtocol) -> [Row] {
        switch item {
        case let item as CollapsibleTimelineItem:
            item.items.flatMap(rows)
        case let item as StateRoomTimelineItem:
            [Row(id: item.id, senderID: item.sender.id, timestamp: item.timestamp, isAgentToolChangeByYou: item.isAgentToolChangeByYou)]
        case let item as EventBasedTimelineItemProtocol:
            [Row(id: item.id, senderID: item.sender.id, timestamp: item.timestamp)]
        case let item as SpiralNoticeRoomTimelineItem:
            [Row(id: item.id, senderID: item.sender.id, timestamp: item.timestamp)]
        case let item as CallInviteRoomTimelineItem:
            [Row(id: item.id, senderID: item.sender.id, timestamp: item.timestamp)]
        case let item as CallNotificationRoomTimelineItem:
            [Row(id: item.id, senderID: item.sender.id, timestamp: item.timestamp)]
        default:
            []
        }
    }
}
