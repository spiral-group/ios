//
// Copyright 2026 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import OrderedCollections
@testable import Spiral
import Testing

@MainActor
struct TimelineStateTests {
    // MARK: - Read marker
    
    @Test("Read marker unique ID is captured when present in the timeline")
    func readMarkerUniqueIDPresent() {
        var state = TimelineState()
        state.itemsDictionary[.init("msg1")] = makeTextViewState(uniqueID: "msg1")
        state.itemsDictionary[.init("read-marker")] = makeReadMarkerViewState(uniqueID: "read-marker")
        state.itemsDictionary[.init("msg2")] = makeTextViewState(uniqueID: "msg2")
        state.recomputeReadMarkerUniqueID()
        
        #expect(state.readMarkerUniqueID == .init("read-marker"))
    }
    
    @Test("Read marker unique ID is nil when no marker exists")
    func readMarkerUniqueIDAbsent() {
        var state = TimelineState()
        state.itemsDictionary[.init("msg1")] = makeTextViewState(uniqueID: "msg1")
        state.itemsDictionary[.init("msg2")] = makeTextViewState(uniqueID: "msg2")
        state.recomputeReadMarkerUniqueID()
        
        #expect(state.readMarkerUniqueID == nil)
    }
    
    @Test("A row folded into a group counts as loaded")
    func foldedRowIsLoaded() {
        var state = TimelineState()
        // Not the first row: the group goes by that one's ID.
        let group = CollapsibleTimelineItem(items: [makeStateItem(eventID: "$first"), makeStateItem(eventID: "$folded")])
        state.itemsDictionary[.init("group")] = RoomTimelineItemViewState(type: .group(group), groupStyle: .single)
        state.fullyReadEventID = "$folded"
        
        #expect(!state.isReadMarkerAboveLoadedRows)
        
        state.fullyReadEventID = "$older"
        #expect(state.isReadMarkerAboveLoadedRows)
    }
    
    // MARK: - Helpers
    
    private func makeStateItem(eventID: String) -> StateRoomTimelineItem {
        StateRoomTimelineItem(id: .event(uniqueID: .init(eventID), eventOrTransactionID: .eventID(eventID)),
                              body: "Alice joined",
                              timestamp: .mock,
                              isOutgoing: false,
                              isEditable: false,
                              canBeRepliedTo: false,
                              sender: .init(id: "@sender:example.com"))
    }
    
    private func makeTextViewState(uniqueID: String) -> RoomTimelineItemViewState {
        let item = TextRoomTimelineItem(id: .virtual(uniqueID: .init(uniqueID)),
                                        timestamp: .mock,
                                        isOutgoing: false,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: .init(id: "@sender:example.com"),
                                        content: .init(body: "Test message"))
        return RoomTimelineItemViewState(type: .text(item), groupStyle: .single)
    }
    
    private func makeReadMarkerViewState(uniqueID: String) -> RoomTimelineItemViewState {
        let item = ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init(uniqueID)))
        return RoomTimelineItemViewState(type: .readMarker(item), groupStyle: .single)
    }
}
