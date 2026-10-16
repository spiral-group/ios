//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.7): one Interactive Post, live.
//
// Binds the two halves that produce a post's state. The relations read is the
// AUTHORITY — it reaches actions no matter how far back the post sits — and
// the event-cache subscription is the FAST PATH, delivering an action the
// moment it lands without a refetch. Both feed the same reader, which
// deduplicates by event id, so it does not matter which arrives first.
//
// Writes go out through `sendRaw` rather than the timeline's send path: the
// timeline is deliberately not allowed to show an action, and routing one
// through it would create a local echo for a row that can never exist.
//

import Combine
import Foundation
import MatrixRustSDK

@MainActor
final class SpiralAppPostSession: SpiralAppSessionProtocol {
    private let postEventID: String
    private let roomProxy: JoinedRoomProxyProtocol
    private let reader: SpiralAppStateReader

    /// Dropping this unsubscribes, so it is held for the session's lifetime.
    private let feed: SpiralAppActionFeed
    /// Asks the user when encryption refuses an action for a verified user's
    /// devices or identity (§ 5.87); `nil` where no sheet can be shown.
    private let refusals: SpiralAppSendRefusals?
    /// Where the people's avatars come from (§ 5.64); nil in a harness.
    private let mediaProvider: MediaProviderProtocol?
    /// The room's people as they change (§ 5.67): the roster the room proxy
    /// publishes, reduced to what `members.basic.read` answers, only when the
    /// PEOPLE in it change — a name or avatar changing is not a new roster,
    /// and the publisher fires for every member update.
    ///
    /// The roster itself is refreshed when the room's joined count changes:
    /// the proxy loads members once on open and again only when a screen
    /// asks, so a join or leave while a post is mounted reached nobody until
    /// this asked for it.
    var membersPublisher: AnyPublisher<[String: Any], Never> {
        let mediaProvider = mediaProvider
        let refreshOnCountChange = roomProxy.infoPublisher
            .map(\.joinedMembersCount)
            .removeDuplicates()
            .dropFirst()
            .handleEvents(receiveOutput: { [roomProxy] _ in Task { await roomProxy.updateMembers() } })
            .compactMap { _ -> [String]? in nil }
        let people = roomProxy.membersPublisher
            .map { members in members.filter { $0.membership == .join && !Self.isAgent($0.userID) }.map(\.userID).sorted() }
            .removeDuplicates()
            .dropFirst()
        return people.merge(with: refreshOnCountChange)
            .flatMap { [roomProxy] _ in
                Future<[String: Any], Never> { promise in
                    Task {
                        let payload = await Self.membersPayload(roomProxy.membersPublisher.value, mediaProvider: mediaProvider)
                        promise(.success(payload))
                    }
                }
            }
            .eraseToAnyPublisher()
    }

    private var listening: SpiralAppActionFeed.Token?

    /// This phone's corner of the post, for this account (§ 5.78): the move
    /// behind a seal waits here to be opened.
    var privateCorner: SpiralAppPrivateCorner? {
        SpiralAppStoredCorner(userID: roomProxy.ownUserID, postID: postEventID, store: .shared)
    }

    /// The state budget from § 5.2, in bytes of encoded JSON.
    ///
    /// It no longer has anything to do with the size of an event. The state
    /// stopped travelling when the blob left the action, so what this bounds
    /// now is what an app may ACCUMULATE: the cost of folding it afresh on
    /// every open, and the size of a checkpoint if one is ever written.
    ///
    /// The wire ceiling was measured rather than assumed (2026-09-21, against
    /// the real server): `content` is accepted up to **64 917 bytes** and
    /// refused at 64 956 with `M_TOO_LARGE`. In an encrypted room the
    /// plaintext is Megolm-encrypted and base64'd, costing about a third, so
    /// the same ceiling is near **48 KB** — checked against real ciphertexts
    /// rather than derived alone. Both are far above anything an operation
    /// reaches: a stroke is about 900 bytes.
    ///
    /// So 16 KB stays, deliberately. The integer grid made it worth about a
    /// hundred strokes instead of twenty-two, nothing reaches it, and raising
    /// it would spend the margin a future checkpoint needs in exchange for
    /// room nobody is asking for. The number to raise it to is known when
    /// something finally wants it.
    ///
    /// Shared with the preview, so an artifact meets the same wall before it
    /// is published as after.
    static let maxStateBytes = 16 * 1024

    /// Operations written but not yet seen coming back.
    ///
    /// Without this, two taps inside one round trip both compute from the last
    /// CONFIRMED state, both claim the same `seq`, and last-write-wins keeps
    /// one — so the second tap does nothing. Observed on two devices,
    /// 2026-09-14; design notebook OPEN #15.
    private var pending: [(seq: Int, operation: SpiralAppOperation, mentioned: [String])] = []

    private var snapshotCancellable: AnyCancellable?

    /// Set by the row that owns this post; nil while nobody can expand.
    var onExpandRequested: (() -> Void)?

    /// What the app is shown: the room's fold with our un-echoed operations
    /// replayed over it — the LOCAL ECHO (6.11 A2).
    ///
    /// There was none, "on purpose", and it flickered: the SDK applied a tap
    /// optimistically, `apply` resolved when the server took the event, the
    /// SDK then dropped its guess — but the room's fold had not yet seen the
    /// action, so the tap VANISHED for the round trip and came back with
    /// the relation. Pressing rock showed rock, then nothing, then rock.
    /// Publishing the working state on `pending` changes means the fold the
    /// app adopts on resolve already contains the tap.
    private let echoSubject = CurrentValueSubject<SpiralAppStateReader.Snapshot, Never>(.loading)

    var snapshotPublisher: AnyPublisher<SpiralAppStateReader.Snapshot, Never> {
        echoSubject.eraseToAnyPublisher()
    }

    var snapshot: SpiralAppStateReader.Snapshot {
        echoSubject.value
    }

    /// The room's fold with `pending` replayed, at the highest seq of both.
    private func echo() {
        let confirmed = reader.snapshot
        guard !pending.isEmpty else {
            echoSubject.send(confirmed)
            return
        }
        echoSubject.send(.init(state: workingState,
                               seq: max(confirmed.seq, pending.last?.seq ?? 0),
                               readiness: confirmed.readiness,
                               summary: confirmed.summary,
                               awaitingReply: confirmed.awaitingReply))
    }

    /// Who is looking at this post, and where.
    ///
    /// Fixed for a mounted session: the room and the post cannot change, and
    /// the viewer cannot become someone else without a remount.
    var context: [String: Any] {
        ["userId": roomProxy.ownUserID, "roomId": roomProxy.id, "postId": postEventID]
    }

    /// Display names and avatars, and deliberately nothing else.
    ///
    /// Not presence, not power levels, not who has read what. An app draws a
    /// name next to a vote; everything past that would be telling it about
    /// the conversation, which it has no business knowing (§ 4.8).
    ///
    /// A room shows its posts before its roster has loaded, so a list with
    /// nobody but us in it is waited for once: `useRoomMembers` asks a single
    /// time, and answered early an app showed an empty room for good.
    func members() async -> [String: Any] {
        var loaded = roomProxy.membersPublisher.value
        if loaded.filter({ $0.membership == .join && !Self.isAgent($0.userID) }).count <= 1 {
            loaded = await roomProxy.members() ?? loaded
        }
        return await Self.membersPayload(loaded, mediaProvider: mediaProvider)
    }

    /// «Your move» (§ 7 #1, § 5.73): whom this action should tell.
    ///
    /// The app suggests (`summary.notify_users`); the client decides — never
    /// oneself or an agent, and never someone already pinged who has not
    /// touched the post since (§ 5.74): the room's own record of who was
    /// mentioned and who acted, plus our actions still on their way.
    ///
    /// The mention rides on the ACTION, not on a message beside it. The push
    /// rule `.m.rule.is_user_mention` reads `m.mentions` and nothing else —
    /// not the event's type — so the named person is told; and no other rule
    /// matches `com.spiral.app.action`, so nobody else is. A message did
    /// neither: an `m.notice` is suppressed by `.m.rule.suppress_notices`
    /// before the mention rule is read (six «your move» notices on prod
    /// pushed nothing), and an `m.text` reaches everyone who keeps the room on
    /// «all messages» and grows a thread under the game. The NSE shows the
    /// action (`SpiralActionNotification`).
    private func mentionable(in summary: [String: Any]?) -> [String] {
        guard let named = summary?["notify_users"] as? [String] else { return [] }
        let waiting = reader.snapshot.awaitingReply.union(pending.flatMap(\.mentioned))
        var seen = Set<String>()
        return named.filter { $0 != roomProxy.ownUserID && !Self.isAgent($0) && !waiting.contains($0) && seen.insert($0).inserted }
    }

    /// Whether a Matrix user is one of the platform's agents rather than a
    /// person. Agents live in their own application-service namespaces —
    /// `@assistant-<owner>:…` (personal) and `@agent-<slug>-<n>:…` (company)
    /// — so the id says, and the display name («Assistant Alice Example 2»)
    /// does not have to (§ 5.64). An agent does not roll dice or vote.
    ///
    /// Any server's namespace on purpose: agents live only on our own
    /// homeserver (ADR-0082's exclusive application-service namespaces), so
    /// the people counted here are never another server's agents. Where a
    /// foreign `@assistant-…` must count as a person — a call's peer, a room
    /// grant — `SpiralAgentRoomGrants.isLocalAgent` adds the server.
    nonisolated static func isAgent(_ userID: String) -> Bool {
        guard userID.hasPrefix("@"), let colon = userID.firstIndex(of: ":") else { return false }
        let localpart = userID[userID.index(after: userID.startIndex)..<colon]
        return localpart.hasPrefix("assistant-") || localpart.hasPrefix("agent-")
    }

    /// The pixel size of the avatar a post gets: the row's avatar is 28 pt,
    /// at 3× that is 84; 64 px is the messenger's own small thumbnail and a
    /// few kilobytes.
    static let avatarSize = CGSize(width: 64, height: 64)

    /// What `members.basic.read` answers for a list of members.
    ///
    /// Only PEOPLE actually IN the room: an app counting "3 of 5" must not
    /// count someone who left or was only invited, nor the agent (§ 5.64).
    /// Shared with the draft preview and the catalogue, so a draft shows its
    /// target room's people in the same shape.
    ///
    /// The avatar travels as a `data:` URL, not `mxc:`: the frame has no
    /// network (`connect-src 'none'`, § 4) and cannot fetch one, and it must
    /// not — so the host hands over the messenger's own 64 px thumbnail,
    /// from the same cache the room list draws from. None, and the kit draws
    /// the messenger's placeholder.
    static func membersPayload(_ members: [RoomMemberProxyProtocol],
                               mediaProvider: MediaProviderProtocol? = nil) async -> [String: Any] {
        let people = members.filter { $0.membership == .join && !isAgent($0.userID) }
        let avatars = await avatarDataURLs(for: people, mediaProvider: mediaProvider)
        let entries = people.map { member -> [String: Any] in
            var entry: [String: Any] = ["userId": member.userID]
            // Disambiguated, so two people called "Sasha" are told apart
            // in a card that has no room to explain itself.
            if let name = member.disambiguatedDisplayName ?? member.displayName {
                entry["displayName"] = name
            }
            if let avatar = avatars[member.userID] {
                entry["avatarUrl"] = avatar
            }
            return entry
        }

        return ["members": entries]
    }

    /// The thumbnails, fetched together; one that does not arrive is left out.
    private static func avatarDataURLs(for members: [RoomMemberProxyProtocol],
                                       mediaProvider: MediaProviderProtocol?) async -> [String: String] {
        guard let mediaProvider else { return [:] }
        return await withTaskGroup(of: (String, String?).self) { group in
            for member in members {
                guard let url = member.avatarURL, let source = try? MediaSourceProxy(url: url, mimeType: nil) else { continue }
                group.addTask {
                    guard case .success(let data) = await mediaProvider.loadThumbnailForSource(source: source, size: avatarSize) else {
                        return (member.userID, nil)
                    }
                    return (member.userID, "data:image/jpeg;base64," + data.base64EncodedString())
                }
            }
            var found: [String: String] = [:]
            for await (userID, dataURL) in group {
                if let dataURL {
                    found[userID] = dataURL
                }
            }
            return found
        }
    }

    var time: [String: Any] {
        Self.time(floor: reader.newestOriginServerTimestamp)
    }

    /// Confirmed state with our un-echoed operations replayed over it.
    ///
    /// What the NEXT action is computed from. Not what the app displays — the
    /// SDK does its own optimistic apply for that — so the two do not stack.
    var workingState: SpiralAppValue {
        pending.reduce(reader.snapshot.state) { $1.operation.applied(to: $0) }
    }

    init(postEventID: String,
         roomProxy: JoinedRoomProxyProtocol,
         feed: SpiralAppActionFeed,
         mediaProvider: MediaProviderProtocol? = nil,
         refusals: SpiralAppSendRefusals? = nil) {
        self.postEventID = postEventID
        self.roomProxy = roomProxy
        self.feed = feed
        self.mediaProvider = mediaProvider
        self.refusals = refusals

        reader = SpiralAppStateReader(postEventID: postEventID) { [roomProxy] eventID in
            try await roomProxy.loadSpiralAppRelations(for: eventID).get()
        }

        snapshotCancellable = reader.snapshotPublisher.sink { [weak self] snapshot in
            // Anything numbered at or below what the room now shows has either
            // landed or lost its race; either way it must stop being replayed,
            // or it would be counted twice.
            self?.pending.removeAll { $0.seq <= snapshot.seq }
            self?.echo()
        }
    }

    deinit {
        // `stopListening` is main-actor work and deinit is not, so the token is
        // surrendered in `stop()`. A session dropped without it leaves a
        // listener that its `[weak self]` renders harmless, and which the last
        // real listener's departure still clears.
    }

    /// Listen, then read. In that order, so an action landing during the read
    /// is queued rather than missed.
    ///
    /// The room's subscription is shared (`SpiralAppActionFeed`): it is opened
    /// once however many posts are mounted, and this session hears only the
    /// actions naming this post.
    func start() async {
        listening = await feed.listen(toPost: postEventID) { [weak self] events in
            self?.ingest(events)
        }

        await reader.refresh()
    }

    /// Give up the room subscription's share of this post.
    func stop() {
        guard let listening else { return }
        feed.stopListening(listening)
        self.listening = nil
    }

    /// Apply an operation and publish it as an action.
    ///
    /// The caller supplies only the operation. The resulting `state` and the
    /// `seq` are computed HERE, from the authoritative fold, because an app
    /// computing them from a stale base would write a full-state snapshot
    /// that then becomes everyone else's base.
    /// - Parameter summary: what the post should say where its own code is
    ///   not running — the timeline card, a push, a search snapshot. Passed
    ///   through as the app wrote it; the shell has already refused the one
    ///   shape that reaches people uninvited (a `ping` naming nobody).
    func apply(_ operation: SpiralAppOperation,
               summary: [String: Any]? = nil) async -> Result<Void, SpiralAppPostError> {
        let current = reader.snapshot

        guard current.readiness != .loading else {
            // Writing from a state we could not vouch for would publish a
            // snapshot built on a hole, and every other client would adopt it.
            return .failure(.stateNotReady)
        }

        // `by.<someone else>` is theirs. The fold would ignore the write
        // anyway; refusing it here tells the app at once instead of letting
        // it show a change the room will never agree to.
        if operation.members.contains(where: { $0.owner != nil && $0.owner != roomProxy.ownUserID }) {
            return .failure(.notOwner)
        }

        let next = operation.applied(to: workingState)

        // The state is not sent (see below), but it is still BOUNDED: an app
        // that only grows would otherwise accumulate a state no checkpoint
        // could ever hold, and every reader would fold it afresh on each
        // open. Refusing early at the documented budget (§ 5.2) leaves the
        // app able to say so and able to delete its way back.
        guard let encodedState = next.encoded(), encodedState.count <= Self.maxStateBytes else {
            return .failure(.stateTooLarge)
        }

        // Follows the highest of what the room has confirmed and what we have
        // already written, so a burst of taps numbers itself 1, 2, 3 rather
        // than claiming 1 three times.
        let seq = max(current.seq, pending.last?.seq ?? 0) + 1

        // THE OPERATION, NOT THE STATE.
        //
        // An action used to carry the whole state beside its operation, and
        // that blob was 85–90 % of the event — 11.5 KB of it on a drawing
        // fifteen strokes old, to convey 900 bytes of new fact. Worse, it
        // grew with the history: every stroke cost more to send, to receive
        // and to decrypt than the one before it, for everyone in the room.
        //
        // It was never read. The fold replays operations from empty and
        // treats a blob as a CHECKPOINT only when an action carries state and
        // no operation (`SpiralAppStateFold`), which no action ever did. So
        // this is a deletion, not a redesign, and every client that already
        // folds the way § 5.41 fixed it keeps agreeing with every other.
        //
        // Correctness does not need checkpoints: the relations read paginates
        // `/relations` until exhausted, so a reader opening a post a year
        // later still sees every operation. They would be an OPTIMISATION for
        // a very long history — the fold already understands them — and can
        // be added the day a post is long enough to want one.
        var content: [String: Any] = [
            "m.relates_to": ["rel_type": "m.reference", "event_id": postEventID],
            "op": operation.jsonObject,
            "seq": seq
        ]
        if let summary {
            content["summary"] = summary
        }
        let mentioned = mentionable(in: summary)
        if !mentioned.isEmpty {
            content["m.mentions"] = ["user_ids": mentioned]
        }

        #if DEBUG
        // Step 6.14 — the measurement the spike has owed since 2026-09-14,
        // where the table still stands empty. The action carries the moment
        // it left, so the peer can price the whole road by itself instead of
        // us stitching two logs together. Two simulators on one Mac share a
        // clock, which is the only reason this is honest; on real devices
        // apart it prices the road plus whatever the clocks disagree by.
        // A WHOLE number of milliseconds. The first cut of this line wrote a
        // Double and every stroke came back `M_BAD_JSON: Bad JSON value:
        // float` — the same wall § 5.41 is about, hit by the instrument built
        // to measure it. The JS SDK encodes what an APP writes; nothing
        // guards what Swift adds to an event beside it.
        let sentAtMS = Int(Date().timeIntervalSince1970 * 1000)
        content["dbg"] = ["t": sentAtMS]
        #endif

        guard let data = try? JSONSerialization.data(withJSONObject: content),
              let json = String(data: data, encoding: .utf8) else {
            return .failure(.notEncodable)
        }

        pending.append((seq, operation, mentioned))
        // Shown NOW, before the round trip — see `echoSubject`.
        echo()

        let send = { [roomProxy] in await roomProxy.sendSpiralRawEvent(type: SpiralAppAction.eventType, content: json) }
        let outcome = if let refusals { await refusals.send(send) } else { await send() }

        #if DEBUG
        // What the send itself cost: encrypt for the room, then the HTTP
        // round trip to the homeserver. The gap BETWEEN two of these lines
        // during a continuous drag is the coalescing window doing its job,
        // which is why the window needs no instrument of its own.
        MXLog.info("[spiral-lat] send seq=\(seq) ms=\(Int(Date().timeIntervalSince1970 * 1000) - sentAtMS)")
        #endif

        switch outcome {
        case .success:
            // The action comes back through the subscription like anyone
            // else's; the reader's fold is still the one source of truth,
            // the echo only replays what is on its way there.
            return .success(())
        case .failure(let error):
            // It was never written, so replaying it would invent a change
            // nobody else will ever see.
            pending.removeAll { $0.seq == seq }
            echo()
            return .failure(.sendFailed(error))
        }
    }

    // MARK: - Private

    private func ingest(_ events: [SpiralObservedEvent]) {
        // A UTD carries no readable content; the SDK delivers it again once
        // its key arrives, so it is skipped rather than counted as missing.
        let readable = events.filter { !$0.isUtd }.map(\.eventJson)
        guard !readable.isEmpty else { return }

        Task { await reader.ingest(rawEventJSONs: readable) }
    }
}

enum SpiralAppPostError: Error {
    /// The post's actions have not been read completely enough to build on.
    case stateNotReady
    /// The state this would produce is past the budget an event can carry.
    case stateTooLarge
    /// The operation writes into another user's `by.<userId>` namespace.
    case notOwner
    case notEncodable
    case sendFailed(RoomProxyError)
}

extension SpiralAppPostError {
    /// Map onto the bridge's closed set, so an app sees a code it can act on.
    ///
    /// Beside the error rather than beside a caller: every place that answers
    /// the bridge owes an app the same code for the same failure.
    var bridgeCode: String {
        switch self {
        case .stateNotReady: "unavailable"
        case .stateTooLarge: "rejected"
        case .notOwner: "rejected"
        case .notEncodable: "rejected"
        case .sendFailed: "unavailable"
        }
    }
}
