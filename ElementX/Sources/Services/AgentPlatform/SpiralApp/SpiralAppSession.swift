//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.8): what an app may ask, and the one
// place that answers.
//
// The owner publishes, not the agent (design § 4.8), so an artifact has to run
// BEFORE it is a post — with nothing to relate actions to and nothing to send
// them to. That is a different place for state to live, and nothing else: the
// app must not be able to tell, or a preview would prove nothing about the post
// it becomes.
//
// So the bridge contract lives here, written once, over whichever session is
// underneath.
//

import Combine
import Foundation

@MainActor
protocol SpiralAppSessionProtocol: AnyObject {
    /// State as this session believes it to be, published on every change.
    ///
    /// `SpiralAppInstance` forwards this into the running app. A preview
    /// publishes too, so an app behaves the same in one — which is the whole
    /// point of rehearsing in it.
    var snapshotPublisher: AnyPublisher<SpiralAppStateReader.Snapshot, Never> { get }
    /// Answers `app.context.read`.
    var context: [String: Any] { get }
    /// Answers `members.basic.read`.
    ///
    /// Async because a roster can be missing when an app mounts, and
    /// `useRoomMembers` asks once: answered `[]` too early, an app showed an
    /// empty room for good — which a list baked into the module used to hide.
    func members() async -> [String: Any]
    /// The room's people, whenever they change while the app is mounted —
    /// pushed as `members.changed` (§ 5.67). A session with a fixed roster
    /// publishes nothing.
    var membersPublisher: AnyPublisher<[String: Any], Never> { get }
    /// Answers `state.shared.read`.
    var snapshot: SpiralAppStateReader.Snapshot { get }
    /// Answers `state.shared.write`.
    func apply(_ operation: SpiralAppOperation, summary: [String: Any]?) async -> Result<Void, SpiralAppPostError>
    /// Answers `time.read`: `now` in ms since the epoch, and the `floor` it
    /// was clamped to — the newest `origin_server_ts` this post has seen.
    ///
    /// A countdown, a timer, a deadline: an app that reads its own clock
    /// shows two phones two different answers. This is the host's clock,
    /// which is at least never EARLIER than the room's newest event — a
    /// phone whose clock is behind cannot make a deadline that has passed
    /// look open. It is not server time; there is no such thing to ask for.
    var time: [String: Any] { get }

    /// Called when the app asks for the whole screen (`ui.expand`).
    ///
    /// Set by whoever owns the row; nil where there is nowhere to expand to.
    var onExpandRequested: (() -> Void)? { get set }

    /// Answers `state.private.*` (§ 5.78): where this phone keeps what the
    /// post keeps only here. Nil keeps nothing, and says so to a writer.
    var privateCorner: SpiralAppPrivateCorner? { get }

    /// Begin listening for other people's actions.
    func start() async
    /// Stop listening.
    func stop()
}

extension SpiralAppSessionProtocol {
    // A session with nothing behind it — a preview — has nothing to listen to
    // and nothing to give up. Defaulted rather than required so that stays
    // obvious instead of being written out as two empty methods.
    func start() async { }
    func stop() { }

    /// Nowhere to expand to, which is the truth for a session nobody is
    /// showing in a row. Defaulted so a conformer only writes this when it
    /// has an answer — and so adding `ui.expand` did not break every double.
    var onExpandRequested: (() -> Void)? {
        get { nil }
        set { }
    }

    /// Nowhere to keep anything: a double that never seals.
    var privateCorner: SpiralAppPrivateCorner? {
        nil
    }

    /// The wall clock, with no room to clamp it to.
    var time: [String: Any] {
        Self.time(floor: 0)
    }

    static func time(floor: UInt64) -> [String: Any] {
        let wall = UInt64(Date().timeIntervalSince1970 * 1000)
        return ["now": max(wall, floor), "floor": floor]
    }
}

extension SpiralAppSessionProtocol {
    /// Answer one bridge call from the app mounted on this session.
    ///
    /// One implementation for every kind of session, because an app that could
    /// tell a preview from a post would be proving the wrong thing when it ran
    /// in one.
    ///
    /// The `default` arm matters as much as the others: a capability the
    /// manifest did not get is refused here too, so the granted list is not the
    /// only thing between an app and a method.
    func answer(method: String, args: Data) async -> String {
        switch method {
        case SpiralAppCapability.appContextRead.rawValue:
            return SpiralAppBridge.success(context)

        case SpiralAppCapability.membersBasicRead.rawValue:
            return await SpiralAppBridge.success(members())

        case SpiralAppCapability.stateSharedRead.rawValue:
            return SpiralAppBridge.success(["state": snapshot.state.jsonObject,
                                            "seq": snapshot.seq])

        case SpiralAppCapability.timeRead.rawValue:
            return SpiralAppBridge.success(time)

        case SpiralAppCapability.statePrivateRead.rawValue:
            return SpiralAppBridge.success(["state": privateCorner?.state ?? [:]])

        case SpiralAppCapability.statePrivateWrite.rawValue:
            // Checked again here: the shell is ours, but the frame that asked
            // is not, and this is what writes to the phone's storage.
            guard let corner = privateCorner else {
                return SpiralAppBridge.failure(code: "unavailable", message: "this post keeps nothing on the phone")
            }
            guard let body = try? JSONSerialization.jsonObject(with: args) as? [String: Any],
                  let state = body["state"] as? [String: Any],
                  let encoded = try? JSONSerialization.data(withJSONObject: state),
                  encoded.count <= SpiralAppPrivateStore.maxBytes else {
                return SpiralAppBridge.failure(code: "rejected",
                                               message: "private state is an object of at most \(SpiralAppPrivateStore.maxBytes) bytes")
            }
            corner.replace(with: state)
            return SpiralAppBridge.success(nil)

        case SpiralAppCapability.uiHaptic.rawValue:
            // Feel, not data: nothing is read and nothing is written, which
            // is why a post may have it without widening § 4.8. A phone with
            // no Taptic engine simply does nothing.
            let strength = (try? JSONSerialization.jsonObject(with: args) as? [String: Any])?
                .flatMap { $0["strength"] as? String } ?? "light"
            SpiralAppFeedback.play(strength)
            return SpiralAppBridge.success(nil)

        case SpiralAppCapability.uiExpand.rawValue:
            // A REQUEST, not a transition: only the row knows whether a
            // viewer is already open, so the app is told it was heard and
            // the host decides. Without a handler (a preview, the lab) it is
            // heard and ignored, which is the honest answer.
            onExpandRequested?()
            return SpiralAppBridge.success(nil)

        case SpiralAppCapability.stateSharedWrite.rawValue:
            guard let body = try? JSONSerialization.jsonObject(with: args) as? [String: Any],
                  let raw = body["op"],
                  let operation = SpiralAppOperation(json: raw) else {
                return SpiralAppBridge.failure(code: "rejected", message: "not an operation this runtime knows")
            }

            switch await apply(operation, summary: body["summary"] as? [String: Any]) {
            case .success:
                MXLog.info("[SpiralApp] write ok: \(operation.shortDescription)")
                return SpiralAppBridge.success(nil)
            case .failure(let error):
                // A refused write is the one thing an app cannot see from
                // inside its frame; without this line a tap that did nothing
                // left no trace anywhere (chess, 2026-09-18).
                MXLog.warning("[SpiralApp] write refused (\(error.bridgeCode)): \(operation.shortDescription) — \(error)")
                return SpiralAppBridge.failure(code: error.bridgeCode, message: "\(error)")
            }

        default:
            return SpiralAppBridge.failure(code: "rejected", message: "not granted: \(method)")
        }
    }
}

extension SpiralAppSessionProtocol {
    var membersPublisher: AnyPublisher<[String: Any], Never> {
        Empty().eraseToAnyPublisher()
    }
}

/// A session for an artifact that is not a post yet.
///
/// Its state lives in memory and goes nowhere: there is no event to relate an
/// action to, and publishing from a preview would put an app's rehearsal into
/// the room.
///
/// It enforces the SAME budget as a real post. An app that only grows would
/// brick its post once published (§ 5.2); finding that out in the preview, on
/// the author's own screen, is the entire reason the preview is worth having
/// rather than a picture of one.
@MainActor
final class SpiralAppPreviewSession: SpiralAppSessionProtocol {
    private var state: SpiralAppValue = .object([:])
    var onExpandRequested: (() -> Void)?
    /// In memory, like its state: a rehearsal's sealed move is gone with it.
    let privateCorner: SpiralAppPrivateCorner? = SpiralAppMemoryCorner()
    private var seq = 0
    private let snapshotSubject = PassthroughSubject<SpiralAppStateReader.Snapshot, Never>()

    var snapshotPublisher: AnyPublisher<SpiralAppStateReader.Snapshot, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    private let userID: String
    private let loadMembers: () async -> [String: Any]

    convenience init(userID: String, members: [String: Any]) {
        self.init(userID: userID) { members }
    }

    /// A preview of a post FOR another room shows that room's people, read
    /// when the app asks — not the thread's, and not nobody.
    init(userID: String, loadMembers: @escaping () async -> [String: Any]) {
        self.userID = userID
        self.loadMembers = loadMembers
    }

    var context: [String: Any] {
        // The instance id is honestly not an event id. An app that persisted
        // anything under it would be storing it against a post that does not
        // exist, which is exactly what should not survive the preview.
        ["instanceId": "preview", "userId": userID, "isPreview": true]
    }

    func members() async -> [String: Any] {
        await loadMembers()
    }

    var snapshot: SpiralAppStateReader.Snapshot {
        // Always ready: there is no history to be incomplete about.
        .init(state: state, seq: seq, readiness: .ready, summary: nil)
    }

    func apply(_ operation: SpiralAppOperation, summary: [String: Any]?) async -> Result<Void, SpiralAppPostError> {
        let next = operation.applied(to: state)

        guard let encoded = next.encoded(), encoded.count <= SpiralAppPostSession.maxStateBytes else {
            return .failure(.stateTooLarge)
        }

        state = next
        seq += 1
        snapshotSubject.send(snapshot)
        return .success(())
    }
}
