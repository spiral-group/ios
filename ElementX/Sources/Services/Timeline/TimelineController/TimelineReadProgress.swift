//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 357): who has read how far, for the ticks and for "Seen by".
//

import Foundation

/// How far a timeline has been read.
///
/// A receipt sits on the newest event its owner has read, so everything before it counts as read too. It can sit on an
/// event with no bubble (a call) or no row at all, which is why this is built from every event of the timeline, once
/// per update, and never from the rows.
nonisolated struct TimelineReadProgress: Equatable {
    struct Event {
        let uniqueID: TimelineItemIdentifier.UniqueID
        let isOwn: Bool
        /// Whether the server has it. A local echo has no readers yet, whatever sits after it.
        let isOnServer: Bool
        let receipts: [ReadReceipt]
    }
    
    private var readers = [TimelineItemIdentifier.UniqueID: [ReadReceipt]]()
    /// The own messages the server has, newest first.
    private var ownMessageIDs = [TimelineItemIdentifier.UniqueID]()
    
    init() { }
    
    /// - Parameter events: The timeline's events, oldest first.
    init(events: [Event], ownUserID: String) {
        var readerIDs = Set<String>()
        var eventReaders = [ReadReceipt]()
        
        for event in events.reversed() {
            for receipt in event.receipts where receipt.userID != ownUserID && readerIDs.insert(receipt.userID).inserted {
                eventReaders.append(receipt)
            }
            
            guard event.isOnServer else { continue }
            
            // Copy on write: events with nothing new between them share one array.
            readers[event.uniqueID] = eventReaders
            if event.isOwn {
                ownMessageIDs.append(event.uniqueID)
            }
        }
    }
    
    /// Everyone who has read the event, whoever reached furthest first.
    func readers(of uniqueID: TimelineItemIdentifier.UniqueID) -> [ReadReceipt] {
        readers[uniqueID] ?? []
    }
    
    /// The own messages read by someone `isCounted` accepts.
    func readOwnMessages(countedBy isCounted: (_ userID: String) -> Bool) -> Set<TimelineItemIdentifier.UniqueID> {
        let newestRead = ownMessageIDs.firstIndex { uniqueID in
            readers(of: uniqueID).contains { isCounted($0.userID) }
        }
        guard let newestRead else { return [] }
        return Set(ownMessageIDs[newestRead...])
    }
    
    /// Whether a reader's receipt shows as two ticks. An agent reads everything it's in the room for, so in a chat with
    /// a person its receipt would say the person has read the message. In a DM with the agent itself it's the reader.
    static func isCounted(_ userID: String, ownUserID: String, dmUserID: String?) -> Bool {
        guard SpiralAgentRoomGrants.isLocalAgent(userID, ownUserID: ownUserID) else { return true }
        return userID == dmUserID
    }
}

extension TimelineReadProgress {
    /// Built from rows, for mocks: the real timeline has events with no row.
    init(timelineItems: [RoomTimelineItemProtocol], ownUserID: String) {
        let events = timelineItems.compactMap { $0 as? EventBasedTimelineItemProtocol }.map { item in
            Event(uniqueID: item.id.uniqueID,
                  isOwn: item.isOutgoing,
                  isOnServer: item.properties.deliveryStatus == nil || item.properties.deliveryStatus == .sent,
                  receipts: item.properties.orderedReadReceipts)
        }
        self.init(events: events, ownUserID: ownUserID)
    }
}
