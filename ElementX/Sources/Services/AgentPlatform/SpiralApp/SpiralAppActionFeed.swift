//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.16): one subscription per room.
//
// The SDK subscribes per ROOM, not per post, so a session that subscribed for
// itself received every action in the room and threw most away. With four posts
// mounted that was four subscriptions, four deliveries of each action, and four
// JSON parses of events belonging to someone else.
//
// `SpiralAppPostSession.start` had already written down that sharing was worth
// doing "when the timeline mounts them". This is that.
//
// The envelope is read once here and each batch goes only to the post it names,
// so adding a fifth post costs a dictionary lookup rather than another parse of
// everything.
//

import Foundation
import MatrixRustSDK

@MainActor
final class SpiralAppActionFeed {
    typealias Listener = ([SpiralObservedEvent]) -> Void

    private let roomProxy: JoinedRoomProxyProtocol
    private var listeners: [String: [UUID: Listener]] = [:]
    private var subscription: TaskHandle?
    /// Whether this feed has taken responsibility for the room's subscription.
    ///
    /// Separate from `subscription` because a subscribe can FAIL and still
    /// count as done: retrying once per arriving listener would turn an SDK
    /// error into a request per post, and the reader's own refresh already
    /// gives a post its state without live updates.
    private var ownsRoomSubscription = false

    init(roomProxy: JoinedRoomProxyProtocol) {
        self.roomProxy = roomProxy
    }

    deinit {
        subscription?.cancel()
    }

    /// Hear about actions on one post.
    ///
    /// The first listener opens the room's subscription and the last one to
    /// leave closes it, so a room nobody is watching costs nothing.
    ///
    /// - Returns: a token to hand back to ``stopListening(_:)``.
    func listen(toPost postEventID: String, with listener: @escaping Listener) async -> Token {
        let token = Token(postEventID: postEventID, id: UUID())
        listeners[postEventID, default: [:]][token.id] = listener

        if !ownsRoomSubscription {
            ownsRoomSubscription = true
            await subscribe()
        }

        return token
    }

    func stopListening(_ token: Token) {
        listeners[token.postEventID]?[token.id] = nil

        if listeners[token.postEventID]?.isEmpty == true {
            listeners[token.postEventID] = nil
        }

        if listeners.isEmpty {
            subscription?.cancel()
            subscription = nil
            ownsRoomSubscription = false
        }
    }

    /// How many posts are being listened to. For tests.
    var listenedPostCount: Int {
        listeners.count
    }

    /// Whether this feed holds the room's subscription. For tests.
    var isSubscribed: Bool {
        ownsRoomSubscription
    }

    struct Token: Hashable {
        let postEventID: String
        let id: UUID
    }

    // MARK: - Private

    private func subscribe() async {
        let listener = SDKListener<[SpiralObservedEvent]>.onMainActor { [weak self] events in
            self?.route(events)
        }

        switch await roomProxy.subscribeToSpiralEvents(types: [SpiralAppAction.eventType],
                                                       listener: listener) {
        case .success(let handle):
            subscription = handle
        case .failure(let error):
            // Not fatal: a post still reads and still writes, it just will not
            // update until something else asks it to.
            MXLog.error("[SpiralApp] no live updates for this room: \(error)")
        }
    }

    private func route(_ events: [SpiralObservedEvent]) {
        var byPost: [String: [SpiralObservedEvent]] = [:]

        for event in events {
            // An event that could not be decrypted still has to reach its post,
            // which counts it as a hole rather than as absent — so it is routed
            // on whatever the envelope says and judged there.
            guard let postEventID = Self.postEventID(ofRawEventJSON: event.eventJson) else { continue }
            byPost[postEventID, default: []].append(event)
        }

        for (postEventID, batch) in byPost {
            guard let handlers = listeners[postEventID] else { continue }
            for handler in handlers.values {
                handler(batch)
            }
        }
    }

    /// Which post an action belongs to, read from the envelope alone.
    ///
    /// Deliberately not a full parse: routing needs one field, and every
    /// listener parses properly anyway. Reading more here would mean two places
    /// that know what an action looks like.
    static func postEventID(ofRawEventJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == SpiralAppAction.eventType,
              let content = root["content"] as? [String: Any],
              let relatesTo = content["m.relates_to"] as? [String: Any],
              relatesTo["rel_type"] as? String == "m.reference" else {
            return nil
        }

        return relatesTo["event_id"] as? String
    }
}
