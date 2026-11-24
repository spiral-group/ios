//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, § 5.73): the NSE reads «your move» off the
// action's own JSON.
//

import Foundation
@testable import Spiral
import Testing
import UserNotifications

struct SpiralActionNotificationTests {
    private static func raw(type: String = SpiralActionNotification.eventType,
                            mentions: [String]? = ["@bob:spiral.md"],
                            line: Any? = "emm2 placed O",
                            kind: String? = nil,
                            relatesTo: [String: Any]? = ["rel_type": "m.reference", "event_id": "$post"]) -> String {
        var content: [String: Any] = ["seq": 3, "op": ["set": ["path": "cells", "value": []]]]
        if let relatesTo { content["m.relates_to"] = relatesTo }
        if let mentions { content["m.mentions"] = ["user_ids": mentions] }
        var summary: [String: Any] = ["notify": "ping"]
        if let line { summary["line"] = line }
        if let kind { summary["notify_kind"] = kind }
        content["summary"] = summary
        let event: [String: Any] = ["type": type, "sender": "@emm2:spiral.md", "event_id": "$move", "content": content]
        let data = (try? JSONSerialization.data(withJSONObject: event)) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    @Test
    func aMoveNamingTheReaderIsTheirMove() throws {
        let action = try #require(SpiralActionNotification(rawEvent: Self.raw(), receiverID: "@bob:spiral.md"))
        #expect(action.body(language: "en") == "\(UntranslatedL10n.notificationInteractivePostYourMove) · emm2 placed O")
    }

    @Test
    func aMoveNamingSomeoneElseOrAnotherEventIsNot() {
        #expect(SpiralActionNotification(rawEvent: Self.raw(), receiverID: "@carol:spiral.md") == nil)
        #expect(SpiralActionNotification(rawEvent: Self.raw(mentions: nil), receiverID: "@bob:spiral.md") == nil)
        #expect(SpiralActionNotification(rawEvent: Self.raw(type: "m.room.message"), receiverID: "@bob:spiral.md") == nil)
        #expect(SpiralActionNotification(rawEvent: "not json", receiverID: "@bob:spiral.md") == nil)
    }

    /// The app says why it pinged; the push says it first (§ 5.74). No kind
    /// is a game from before kinds, and meant «your move».
    @Test
    func theKindSaysWhyThePushCame() throws {
        let body = { (kind: String?, line: Any?) throws -> String in
            try #require(SpiralActionNotification(rawEvent: Self.raw(line: line, kind: kind), receiverID: "@bob:spiral.md")).body(language: "en")
        }
        #expect(try body(nil, "x") == "\(UntranslatedL10n.notificationInteractivePostYourMove) · x")
        #expect(try body("record", "emm2 · 42") == "\(UntranslatedL10n.notificationInteractivePostRecord) · emm2 · 42")
        #expect(try body("challenge", nil) == UntranslatedL10n.notificationInteractivePostChallenge)
        #expect(try body("result", "X wins") == "\(UntranslatedL10n.notificationInteractivePostResult) · X wins")
        #expect(try body("mention", "Alice gave you «milk»") == "Alice gave you «milk»", "a plain mention is its line")
        #expect(try body("mention", nil) == UntranslatedL10n.notificationInteractivePostMention)
        #expect(try body("an-unknown-kind", "x") == "\(UntranslatedL10n.notificationInteractivePostYourMove) · x")
    }

    /// A line written per language is read in the reader's (§ 5.68).
    @Test
    func aLinePerLanguageIsReadInTheReaders() throws {
        let action = try #require(SpiralActionNotification(rawEvent: Self.raw(line: ["uk": "emm2 поставив O", "en": "emm2 placed O"]),
                                                           receiverID: "@bob:spiral.md"))
        #expect(action.line(in: "uk") == "emm2 поставив O")
        #expect(action.line(in: "de") == "emm2 placed O", "English when the reader's is not there")
    }

    /// L1: any member's line reaches the push, so it is a line, not a page.
    @Test
    func aLongLineIsCutForThePush() throws {
        let long = String(repeating: "я", count: 5000)
        let plain = try #require(SpiralActionNotification(rawEvent: Self.raw(line: long), receiverID: "@bob:spiral.md"))
        let byLanguage = try #require(SpiralActionNotification(rawEvent: Self.raw(line: ["uk": long]), receiverID: "@bob:spiral.md"))

        for line in [plain.line(in: "en"), byLanguage.line(in: "uk")] {
            #expect(line?.unicodeScalars.count == SpiralAppActionLimits.maxSummaryLineScalars)
            #expect(line?.hasSuffix("…") == true)
        }
    }

    @Test
    func aMoveWithoutALineIsStillYourMove() throws {
        let action = try #require(SpiralActionNotification(rawEvent: Self.raw(line: nil), receiverID: "@bob:spiral.md"))
        #expect(action.body(language: "en") == UntranslatedL10n.notificationInteractivePostYourMove)
    }

    /// A move names its post by `m.reference`; that is where a tap goes (§ 5.82).
    @Test
    func aMoveNamesThePostItWasMadeIn() throws {
        let action = { (relatesTo: [String: Any]?) throws -> SpiralActionNotification in
            try #require(SpiralActionNotification(rawEvent: Self.raw(relatesTo: relatesTo), receiverID: "@bob:spiral.md"))
        }
        #expect(try action(["rel_type": "m.reference", "event_id": "$post"]).postEventID == "$post")
        #expect(try action(nil).postEventID == nil, "a move that names no post is still a ping, and opens the room")
        #expect(try action(["rel_type": "m.thread", "event_id": "$root"]).postEventID == nil, "only a reference is the post")
    }

    /// A tap on a game's ping opens the room on its post — the road a link to a
    /// message takes; any other notification keeps its own road.
    @Test
    func aTapOnAPingOpensTheRoomOnItsPost() {
        let ping = UNMutableNotificationContent()
        ping.roomID = "!room:spiral.md"
        ping.receiverID = "@bob:spiral.md"
        ping.eventID = "$move"
        ping.spiralPostEventID = "$post"
        #expect(ping.spiralPostRoute == .event(eventID: "$post", roomID: "!room:spiral.md", via: []))

        let message = UNMutableNotificationContent()
        message.roomID = "!room:spiral.md"
        message.receiverID = "@bob:spiral.md"
        message.eventID = "$message"
        #expect(message.spiralPostRoute == nil)
    }

    /// The receipt that clears the mention: reading the newest item of the
    /// live timeline reads to the end, past a hidden move (§ 5.73).
    @Test
    func readingTheNewestLiveItemReadsTheRoomToTheEnd() {
        let items: [RoomTimelineItemProtocol] = [Self.text("t1"), Self.text("t2"), SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("v3")), timestamp: .mock)]
        #expect(TimelineController.readsToTheEnd(items[1].id, in: items, kind: .live))
        #expect(!TimelineController.readsToTheEnd(items[0].id, in: items, kind: .live), "an older item reads only to itself")
        #expect(!TimelineController.readsToTheEnd(items[1].id, in: items, kind: .detached), "a timeline focused on the past is not the end")
        #expect(!TimelineController.readsToTheEnd(items[1].id, in: items, kind: .thread(rootEventID: "t1")))
    }

    private static func text(_ eventID: String) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: .event(uniqueID: .init(UUID().uuidString), eventOrTransactionID: .eventID(eventID)),
                             timestamp: .mock, isOutgoing: false, isEditable: false, canBeRepliedTo: true,
                             sender: .init(id: ""), content: .init(body: "x"))
    }
}
