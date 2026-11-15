//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A feed post shared through the
// forwarding screen (arch § 5.10): for each chat the person picked, the
// server builds the message (`POST /feed/posts/{id}/share`) and the app
// sends it as it is. Bridged chats are left out of the picker, and the
// server refuses them as well (D-P12).
//

import Foundation
import MatrixRustSDK

final class FeedShareForwardingSource: MessageForwardingSource {
    let postID: String
    let feedService: FeedServiceProtocol
    /// The app's language, for the line before the link.
    let language: String?
    /// Chats the last send could not share to, for the toast that ends it.
    private(set) var failedRoomCount = 0

    init(postID: String, feedService: FeedServiceProtocol, language: String? = Bundle.main.preferredLocalizations.first) {
        self.postID = postID
        self.feedService = feedService
        self.language = language
    }

    var title: String {
        UntranslatedL10n.screenFeedShareTitle
    }

    /// A chat with a bridge's puppet or bot among the members its summary
    /// names. The server checks every member, so one this misses is still refused.
    func excludes(_ room: RoomSummary) -> Bool {
        room.isSpace || room.heroes.contains { SpiralBridgeUsers.isBridgeUser($0.id) }
    }

    func contents(for roomID: String) async -> Result<[RoomMessageEventContentWithoutRelation], MessageForwardingSourceError> {
        switch await feedService.share(postID: postID, roomID: roomID, language: language) {
        case .success(let share):
            do {
                // Text only, as the server built it: no formatted body (decision 96 for a newer `msgtype`).
                return try .success([messageEventContentNew(msgtype: .text(content: TextMessageContent(body: share.body, formatted: nil)))])
            } catch {
                MXLog.error("Failed to build the share of feed post \(postID): \(error)")
                return .failure(.init(message: UntranslatedL10n.screenFeedShareFailed))
            }
        case .failure(let error):
            MXLog.error("Failed to share feed post \(postID): \(error)")
            return .failure(.init(message: Self.message(for: error)))
        }
    }

    /// The flow says how many chats it reached, failures included.
    func sentMessage(roomCount: Int) -> String? {
        nil
    }

    func didFinish(sentRoomIDs: [String], failedRoomIDs: [String]) {
        failedRoomCount = failedRoomIDs.count
    }

    /// A share swiped away mid-send reaches no further chat, and only the chats already shared to are reported.
    var stopsWhenDismissed: Bool {
        true
    }

    /// "Shared to 2 chats", or both counts when some could not be.
    static func sharedMessage(sent: Int, failed: Int) -> String {
        failed > 0 ? UntranslatedL10n.screenFeedSharedPartly(sent, failed) : UntranslatedL10n.screenFeedShared(sent)
    }

    static func message(for error: FeedError) -> String {
        switch error {
        case .shareBridgedRoom: UntranslatedL10n.screenFeedShareBridgedRoom
        case .notFound: UntranslatedL10n.screenFeedPostNotAvailableTitle
        default: UntranslatedL10n.screenFeedShareFailed
        }
    }
}
