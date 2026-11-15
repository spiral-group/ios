//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
import CallKit
import Combine
import Foundation
import Intents
import MatrixRustSDK
import PushKit
import UIKit
import UserNotifications

/// Keep this class testable
struct TimeProvider {
    var clock: any Clock<Duration>
    /// Upstream 26.10's addition, for `LiveLocationService`.
    var now: () -> Date = Date.init
}

protocol CXCallControllerProtocol {
    func request(_ transaction: CXTransaction) async throws
    func request(_ transaction: CXTransaction, completion: @escaping @Sendable (Error?) -> Void)
}

extension CXCallController: CXCallControllerProtocol { }

// AGENT-PLATFORM (Brief 0067): upstream's `ElementCallService`, renamed — it is
// the PushKit/CallKit/Recents/decline layer, and it outlived the web view it
// was named after (ADR-0079).
class CallKitService: NSObject, CallKitServiceProtocol, PKPushRegistryDelegate, CXProviderDelegate {
    private struct CallID: Equatable {
        let callKitID: UUID
        let roomID: String
        let rtcNotificationID: String?
        let isVoiceCall: Bool
        /// What the ring called this call ("Group — Person" for a group
        /// ring, the person for a DM). Kept on the ID because two of the
        /// ways a ring dies unanswered — the caller giving up, a second
        /// ring replacing it — happen long after the push that knew the
        /// name has left scope, and the missed-call notification must say
        /// WHO was missed. Outgoing calls carry the plain room name; only
        /// `incomingCallID` ever feeds the missed-call notification.
        var ringDisplayName: String?
    }

    private let pushRegistry: PKPushRegistry
    private let callController: CXCallControllerProtocol
    private let callProvider: CXProviderProtocol

    /// How long the media stack gets to answer a CallKit action before we stop
    /// waiting. A mute is a local publication toggle (milliseconds); anything
    /// slower is a wedge, and CallKit times the action out on its own soon
    /// after.
    private static let actionReplyTimeout = Duration.seconds(2)
    private let timeProvider: TimeProvider
    private let audio: NativeCallAudioControlling
    /// Where the missed-call notification goes. `nil` only in a test process
    /// that did not inject one — a real center would post actual banners from
    /// unit tests, and an un-configured mock crashes by design.
    private let notificationCenter: UserNotificationCenterProtocol?

    /// The claim on the process-wide call audio taken when a CallKit action for
    /// a native call fulfils, held until the call ends.
    ///
    /// CallKit activates whatever category is configured at fulfil time, which
    /// is before any `NativeCallSession` exists — and a call can end without
    /// one ever existing: the user hangs up while routing, the room lookup
    /// fails, the app is suspended between `fulfill()` and the screen. Doing
    /// that configuration with nothing to release left LiveKit's automatic
    /// configuration disabled for the rest of the process.
    private var callKitActivationAudioOwner: NativeCallAudioOwner?

    /// Whether a CallKit audio session is in flight for one of our calls.
    ///
    /// The live call cannot answer that when the deactivation arrives:
    /// `tearDownCallSession` clears `ongoingCallID` synchronously while CallKit
    /// delivers `provider(_:didDeactivate:)` only after the end action has
    /// settled, so by then the call that held the audio is already gone from
    /// this service. This outlives that gap.
    private var isHoldingCallKitAudio = false

    private weak var clientProxy: ClientProxyProtocol? {
        didSet {
            // There's a race condition where a call starts when the app has been killed and the
            // observation set in `incomingCallID` occurs *before* the user session is restored.
            // So observe when the client proxy is set to fix this (the method guards for the call).
            Task { await observeIncomingCall() }
        }
    }

    private var incomingCallRoomInfoCancellable: AnyCancellable?
    private var incomingCallID: CallID? {
        didSet {
            Task { await observeIncomingCall() }
        }
    }

    private var endUnansweredCallTask: Task<Void, Never>?

    /// The in-app ring the user accepted, from the tap until its screen
    /// registers in `setupCallSession` or a teardown gives its call up. It
    /// outlives the ring slot: the ring's watcher can retire the ring first
    /// — its caller hung up, a newer ring replaced it, our own join echoed
    /// back as "answered elsewhere" — and the call parked for it at the tap
    /// still has to be resolved (follow-up L1).
    private var acceptedInAppRing: CallID? {
        // Its record goes with it, taken or given up.
        didSet {
            if acceptedInAppRing == nil { callsLiveAtAccept = [] }
        }
    }

    /// The calls in the slots when the user accepted `acceptedInAppRing`.
    /// A screen of one of them is older than the ring's (L2 review).
    private var callsLiveAtAccept = Set<UUID>()

    /// The accepted ring a registration took but did not adopt (it found the
    /// room's live call, or a newer ring of the room in the slot) leaves the
    /// refused-ring record with it.
    private func forgetRefusal(ofUnadopted acceptedRing: CallID?) {
        guard let acceptedRing, ongoingCallID?.callKitID != acceptedRing.callKitID else { return }
        ringsCallKitRefused.remove(acceptedRing.callKitID)
    }

    /// An accepted ring given up: out of the ring slot if it is still there,
    /// and out of the refused-ring record.
    private func forget(acceptedRing: CallID) {
        ringsCallKitRefused.remove(acceptedRing.callKitID)
        guard incomingCallID?.callKitID == acceptedRing.callKitID else { return }
        clearIncomingCallState()
    }

    /// Hands the accepted in-app ring of `roomID` to whatever registers or
    /// gives up its call; an unscoped teardown (`nil`) drops it.
    private func takeAcceptedInAppRing(forRoomID roomID: String?) -> CallID? {
        guard let ring = acceptedInAppRing, roomID == nil || ring.roomID == roomID else { return nil }
        acceptedInAppRing = nil
        return ring
    }

    /// Rings CallKit refused to present (Do Not Disturb, a Focus): they rang
    /// in the app only, so CallKit has no call under their UUIDs, and the
    /// screen that registers one starts it (earlier follow-up 6a).
    private(set) var ringsCallKitRefused = Set<UUID>()

    /// Missed calls that happened before the user session was restored — a
    /// cold-launch VoIP push can expire before `setClientProxy` runs, and a
    /// notification stamped without `receiver_id` has a tap that routes
    /// nowhere (`AppCoordinator.notificationTapped` guards on it). Flushed
    /// the moment the session arrives.
    private var pendingMissedCallNotifications = [(roomID: String, displayName: String)]()

    private var ongoingCallID: CallID? {
        didSet { publishOngoingCallRoom() }
    }

    /// Calls whose screen has stopped and whose teardown has not landed yet
    /// (`markCallEnding`): over for the app, still CallKit's (review item 8).
    private var endingCallKitIDs = Set<UUID>()

    /// Whether this device's call in `roomID` has a screen that is stopping.
    private func hasEndingCall(inRoomID roomID: String) -> Bool {
        [ongoingCallID, heldCallID].contains { $0?.roomID == roomID && notEnding($0) == nil }
    }

    /// `callID` unless its screen is stopping.
    private func notEnding(_ callID: CallID?) -> CallID? {
        callID.flatMap { endingCallKitIDs.contains($0.callKitID) ? nil : $0 }
    }

    private func publishOngoingCallRoom() {
        ongoingCallRoomIDSubject.send(notEnding(ongoingCallID)?.roomID)
    }

    private var ongoingCallDisplayName: String?

    /// The outgoing CallKit call that is still ringing and has not been
    /// reported as connected yet.
    private var pendingOutgoingConnectionCallKitID: UUID?
    /// AGENT-PLATFORM (Brief 0067, call audit 2026-09-05, P2): the peer
    /// answered while `setupCallSession` was still inside
    /// `callController.request` — `pendingOutgoingConnectionCallKitID` is
    /// assigned only after that returns, so the `.connected` report used to
    /// fail its guard and be dropped, and nothing retried it: the app showed
    /// a live call while CallKit stayed at "connecting". The early report is
    /// remembered here and honoured the moment the setup catches up.
    private var connectedBeforeSetupCallKitID: UUID?

    let ongoingCallRoomIDSubject = CurrentValueSubject<String?, Never>(nil)
    var ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never> {
        ongoingCallRoomIDSubject.asCurrentValuePublisher()
    }

    // MARK: - Call waiting between Spiral calls (Brief 0068 Slice 2)

    /// The second live call, parked. Answering a second Spiral call used to
    /// END the first ("one call screen"); it holds it now, and the two
    /// swap through CallKit so the system UI, Recents and the audio
    /// session agree on which one is active. Written only through
    /// `setHeld(_:name:)` so the id and the name publish together.
    private var heldCallID: CallID?
    private var heldCallDisplayName: String?
    private let heldCallSubject = CurrentValueSubject<CallKitHeldCall?, Never>(nil)
    var heldCallPublisher: CurrentValuePublisher<CallKitHeldCall?, Never> {
        heldCallSubject.asCurrentValuePublisher()
    }

    private func setHeld(_ callID: CallID?, name: String?) {
        heldCallID = callID
        heldCallDisplayName = name
        heldCallSubject.send(callID.map { CallKitHeldCall(roomID: $0.roomID, displayName: name ?? $0.ringDisplayName ?? $0.roomID) })
    }

    func swapCalls() {
        guard let ongoingCallID, let heldCallID else { return }
        MXLog.info("Swapping calls: holding \(ongoingCallID.roomID), resuming \(heldCallID.roomID)")
        let transaction = CXTransaction()
        transaction.addAction(CXSetHeldCallAction(call: ongoingCallID.callKitID, onHold: true))
        transaction.addAction(CXSetHeldCallAction(call: heldCallID.callKitID, onHold: false))
        callController.request(transaction) { error in
            if let error {
                MXLog.error("Swapping calls failed: \(error)")
            }
        }
    }

    /// The previous call is HELD, not ended, when an incoming one is
    /// answered — from the CallKit banner ("Hold & Accept") or the in-app
    /// fallback ring. With a held call already there, that one is over: two
    /// parked calls is not a UI this app has.
    private func parkOngoingCall(_ previous: CallID, answering incoming: CallID) {
        guard notEnding(previous) != nil else {
            endStoppingCall(previous)
            return
        }
        // A call parked for an earlier in-app ring still fills both slots
        // until that ring is resolved; it is not a third call.
        if let twoAgo = heldCallID, twoAgo.callKitID != previous.callKitID {
            MXLog.info("A third call; ending the held one in \(twoAgo.roomID)")
            endHeldCall(twoAgo, reason: .remoteEnded)
        }
        MXLog.info("Answering a call in \(incoming.roomID) while \(previous.roomID) is live; holding the previous one")
        setHeld(previous, name: ongoingCallDisplayName)
        // "Hold & Accept" from the system UI has already sent the hold
        // action; the in-app fallback ring has not. Requesting it again is
        // idempotent on the session side.
        let hold = CXTransaction(action: CXSetHeldCallAction(call: previous.callKitID, onHold: true))
        callController.request(hold) { [weak self] error in
            guard let error else { return }
            MXLog.error("Holding the previous call failed: \(error); holding the session directly")
            // CallKit may refuse to hold a call it knows only as connecting
            // (an outgoing call parked as it goes live). The slot says held,
            // so the session must be too: a live microphone or a ringback
            // under the answer otherwise. Only while it still says so: a late
            // error must not hold a call that is active again.
            Task { @MainActor [weak self] in
                guard let self, heldCallID?.callKitID == previous.callKitID else { return }
                actionsSubject.send(.setCallHeld(true, roomID: previous.roomID))
            }
        }
    }

    /// A call whose screen is stopping is over: an answer or a promotion that
    /// would park or resume it ends it in CallKit instead, and it leaves the
    /// slots, so its screen's teardown finds it gone (review of item 8). The
    /// activation audio is left alone: it may be the answer's already.
    private func endStoppingCall(_ callID: CallID) {
        MXLog.info("The call in \(callID.roomID) is ending; ending it in CallKit rather than parking or resuming it")
        callController.request(CXTransaction(action: CXEndCallAction(call: callID.callKitID))) { error in
            if let error {
                MXLog.error("Failed transaction with error: \(error)")
            }
        }
        if ongoingCallID?.callKitID == callID.callKitID {
            ongoingCallID = nil
            ongoingCallDisplayName = nil
        }
        if heldCallID?.callKitID == callID.callKitID {
            setHeld(nil, name: nil)
        }
    }

    /// End the parked call: its screen is told, CallKit is told, the slot
    /// is cleared. The active call is untouched.
    private func endHeldCall(_ held: CallID, reason: CXCallEndedReason) {
        actionsSubject.send(.endCall(roomID: held.roomID))
        callProvider.reportCall(with: held.callKitID, endedAt: nil, reason: reason)
        setHeld(nil, name: nil)
    }

    /// The held call becomes the active one — after a swap, or because the
    /// active one ended with this one waiting behind it.
    private func promoteHeldCall(resumeThroughCallKit: Bool) {
        guard let held = heldCallID else { return }
        guard notEnding(held) != nil else {
            endStoppingCall(held)
            return
        }
        let heldName = heldCallDisplayName ?? held.ringDisplayName ?? held.roomID
        let previousActive = ongoingCallID
        let previousActiveName = ongoingCallDisplayName
        ongoingCallID = held
        ongoingCallDisplayName = heldName
        setHeld(previousActive, name: previousActiveName)
        // A swap does not park a call whose screen is stopping.
        if let previousActive, notEnding(previousActive) == nil {
            endStoppingCall(previousActive)
        }
        if resumeThroughCallKit {
            // The active call ended on its own; CallKit does not resume the
            // held one for us. Idempotent on the session side.
            let transaction = CXTransaction(action: CXSetHeldCallAction(call: held.callKitID, onHold: false))
            callController.request(transaction) { [weak self] error in
                guard let error else { return }
                MXLog.error("Resuming the held call failed: \(error); resuming the session directly")
                // CallKit refused; the session must not stay parked with no
                // control left to lift it. Only while it is still the active
                // call: a late error must not resume one parked again.
                Task { @MainActor [weak self] in
                    guard let self, ongoingCallID?.callKitID == held.callKitID, heldCallID?.callKitID != held.callKitID else { return }
                    actionsSubject.send(.setCallHeld(false, roomID: held.roomID))
                }
            }
        }
        actionsSubject.send(.activeCallChanged(roomID: held.roomID))
    }

    private let actionsSubject: PassthroughSubject<CallKitServiceAction, Never> = .init()
    var actions: AnyPublisher<CallKitServiceAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    private var declineListenerHandle: TaskHandle?

    init(callProvider: CXProviderProtocol? = nil,
         callController: CXCallControllerProtocol = CXCallController(),
         timeProvider: TimeProvider? = nil,
         audio: NativeCallAudioControlling? = nil,
         notificationCenter: UserNotificationCenterProtocol? = nil) {
        pushRegistry = PKPushRegistry(queue: nil)
        self.callController = callController
        self.notificationCenter = notificationCenter ?? (ProcessInfo.isRunningTests ? nil : UNUserNotificationCenter.current())

        self.timeProvider = timeProvider ?? TimeProvider(clock: ContinuousClock())
        // LiveKit's `AudioManager` and `AVAudioSession` are process-wide and
        // unusable in a unit-test process, so tokens there are minted against
        // nothing at all.
        self.audio = audio ?? (ProcessInfo.isRunningTests ? InertNativeCallAudioControl() : NativeCallAudioControl())

        if let callProvider {
            self.callProvider = callProvider
        } else {
            self.callProvider = CXProvider(configuration: Self.makeProviderConfiguration())
        }

        super.init()

        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]

        self.callProvider.setDelegate(self, queue: nil)
    }

    static func makeProviderConfiguration() -> CXProviderConfiguration {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.includesCallsInRecents = true
        // CallKit reads only the alpha, so this can't be `app-logo`, an opaque tile.
        configuration.iconTemplateImageData = Asset.Images.callkitLogo.image.pngData()

        // https://stackoverflow.com/a/46077628/730924
        configuration.supportedHandleTypes = [.generic]

        return configuration
    }

    func setClientProxy(_ clientProxy: any ClientProxyProtocol) {
        self.clientProxy = clientProxy

        let pending = pendingMissedCallNotifications
        pendingMissedCallNotifications = []
        for missedCall in pending {
            postMissedCallNotification(roomID: missedCall.roomID, displayName: missedCall.displayName)
        }
    }

    @discardableResult
    func setupCallSession(roomID: String, roomDisplayName: String, isVoiceCall: Bool, callKitID screenCallKitID: UUID? = nil) async -> UUID? {
        // The accepted in-app ring's screen registering; its watcher may
        // have retired the ring already (follow-up L1).
        let acceptedRing = takeAcceptedInAppRing(forRoomID: roomID)
        defer { forgetRefusal(ofUnadopted: acceptedRing) }
        // A call whose screen is stopping is not this screen's: the outgoing
        // path below replaces it.
        if let ongoingCallID = notEnding(ongoingCallID), ongoingCallID.roomID == roomID {
            ongoingCallDisplayName = roomDisplayName
            return ongoingCallID.callKitID
        }
        if let heldCallID = notEnding(heldCallID), heldCallID.roomID == roomID {
            setHeld(heldCallID, name: roomDisplayName)
            return heldCallID.callKitID
        }

        // If this starting from a ring reuse those identifiers
        // Make sure the roomID matches
        let matchingIncomingCallID: CallID? = if let incomingCallID, incomingCallID.roomID == roomID {
            incomingCallID
        } else {
            acceptedRing
        }
        // A screen opened for a call that is gone (an accept a newer one gave
        // up, question 93) registers nothing: as an outgoing call it would
        // replace the calls that are live.
        guard screenCallKitID == nil || matchingIncomingCallID != nil else {
            MXLog.info("The call the screen in \(roomID) was opened for is gone; registering nothing")
            return nil
        }

        makeRoom(for: matchingIncomingCallID, roomID: roomID)
        let callID = matchingIncomingCallID ?? CallID(callKitID: UUID(),
                                                      roomID: roomID,
                                                      rtcNotificationID: nil,
                                                      isVoiceCall: isVoiceCall,
                                                      ringDisplayName: roomDisplayName)

        // Read before the ring leaves its slot, which drops the record.
        let callKitRefusedTheRing = matchingIncomingCallID.map { ringsCallKitRefused.remove($0.callKitID) != nil } ?? false
        clearIncomingCallState(registering: matchingIncomingCallID)
        ongoingCallDisplayName = roomDisplayName
        ongoingCallID = callID

        // AGENT-PLATFORM (Brief 0063): media runs in this process, so the call
        // is a real CallKit call for its whole life. A real CallKit call is
        // also the only thing that activates the audio session, without which
        // the call connects but stays silent.
        // An answered incoming call already owns this UUID in CallKit, unless
        // CallKit refused its ring: that one is started like an outgoing call.
        guard matchingIncomingCallID == nil || callKitRefusedTheRing else {
            renameAnsweredCall(callID, roomID: roomID, roomDisplayName: roomDisplayName)
            return callID.callKitID
        }

        await startInCallKit(callID, roomID: roomID, roomDisplayName: roomDisplayName, isAnswer: matchingIncomingCallID != nil)
        parkForAcceptedRing(callID, isAnswer: matchingIncomingCallID != nil)
        return callID.callKitID
    }

    /// An outgoing call that goes live while an in-app ring of another room
    /// the user accepted still rings waits behind it, as a call live at the
    /// tap does: the accept is the user's latest tap, and the ring's screen
    /// takes over (review of 6b). The flow coordinator parks this call's
    /// screen when it presents the ring's.
    private func parkForAcceptedRing(_ callID: CallID, isAnswer: Bool) {
        guard !isAnswer, let accepted = acceptedInAppRing, accepted.roomID != callID.roomID,
              isAcceptedRingLive(forRoomID: accepted.roomID), ongoingCallID?.callKitID == callID.callKitID else { return }
        parkOngoingCall(callID, answering: accepted)
    }

    /// The slots before a registration: an answered ring parks the live call
    /// (the in-app fallback ring's was parked at the tap, Brief 0068 Slice
    /// 2, and still sits in the active slot until this registration takes it
    /// over; a ring that skipped that path is parked here), and an OUTGOING
    /// call replaces the calls that are live — the app has one active and one
    /// parked call, never a third. A ring the user accepted is not a call
    /// yet: its screen decides (review of 6b).
    private func makeRoom(for answeredRing: CallID?, roomID: String) {
        if let previous = ongoingCallID {
            if let answeredRing {
                if heldCallID?.callKitID != previous.callKitID {
                    parkOngoingCall(previous, answering: answeredRing)
                }
            } else {
                tearDownCallSession(sendEndCallAction: true, forRoomID: nil, promoteHeld: false, givingUpAcceptedRing: false)
                // Its screen comes down wherever it sits: a promotion can have
                // brought it over this one's (M1 review). This room's screen
                // is the one registering.
                if previous.roomID != roomID {
                    actionsSubject.send(.endCall(roomID: previous.roomID))
                }
            }
        } else if heldCallID != nil, answeredRing == nil {
            tearDownCallSession(sendEndCallAction: true, forRoomID: nil, promoteHeld: false, givingUpAcceptedRing: false)
        }
    }

    /// The registration's CallKit call, started: an outgoing call, or a ring
    /// CallKit refused (`isAnswer`), which rang as incoming already.
    private func startInCallKit(_ callID: CallID, roomID: String, roomDisplayName: String, isAnswer: Bool) async {
        let handle = CXHandle(type: .generic, value: roomID)
        let startCallAction = CXStartCallAction(call: callID.callKitID, handle: handle)
        // Slice 5: a video call is declared as one, so the system UI,
        // Recents and the lock screen agree with what the call is.
        startCallAction.isVideo = !callID.isVoiceCall

        do {
            try await callController.request(CXTransaction(action: startCallAction))
            let update = CXCallUpdate()
            update.hasVideo = !callID.isVoiceCall
            // A held call keeps its transport and parks the audio —
            // declaring support lets iOS drive hold for call waiting
            // instead of tearing the call down.
            update.supportsHolding = true
            update.localizedCallerName = roomDisplayName
            update.remoteHandle = handle
            callProvider.reportCall(with: callID.callKitID, updated: update)
            // The transport is up but the peer has not answered: report the
            // call as still connecting so the system timer starts on
            // `reportOutgoingCallConnected`, not now.
            callProvider.reportOutgoingCall(with: callID.callKitID, startedConnectingAt: .now)
            pendingOutgoingConnectionCallKitID = callID.callKitID
            if connectedBeforeSetupCallKitID == callID.callKitID {
                MXLog.info("The call connected while CallKit was still being set up; reporting it connected now")
                connectedBeforeSetupCallKitID = nil
                reportOutgoingCallConnected(roomID: roomID)
            }
            // An answered ring was donated as incoming when it rang.
            if !isAnswer {
                await donateCallInteraction(roomID: roomID,
                                            roomDisplayName: roomDisplayName,
                                            isVoiceCall: callID.isVoiceCall,
                                            direction: .outgoing)
            }
        } catch {
            MXLog.error("Failed requesting start call action with error: \(error)")
        }
    }

    /// The ring introduced itself as "Group — Person"; once answered the call
    /// belongs to the ROOM (the person who started it may leave while others
    /// talk). Without this the system UI kept the ring name until the first
    /// camera toggle rewrote it mid-call (critic A5).
    private func renameAnsweredCall(_ callID: CallID, roomID: String, roomDisplayName: String) {
        let update = CXCallUpdate()
        update.hasVideo = !callID.isVoiceCall
        update.supportsHolding = true
        update.localizedCallerName = roomDisplayName
        update.remoteHandle = CXHandle(type: .generic, value: roomID)
        callProvider.reportCall(with: callID.callKitID, updated: update)
    }

    func callKitID(forRoomID roomID: String) -> UUID? {
        [notEnding(ongoingCallID), notEnding(heldCallID), acceptedInAppRing].compactMap { $0 }.first { $0.roomID == roomID }?.callKitID
    }

    func markCallEnding(callKitID: UUID) {
        endingCallKitIDs.insert(callKitID)
        publishOngoingCallRoom()
    }

    func tearDownCallSession(forRoomID roomID: String?) {
        tearDownCallSession(sendEndCallAction: true, forRoomID: roomID)
    }

    func tearDownCallSession(forRoomID roomID: String, callKitID: UUID?) {
        tearDownScreensCall(forRoomID: roomID, callKitID: callKitID, promoteHeld: true)
    }

    func tearDownReplacedCallSession(forRoomID roomID: String, callKitID: UUID?) {
        tearDownScreensCall(forRoomID: roomID, callKitID: callKitID, promoteHeld: false)
    }

    private func tearDownScreensCall(forRoomID roomID: String, callKitID: UUID?, promoteHeld: Bool) {
        defer {
            if let callKitID {
                endingCallKitIDs.remove(callKitID)
            }
        }
        guard let callKitID else {
            // A call the screen started and never registered: at most a
            // registration in flight. The room's accepted ring is another
            // screen's.
            tearDownCallSession(sendEndCallAction: true, forRoomID: roomID, promoteHeld: promoteHeld, givingUpAcceptedRing: false)
            return
        }
        if acceptedInAppRing?.callKitID == callKitID {
            // The in-app answer's screen ending before it registered.
            tearDownCallSession(sendEndCallAction: true, forRoomID: roomID, promoteHeld: promoteHeld)
        } else if ongoingCallID?.callKitID == callKitID || heldCallID?.callKitID == callKitID {
            // The room's accepted ring is given up only by the screen it
            // landed on: one bound to a call that came after the accept (a
            // redial answered into the ring's screen, review of N1), once the
            // ring no longer rings. A call that was live at the accept is an
            // older screen's, whatever took the ring's slot since (a third
            // room's ring, L2 review): the ring's own screen resolves it.
            let isTheRingsScreen = !callsLiveAtAccept.contains(callKitID)
            tearDownCallSession(sendEndCallAction: true,
                                forRoomID: roomID,
                                promoteHeld: promoteHeld,
                                givingUpAcceptedRing: isTheRingsScreen && !isAcceptedRingLive(forRoomID: roomID))
        } else {
            MXLog.info("Ignoring a teardown in \(roomID): the screen's call \(callKitID) is already over")
        }
    }

    func handleInAppRingDecision(roomID: String, accepted: Bool) {
        guard let incomingCallID, incomingCallID.roomID == roomID else { return }

        if accepted {
            if let first = acceptedInAppRing, first.roomID != roomID {
                giveUpEarlierAccept(first)
            }
            // The ring stays tracked so `setupCallSession` can adopt it —
            // only the missed-call consequence is retired here.
            endUnansweredCallTask?.cancel()
            endUnansweredCallTask = nil
            // Brief 0068 Slice 2: the live call is parked NOW, synchronously
            // with the tap, so the flow coordinator finds the held slot set
            // when it presents the new screen — `setupCallSession` runs
            // seconds later, from that screen.
            callsLiveAtAccept = Set([ongoingCallID, heldCallID].compactMap { $0?.callKitID })
            if let previous = ongoingCallID, previous.roomID != roomID {
                parkOngoingCall(previous, answering: incomingCallID)
            }
            acceptedInAppRing = incomingCallID
        } else {
            // `.declinedElsewhere` is the closest CallKit vocabulary for a
            // local decline on a ring CallKit never presented; the report is
            // bookkeeping for the (failed) CallKit call, not UI.
            callProvider.reportCall(with: incomingCallID.callKitID, endedAt: nil, reason: .declinedElsewhere)
            clearIncomingCallState()
        }
    }

    /// Operator question 93: a second in-app accept, of another room, before
    /// the first one's screen registered gives the first up; the user's
    /// latest tap wins. The first ring was retired when the second replaced
    /// it, as any replaced ring is (CallKit told, its in-app ring down, no
    /// decline). What is left is its screen: it comes down, unless its room
    /// has a call of its own whose screen that would be, and its
    /// registration, should it still come, finds its call gone. A call
    /// parked at the first tap stays parked, now for the second.
    private func giveUpEarlierAccept(_ first: CallID) {
        MXLog.info("A second in-app accept gives up the first one in \(first.roomID)")
        acceptedInAppRing = nil
        ringsCallKitRefused.remove(first.callKitID)
        // A call of the room that is merely stopping has no screen to spare (L4 review).
        guard notEnding(ongoingCallID)?.roomID != first.roomID, notEnding(heldCallID)?.roomID != first.roomID else { return }
        actionsSubject.send(.endCall(roomID: first.roomID))
    }

    func isAcceptedRingLive(forRoomID roomID: String) -> Bool {
        guard let acceptedInAppRing, acceptedInAppRing.roomID == roomID else { return false }
        return incomingCallID?.callKitID == acceptedInAppRing.callKitID
    }

    func reportOutgoingCallConnected(roomID: String) {
        guard let ongoingCallID, ongoingCallID.roomID == roomID else { return }
        guard let pendingCallKitID = pendingOutgoingConnectionCallKitID,
              pendingCallKitID == ongoingCallID.callKitID else {
            // Not yet reported as connecting — the setup is still in flight
            // (or already finished and reported connected, in which case the
            // remembered id is stale and harmless: it is cleared on setup).
            connectedBeforeSetupCallKitID = ongoingCallID.callKitID
            return
        }
        connectedBeforeSetupCallKitID = nil

        callProvider.reportOutgoingCall(with: pendingCallKitID, connectedAt: .now)
        pendingOutgoingConnectionCallKitID = nil
    }

    func updateCallVideoState(hasVideo: Bool, callKitID: UUID?) {
        guard let ongoingCallID, ongoingCallID.callKitID == callKitID else { return }

        let update = CXCallUpdate()
        update.hasVideo = hasVideo
        update.supportsHolding = true
        update.localizedCallerName = ongoingCallDisplayName
        update.remoteHandle = CXHandle(type: .generic, value: ongoingCallID.roomID)
        callProvider.reportCall(with: ongoingCallID.callKitID, updated: update)
    }

    func requestAudioEnabled(_ enabled: Bool, roomID: String) async -> Bool {
        guard let ongoingCallID, ongoingCallID.roomID == roomID else {
            MXLog.info("No live CallKit call for \(roomID); the microphone change is the screen's to apply")
            return false
        }

        #if targetEnvironment(simulator)
        // The simulator's `CXSetMutedCallAction` delegate fulfils without
        // touching the media (see `provider(_:perform: CXSetMutedCallAction)`),
        // so routing through it would mute nothing.
        return false
        #else
        let transaction = CXTransaction(action: CXSetMutedCallAction(call: ongoingCallID.callKitID, muted: !enabled))
        return await withCheckedContinuation { continuation in
            callController.request(transaction) { error in
                if let error {
                    MXLog.error("CallKit refused the microphone change: \(error); applying it directly")
                }
                continuation.resume(returning: error == nil)
            }
        }
        #endif
    }

    // MARK: - PKPushRegistryDelegate

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) { }

    /// A VoIP push, validated.
    ///
    /// Extracted because `pushRegistry(_:didReceiveIncomingPushWith:for:)` grew
    /// past the point where its shape was readable: four required-field guards,
    /// four optional lookups and a routing side-effect all ran before the first
    /// decision about whether this push was even going to ring. Separating "what
    /// did we receive" from "what do we do about it" is what makes the ORDER of
    /// those decisions visible — and the order was wrong in two places.
    ///
    /// Returns `nil` when a required field is absent, logging which one.
    private struct IncomingCallPush {
        let roomID: String
        let rtcNotificationID: String
        let roomDisplayName: String?
        let isDM: Bool
        let callerID: String
        let callerDisplayName: String
        let callerAvatarData: Data?
        let isVoiceCall: Bool

        /// What the ring is called everywhere the user sees it: the person
        /// for a DM (the room name IS their name there), "Group — Person"
        /// for a group, so a group ring is recognisable as the group's
        /// before deciding whether this particular person warrants
        /// answering. The guard also swallows the no-sender-name case,
        /// where `callerDisplayName` already fell back to the room name —
        /// "Group — Group" helps nobody.
        var ringDisplayName: String {
            guard !isDM, let roomDisplayName, roomDisplayName != callerDisplayName else {
                return callerDisplayName
            }
            return "\(roomDisplayName) — \(callerDisplayName)"
        }

        /// Seconds of ring left, computed by the NSE from two SERVER timestamps
        /// so the device clock never enters it (audit W6-5-3).
        let remainingRingSeconds: Int

        init?(payload: PKPushPayload) {
            let dictionary = payload.dictionaryPayload

            guard let roomID = dictionary[CallKitNotificationKey.roomID.rawValue] as? String else {
                MXLog.error("Something went wrong, missing room identifier for incoming voip call: \(payload)")
                assertionFailure("Incoming voip push is missing the room identifier")
                return nil
            }
            guard let rtcNotificationID = dictionary[CallKitNotificationKey.rtcNotifyEventID.rawValue] as? String else {
                MXLog.error("Something went wrong, missing rtc notification event identifier for incoming voip call: \(payload)")
                assertionFailure("Incoming voip push is missing the rtc notification event identifier")
                return nil
            }
            guard let remainingRingSeconds = dictionary[CallKitNotificationKey.remainingRingSeconds.rawValue] as? Int else {
                MXLog.error("Something went wrong, missing ring duration for incoming voip call: \(payload)")
                assertionFailure("Incoming voip push is missing the ring duration")
                return nil
            }

            let roomDisplayName = dictionary[CallKitNotificationKey.roomDisplayName.rawValue] as? String

            self.roomID = roomID
            self.rtcNotificationID = rtcNotificationID
            self.remainingRingSeconds = remainingRingSeconds
            self.roomDisplayName = roomDisplayName
            // A DM when absent: the NSE ships in lockstep with the app so the
            // key is always there in practice, and the DM reading degrades to
            // the plain caller name rather than a mislabelled group.
            isDM = dictionary[CallKitNotificationKey.isDM.rawValue] as? Bool ?? true
            callerID = dictionary[CallKitNotificationKey.callerID.rawValue] as? String ?? roomID
            callerDisplayName = dictionary[CallKitNotificationKey.callerDisplayName.rawValue] as? String
                ?? roomDisplayName
                ?? roomID
            callerAvatarData = dictionary[CallKitNotificationKey.callerAvatarData.rawValue] as? Data
            isVoiceCall = dictionary[CallKitNotificationKey.isVoiceCall.rawValue] as? Bool ?? false
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard let push = IncomingCallPush(payload: payload) else {
            reportImmediatelyEndedCall(reason: .failed, completion: completion)
            return
        }

        let roomID = push.roomID
        let rtcNotificationID = push.rtcNotificationID
        let roomDisplayName = push.roomDisplayName
        let callerID = push.callerID
        let callerDisplayName = push.callerDisplayName
        let callerAvatarData = push.callerAvatarData

        // A call whose screen is stopping is no duplicate: a redial during
        // the stop rings, and an answer ends the stopping call rather than
        // parking it.
        guard notEnding(ongoingCallID)?.roomID != roomID else {
            MXLog.warning("Call already ongoing for room \(roomID), reporting the duplicate push as handled")
            reportImmediatelyEndedCall(reason: .answeredElsewhere,
                                       callerInfo: (roomID: roomID, roomDisplayName: roomDisplayName),
                                       completion: completion)
            return
        }

        // Nor is a redelivered push of a call this device has (an APNs retry,
        // the NSE run again), also when its screen is stopping (L1 review).
        if [ongoingCallID, heldCallID].contains(where: { $0?.rtcNotificationID == rtcNotificationID }) {
            MXLog.warning("Duplicate push for this device's call in room \(roomID); reporting it as handled")
            reportImmediatelyEndedCall(reason: .answeredElsewhere,
                                       callerInfo: (roomID: roomID, roomDisplayName: roomDisplayName),
                                       completion: completion)
            return
        }

        let isVoiceCall = push.isVoiceCall

        // A REDELIVERED push of the ring already on screen (APNs retry, NSE
        // re-invocation) is not a new call: without this check the C5
        // replacement below retired the LIVE ring as `.unanswered` — a
        // spurious missed-call entry — and re-rang the same call under a
        // fresh UUID (audit W6-5-1). Report the duplicate handled, exactly
        // like the ongoing-call duplicate leg above.
        if let existing = incomingCallID, existing.rtcNotificationID == rtcNotificationID {
            MXLog.warning("Duplicate push for the ring already up in room \(roomID); reporting it as handled")
            reportImmediatelyEndedCall(reason: .answeredElsewhere,
                                       callerInfo: (roomID: roomID, roomDisplayName: roomDisplayName),
                                       completion: completion)
            return
        }

        // Audit W6-5-3 — how long is LEFT, computed by the NSE from two
        // server timestamps. This used to be an absolute expiry date
        // compared against the device clock with zero tolerance, so a
        // device whose clock ran ahead of the homeserver classified every
        // incoming call as already expired: CallKit flashed and died and
        // the user saw a missed call they were never offered.
        //
        // Checked BEFORE the retire below, not after. Validating the new
        // push only once the LIVE ring had already been torn down meant a
        // stale or malformed second push killed a call the user could still
        // have answered — and then reported itself missed as well, so two
        // calls ended for the price of one bad one. Nothing may be
        // destroyed on behalf of a push that is not going to ring.
        guard push.remainingRingSeconds > 0 else {
            MXLog.warning("Call expired for room \(roomID), reporting it as missed")
            // No `clearIncomingCallState()` here (critic A7): the dedup guard
            // above already returned for a redelivery of the LIVE ring, so
            // any `incomingCallID` at this point is a DIFFERENT call the user
            // can still answer — an expired push must not destroy its timer,
            // room observer and decline listener as collateral.
            postMissedCallNotification(roomID: roomID, displayName: push.ringDisplayName)
            reportImmediatelyEndedCall(reason: .unanswered,
                                       callerInfo: (roomID: roomID, roomDisplayName: roomDisplayName),
                                       completion: completion)
            return
        }

        // AGENT-PLATFORM (Brief 0063, audit C5): a second ring while one is
        // still up used to OVERWRITE the single-slot bookkeeping — the old
        // ring's unanswered timer was reassigned without a cancel, its wake-up
        // guard then mismatched the new call, and the FIRST ring was never
        // reported ended: it rang until the user acted, and answering it
        // joined the SECOND room. Retire the old ring properly before
        // adopting the new one. (True call-waiting — both calls presented —
        // is deliberately out of scope until it can be exercised on a real
        // device; a clean "latest ring wins" is the honest single-slot
        // behaviour.)
        if let existing = incomingCallID {
            MXLog.warning("A new incoming ring for room \(roomID) replaces the active ring for room \(existing.roomID)")
            callProvider.reportCall(with: existing.callKitID, endedAt: nil, reason: .unanswered)
            actionsSubject.send(.stopInAppRinging(roomID: existing.roomID))
            // The user never acted on the retired ring — that is a missed
            // call by any honest reading, even though what killed it was
            // the next one arriving. An accepted one was answered.
            if acceptedInAppRing?.callKitID != existing.callKitID {
                postMissedCallNotification(roomID: existing.roomID, displayName: existing.ringDisplayName)
            }
            clearIncomingCallState()
        }

        // Recents routing, recorded only once this push is going to become a
        // real ring (audit follow-up). It used to run before every guard,
        // so a duplicate, an already-ongoing call or an expired push still
        // rebound `callerID -> roomID` permanently — and a later call-back
        // from Recents then opened whichever room the discarded push named.
        CallKitRoomRouting.store(roomID: roomID, for: callerID)

        let callID = CallID(callKitID: UUID(),
                            roomID: roomID,
                            rtcNotificationID: rtcNotificationID,
                            isVoiceCall: isVoiceCall,
                            ringDisplayName: push.ringDisplayName)
        incomingCallID = callID

        Task {
            // The same composed name the CallKit banner shows — a Recents row
            // saying "Tester" under a banner saying "welcome — Tester" reads
            // as two different calls (critic A5).
            await donateCallInteraction(roomID: roomID,
                                        callerID: callerID,
                                        callerDisplayName: push.ringDisplayName,
                                        callerAvatarData: callerAvatarData,
                                        isVoiceCall: isVoiceCall,
                                        direction: .incoming)
        }

        let ringDuration: Duration = .seconds(min(push.remainingRingSeconds, 90))

        let update = CXCallUpdate()
        update.hasVideo = !isVoiceCall
        // "Group — Person" for a group ring, the person for a DM. This was
        // the caller's name unconditionally, so a group call introduced
        // itself as whoever happened to start it (regression against
        // upstream, which names the banner after the room).
        update.localizedCallerName = push.ringDisplayName
        // https://stackoverflow.com/a/41230020/730924
        update.remoteHandle = .init(type: .generic, value: callerID)

        // The push registry uses the main queue so the completion is main actor bound,
        // whereas CallKit invokes its completion on a background queue.
        let mainActorCompletion = { @MainActor @Sendable in completion() }
        callProvider.reportNewIncomingCall(with: callID.callKitID, update: update) { [weak self] error in
            if let error {
                MXLog.error("Failed reporting new incoming call with error: \(error)")
            }

            Task { @MainActor in
                if error != nil {
                    self?.ringsCallKitRefused.insert(callID.callKitID)
                    // AGENT-PLATFORM (Brief 0063, G15): CallKit refused the
                    // ring — the ONE branch that raises the in-app incoming
                    // screen, so it can never race a successful system ring
                    // for the same call.
                    self?.actionsSubject.send(.startInAppRinging(roomID: roomID,
                                                                 callerDisplayName: push.ringDisplayName,
                                                                 callerAvatarData: callerAvatarData,
                                                                 isVoiceCall: isVoiceCall,
                                                                 rtcNotificationID: rtcNotificationID))
                }
                self?.actionsSubject.send(.receivedIncomingCallRequest)

                mainActorCompletion()
            }
        }

        endUnansweredCallTask = Task { [weak self] in
            try? await self?.timeProvider.clock.sleep(for: ringDuration)

            guard let self, !Task.isCancelled else {
                return
            }

            if let incomingCallID, incomingCallID.callKitID == callID.callKitID {
                callProvider.reportCall(with: incomingCallID.callKitID, endedAt: nil, reason: .unanswered)
                // `.unanswered` only writes a Recents row — CallKit never
                // raises a lock-screen banner for third-party VoIP apps, so
                // without this the user learns about the missed call only by
                // opening the room.
                postMissedCallNotification(roomID: incomingCallID.roomID,
                                           displayName: incomingCallID.ringDisplayName)
                clearIncomingCallState()
                // G15 — take the fallback ring down with the system one.
                actionsSubject.send(.stopInAppRinging(roomID: callID.roomID))
            }
        }
    }

    // MARK: - CXProviderDelegate

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MXLog.info("Call provider did activate audio session")

        // AGENT-PLATFORM (Brief 0063): the media engine is parked until this
        // point, which is what makes audio survive answering on a locked
        // device.
        isHoldingCallKitAudio = true
        audio.callKitDidActivate(audioSession)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MXLog.info("Call provider did deactivate audio session")

        // AGENT-PLATFORM (Brief 0063): deliberately NOT keyed on the live call
        // — see `isHoldingCallKitAudio`. CallKit delivers this only after the
        // end action has settled, and `tearDownCallSession` has cleared the
        // call by then, so reading the live call made the engine-parking
        // safety net a no-op in the normal ordering.
        guard isHoldingCallKitAudio else { return }

        isHoldingCallKitAudio = false
        audio.callKitDidDeactivate(audioSession)
    }

    func providerDidReset(_ provider: CXProvider) {
        MXLog.info("Call provider did reset: \(provider)")

        // Every call this provider had is gone, so nothing is left to end the
        // activation window the usual way.
        isHoldingCallKitAudio = false
        releaseCallKitActivationAudio()

        // Audit W6-6-4: the SESSION does not die with the provider — a live
        // call kept its microphone and transport running with no
        // CallKit call attached, no system mute and no system end. A reset
        // means CallKit lost the call either way, so end it honestly.
        if let ongoingCallID {
            MXLog.warning("Provider reset with a live call in \(ongoingCallID.roomID); ending it")
            actionsSubject.send(.endCall(roomID: ongoingCallID.roomID))
        }
        if let heldCallID {
            MXLog.warning("Provider reset with a held call in \(heldCallID.roomID); ending it")
            actionsSubject.send(.endCall(roomID: heldCallID.roomID))
            setHeld(nil, name: nil)
        }
        clearIncomingCallState()
        tearDownCallSession(sendEndCallAction: false, forRoomID: nil, promoteHeld: false)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // Matched by the action's OWN call UUID (audit C5): with a stale ring
        // still on screen next to a fresh one, answering the stale UI used to
        // grab whatever `incomingCallID` currently held and join the WRONG
        // room. And an unmatched action must `fail()`, not fall through — a
        // dropped action wedges the system call UI until CallKit's own
        // timeout (audit A5-3, the answer racing ring expiry).
        guard let incomingCallID, incomingCallID.callKitID == action.callUUID else {
            MXLog.error("Failed answering incoming call: the action's call \(action.callUUID) is not the live ring")
            action.fail()
            return
        }

        // The user said yes — the missed-call timer dies NOW, synchronously;
        // an answer in the ring's final second must not lose the race and
        // post a "Missed call" for a call the user had just joined (critic
        // A1/B2).
        endUnansweredCallTask?.cancel()
        endUnansweredCallTask = nil

        // CallKit activates the audio session with whatever category is set at
        // fulfil time. On a fresh launch the answer arrives before the call
        // screen configures `.playAndRecord`, CallKit skips activation entirely
        // (no `provider(_:didActivate:)`) and the call stays silent.
        isHoldingCallKitAudio = true
        claimCallKitActivationAudio()

        // First fulfil the action
        action.fulfill()

        // AGENT-PLATFORM (Brief 0063): the CallKit call stays alive for the
        // whole call — media is in this process and the audio session is its.
        // Answering while another call is live. This app has one call
        // screen, so the previous call is over — and CallKit has to be
        // told. Overwriting the slot silently left the system holding a
        // call this service no longer knew about: every later action for
        // it fell through to the untracked branch, so it could not be
        // ended, held or muted, and it stayed in the system UI until the
        // OS gave up.
        if let previous = ongoingCallID, previous.callKitID != incomingCallID.callKitID {
            parkOngoingCall(previous, answering: incomingCallID)
        }

        clearIncomingCallState()
        ongoingCallID = incomingCallID
        ongoingCallDisplayName = incomingCallID.ringDisplayName
        actionsSubject.send(.startCall(roomID: incomingCallID.roomID, isVoiceCall: incomingCallID.isVoiceCall))
    }

    // AGENT-PLATFORM (Brief 0063)
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        MXLog.info("Call provider did start outgoing call")
        // Same category-at-fulfil-time requirement as CXAnswerCallAction. An
        // action for a call we do not know leaves the latch alone — it says
        // nothing about the call that is holding the audio.
        if callID(matching: action.callUUID) != nil {
            isHoldingCallKitAudio = true
            claimCallKitActivationAudio()
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        #if targetEnvironment(simulator)
        // Like `CXEndCallAction`, this arrives unprompted on simulators. Acting
        // on it mutes the microphone, and because the call runs on a shared
        // play-and-record audio unit that also silences what we play back.
        action.fulfill()
        #else
        setMuted(action.isMuted, forCallKitID: action.callUUID) { succeeded in
            if succeeded {
                action.fulfill()
            } else {
                // Fulfilling regardless is what left the system call UI showing
                // "muted" over a live microphone.
                action.fail()
            }
        }
        #endif
    }

    /// Asks whoever owns the microphone to change it and reports back whether
    /// it actually changed.
    ///
    /// Split out of the delegate method because the simulator branch above
    /// compiles this path away in tests, and because `CXAction.isComplete`
    /// cannot tell a fulfilled action from a failed one.
    /// `callKitID` is the action's own UUID, so a mute lands on the call the
    /// system meant rather than on whatever the ongoing slot holds — muting a
    /// held call must not mute the active one. `nil` targets the live call,
    /// which is what the in-app control wants.
    func setMuted(_ muted: Bool, forCallKitID callKitID: UUID? = nil, completion: @escaping (Bool) -> Void) {
        let target = if let callKitID { callID(matching: callKitID) } else { ongoingCallID }
        guard let target else {
            // No call is carrying audio, so a mute of it is already true and
            // an unmute has nothing to start. Failing here made CallKit
            // re-issue the action every audio frame (the retry storm behind
            // the post-call crackle, 2026-09-07); there is nothing to retry.
            MXLog.info("No matching call for a CallKit mute change; fulfilling it as a no-op")
            completion(true)
            return
        }

        var timeoutTask: Task<Void, Never>?
        let reply = CallKitActionReply { succeeded in
            timeoutTask?.cancel()
            if !succeeded {
                MXLog.error("The call microphone refused a CallKit mute change")
            }
            completion(succeeded)
        }

        // A screen that never answers — dismissed mid-action, wedged media —
        // must not leave CallKit waiting. Failing is the safe default: a mute
        // we cannot prove must never be shown as done.
        timeoutTask = Task { [weak self] in
            try? await self?.timeProvider.clock.sleep(for: Self.actionReplyTimeout)
            guard !Task.isCancelled else { return }
            MXLog.error("Timed out waiting for the call microphone to answer a CallKit mute change")
            reply.send(false)
        }

        actionsSubject.send(.setAudioEnabled(!muted, roomID: target.roomID, reply: reply))
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        // Call waiting: iOS holds this call when the user answers another
        // one. The session parks the audio and keeps the transport.
        //
        // Matched by the action's own UUID, for the reason W6-5-4 gave for
        // the end action: hold is the one control that only exists BECAUSE a
        // second call does, so acting on whatever the ongoing slot happened to
        // hold meant a swap could hold the call it had just resumed.
        guard let callID = callID(matching: action.callUUID) else {
            MXLog.error("Hold action for an untracked call \(action.callUUID); fulfilling with nothing to do")
            action.fulfill()
            return
        }

        // Brief 0068 Slice 2: resuming the parked call (the system UI's
        // swap) makes it the active one; the previously active call has
        // its own hold action in the same transaction, in either order.
        if !action.isOnHold, let heldCallID, heldCallID.callKitID == action.callUUID {
            promoteHeldCall(resumeThroughCallKit: false)
        }
        actionsSubject.send(.setCallHeld(action.isOnHold, roomID: callID.roomID))
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        #if targetEnvironment(simulator)
        // This gets called for no reason on simulators, where CallKit
        // isn't even supported, ignore it.
        #else
        endCall(matching: action.callUUID)
        action.fulfill()
        #endif
    }

    /// What a CallKit end action does, split from the delegate method the way
    /// `setMuted` already is — and for a sharper reason: the delegate body is
    /// compiled out on simulators, and unit tests run on simulators, so the
    /// W6-5-4 fix in here — a P1: declining a call-waiting ring used to hang
    /// up the LIVE call — had zero regression protection. A refactor of the
    /// two-slot matching could not have failed any gate on this machine.
    ///
    /// Matched by the action's OWN call UUID (audit W6-5-4). The old handler
    /// acted on BOTH slots for every end action: declining a call-waiting
    /// ring hung up the live call, and ending the live call sent an MSC4310
    /// decline for an unrelated ring — the caller saw "declined" while the
    /// callee's phone kept ringing.
    func endCall(matching callKitID: UUID) {
        if let ongoingCallID, ongoingCallID.callKitID == callKitID {
            actionsSubject.send(.endCall(roomID: ongoingCallID.roomID))
            // Scoped to the active call: a parked one behind it comes back.
            tearDownCallSession(sendEndCallAction: false, forRoomID: ongoingCallID.roomID)
        } else if let heldCallID, heldCallID.callKitID == callKitID {
            // Ending the parked call from the system UI: the active one is
            // untouched (Brief 0068 Slice 2). CallKit already knows.
            MXLog.info("Ending the held call in \(heldCallID.roomID)")
            actionsSubject.send(.endCall(roomID: heldCallID.roomID))
            setHeld(nil, name: nil)
        } else if let incomingCallID, incomingCallID.callKitID == callKitID {
            Task {
                await sendDeclineCallEvent(incomingCallID)
            }
            clearIncomingCallState()
        } else {
            // A call this service no longer tracks (raced teardown, provider
            // reset). Nothing to act on — but the action must still settle.
            MXLog.warning("End action for an untracked call \(callKitID); fulfilling with nothing to do")
        }
    }

    // MARK: - Private

    /// The call a CallKit action refers to. Actions carry the UUID of the call
    /// they belong to, which is the only honest way to find THIS call while a
    /// ring and an ongoing call coexist.
    private func callID(matching callKitID: UUID) -> CallID? {
        if ongoingCallID?.callKitID == callKitID {
            return ongoingCallID
        }
        if heldCallID?.callKitID == callKitID {
            return heldCallID
        }
        if incomingCallID?.callKitID == callKitID {
            return incomingCallID
        }
        return nil
    }

    /// Takes the audio window a fulfilling CallKit action opens.
    ///
    /// The new claim is taken BEFORE any previous one is given back: releasing
    /// first would drop the holder count to zero between two CallKit calls and
    /// tear the audio down in the gap.
    private func claimCallKitActivationAudio() {
        let previous = callKitActivationAudioOwner
        callKitActivationAudioOwner = audio.claimActivationWindow()

        if let previous {
            audio.releaseActivationWindow(previous)
        }
    }

    /// Gives that window back. Safe to call on any path that ends a call —
    /// which is the point, because the paths that end one WITHOUT ever
    /// producing a `NativeCallSession` are exactly the ones that used to leave
    /// the process without a microphone.
    private func releaseCallKitActivationAudio() {
        guard let owner = callKitActivationAudioOwner else { return }
        callKitActivationAudioOwner = nil
        audio.releaseActivationWindow(owner)
    }

    /// Ends the ongoing CallKit call. `roomID` scopes it to one call; `nil`
    /// means "whatever is live", which is what sign-out and a provider reset
    /// want.
    ///
    /// Scoped because a replaced screen tears itself down asynchronously and
    /// slowly — an end tone, a Matrix leave and a transport disconnect, seconds
    /// in all. Answering a second call swaps the ongoing slot while the old
    /// screen is still stopping, so an unscoped teardown ended the call the
    /// user had just answered.
    ///
    /// Brief 0068 Slice 2: `roomID == nil` is UNSCOPED — sign-out, a provider
    /// reset, an outgoing call replacing everything — and ends the parked
    /// call too. A scoped teardown of the active call promotes the parked
    /// one unless `promoteHeld` says otherwise. A screen ending a call of
    /// its own leaves the room's accepted ring alone (`givingUpAcceptedRing`,
    /// follow-up N1): that ring is another screen's.
    private func tearDownCallSession(sendEndCallAction: Bool = true,
                                     forRoomID roomID: String? = nil,
                                     promoteHeld: Bool = true,
                                     givingUpAcceptedRing: Bool = true) {
        // Whatever ends here, the accepted ring of this room has no screen
        // left to register, and its ring goes with it — also when no call
        // is live to fall back to.
        let acceptedRing = givingUpAcceptedRing ? takeAcceptedInAppRing(forRoomID: roomID) : nil
        if let acceptedRing {
            forget(acceptedRing: acceptedRing)
        }
        // The parked call's screen ending itself: its CallKit call goes, the
        // active one is untouched.
        if let roomID, let heldCallID, heldCallID.roomID == roomID {
            MXLog.info("Tearing down the held call in \(roomID)")
            if sendEndCallAction {
                callController.request(CXTransaction(action: CXEndCallAction(call: heldCallID.callKitID))) { error in
                    if let error {
                        MXLog.error("Failed transaction with error: \(error)")
                    }
                }
            }
            // In the in-app ring's tap→adoption window the parked call still
            // sits in the active slot too; a dead call must not stay there
            // to be re-parked by the adoption.
            if ongoingCallID?.callKitID == heldCallID.callKitID {
                releaseCallKitActivationAudio()
                ongoingCallID = nil
                ongoingCallDisplayName = nil
            }
            setHeld(nil, name: nil)
            return
        }
        if let roomID, let ongoingCallID, ongoingCallID.roomID != roomID {
            // The accepted in-app ring's call not starting (room lookup,
            // coordinator init, the ring ending or being replaced first —
            // follow-up L1): the ring goes, and the call parked for it comes
            // back rather than staying held for nothing.
            if acceptedRing != nil {
                MXLog.info("The accepted ring in \(roomID) never started; un-parking \(ongoingCallID.roomID)")
                if let heldCallID, heldCallID.callKitID == ongoingCallID.callKitID {
                    setHeld(nil, name: nil)
                    callController.request(CXTransaction(action: CXSetHeldCallAction(call: heldCallID.callKitID, onHold: false))) { error in
                        if let error {
                            MXLog.error("Un-parking failed: \(error)")
                        }
                    }
                    // Its screen may have stayed parked for this accept,
                    // behind a screen the accept gave up.
                    actionsSubject.send(.activeCallChanged(roomID: heldCallID.roomID))
                }
                return
            }
            MXLog.info("Ignoring a teardown for \(roomID); the live call is in \(ongoingCallID.roomID)")
            return
        }
        if roomID == nil, let heldCallID {
            MXLog.info("Unscoped teardown: ending the held call in \(heldCallID.roomID) too")
            if sendEndCallAction {
                callController.request(CXTransaction(action: CXEndCallAction(call: heldCallID.callKitID))) { error in
                    if let error {
                        MXLog.error("Failed transaction with error: \(error)")
                    }
                }
            }
            actionsSubject.send(.endCall(roomID: heldCallID.roomID))
            setHeld(nil, name: nil)
        }

        if sendEndCallAction, let ongoingCallID {
            let transaction = CXTransaction(action: CXEndCallAction(call: ongoingCallID.callKitID))
            callController.request(transaction) { error in
                if let error {
                    MXLog.error("Failed transaction with error: \(error)")
                }
            }
        }

        // The session that took its own claim is gone by now (the screen tears
        // itself down first), so this is what actually returns the audio to the
        // SDK. `isHoldingCallKitAudio` deliberately survives: the
        // deactivation it is for has not been delivered yet.
        releaseCallKitActivationAudio()

        ongoingCallID = nil
        ongoingCallDisplayName = nil
        pendingOutgoingConnectionCallKitID = nil
        connectedBeforeSetupCallKitID = nil

        // The active call is gone; a parked one comes back (Brief 0068
        // Slice 2). CallKit does not resume it on its own, so we ask.
        if promoteHeld, heldCallID != nil {
            promoteHeldCall(resumeThroughCallKit: true)
        }
    }

    /// Every VoIP push must be reported to CallKit via `reportNewIncomingCall`, otherwise iOS
    /// terminates the app with `NSInternalInconsistencyException`. On early-return paths we report
    /// a call and immediately end it. `callerInfo` names the call after the room so the brief
    /// system UI and the Recents entry show the room rather than "Unknown", and the entry can be
    /// tapped to call back.
    private func reportImmediatelyEndedCall(reason: CXCallEndedReason,
                                            callerInfo: (roomID: String, roomDisplayName: String?)? = nil,
                                            completion: @escaping () -> Void) {
        let callID = UUID()
        let update = CXCallUpdate()
        update.hasVideo = false

        if let callerInfo {
            update.localizedCallerName = callerInfo.roomDisplayName
            update.remoteHandle = .init(type: .generic, value: callerInfo.roomID)
        }

        // CallKit invokes the completion on a background queue, so hop back to the main actor
        // to report the ended call and to run the (main actor bound) completion.
        let mainActorCompletion = { @MainActor @Sendable in completion() }
        callProvider.reportNewIncomingCall(with: callID, update: update) { [weak self] error in
            if let error {
                MXLog.error("Failed reporting immediately ended call with error: \(error)")
            }

            Task { @MainActor in
                self?.callProvider.reportCall(with: callID, endedAt: nil, reason: reason)
                mainActorCompletion()
            }
        }
    }

    private func sendDeclineCallEvent(_ incomingCallID: CallID) async {
        guard let rtcNotificationID = incomingCallID.rtcNotificationID else {
            MXLog.info("No rtc notification event to decline.")
            return
        }

        guard let clientProxy else {
            MXLog.warning("A ClientProxy is needed to fetch the room.")
            return
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(incomingCallID.roomID) else {
            MXLog.warning("Failed to fetch a joined room for the incoming call.")
            return
        }

        _ = await roomProxy.declineCall(notificationID: rtcNotificationID)
    }

    private func observeIncomingCall() async {
        incomingCallRoomInfoCancellable = nil

        guard let incomingCallID else {
            MXLog.info("No incoming call to observe for.")
            return
        }

        guard let clientProxy else {
            MXLog.warning("A ClientProxy is needed to fetch the room.")
            return
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(incomingCallID.roomID) else {
            MXLog.warning("Failed to fetch a joined room for the incoming call.")
            return
        }

        // AGENT-PLATFORM (Brief 0067, call audit 2026-09-05): the lookup
        // above suspends, and a NEWER ring can replace this one meanwhile
        // — with its own observers already installed. Installing this
        // ring's over them handed the newer ring's fate to the older
        // ring's room, and the older caller's hang-up then cleared the
        // newer ring's timer and decline listener while the phone was
        // still ringing for it: answering failed the UUID guard.
        guard self.incomingCallID?.callKitID == incomingCallID.callKitID else {
            MXLog.info("Ring \(incomingCallID.callKitID) was replaced while its room was being looked up; not observing it")
            return
        }

        roomProxy.subscribeToRoomInfoUpdates()

        incomingCallRoomInfoCancellable = roomProxy
            .infoPublisher
            .compactMap { ($0.hasRoomCall, $0.activeRoomCallParticipants) }
            .removeDuplicates { $0 == $1 }
            .drop { hasRoomCall, _ in
                // Filter all updates before hasRoomCall becomes `true`. Then we can correctly
                // detect its change to `false` to stop ringing when the caller hangs up.
                !hasRoomCall
            }
            .sink { [weak self] hasOngoingCall, activeRoomCallParticipants in
                guard let self else { return }

                let participants: [String] = activeRoomCallParticipants

                if !hasOngoingCall {
                    MXLog.info("Call cancelled by remote")
                    reportEndedCall(incomingCallID: incomingCallID, reason: .remoteEnded)
                } else if participants.contains(roomProxy.ownUserID) {
                    if hasEndingCall(inRoomID: incomingCallID.roomID) {
                        // While this device's call in the room is ending, its
                        // own membership lingers until the leave syncs back:
                        // only another of the user's devices answers.
                        Task { [weak self] in await self?.endRingIfAnotherDeviceAnswered(incomingCallID, in: roomProxy) }
                    } else {
                        MXLog.info("Call answered elsewhere")
                        reportEndedCall(incomingCallID: incomingCallID, reason: .answeredElsewhere)
                    }
                }
            }

        guard let rtcNotificationID = incomingCallID.rtcNotificationID else {
            MXLog.warning("Decline: No RTC notification ID found for the incoming call.")
            return
        }

        MXLog.info("Observe decline events for notification \(rtcNotificationID)")

        let listener: CallDeclineListener = SDKListener.onMainActor { [weak self] senderID in
            guard let self else { return }

            MXLog.debug("Call declined event received from \(senderID)")

            if senderID == roomProxy.ownUserID {
                // Stop ringing!
                MXLog.debug("Call declined elsewhere")
                reportEndedCall(incomingCallID: incomingCallID, reason: .declinedElsewhere)
            }
        }

        guard case let .success(handle) = roomProxy.subscribeToCallDeclineEvents(rtcNotificationEventID: rtcNotificationID, listener: listener) else {
            MXLog.error("Unable to listen for decline events.")
            return
        }

        declineListenerHandle = handle
    }

    /// The room's call has a membership of the user's from another device.
    /// This device's own, which lingers while its call there ends, is told
    /// apart by its device ID, not by the user's (residual of the redial round).
    private func endRingIfAnotherDeviceAnswered(_ incomingCallID: CallID, in roomProxy: JoinedRoomProxyProtocol) async {
        guard let ownDeviceID = clientProxy?.deviceID,
              case let .success(session) = roomProxy.matrixRTCSession(),
              case let .success(memberships) = await session.memberships(),
              memberships.contains(where: { $0.userID == roomProxy.ownUserID && $0.deviceID != ownDeviceID }) else { return }
        // The read suspends: the ring may have been answered here, or replaced.
        guard self.incomingCallID?.callKitID == incomingCallID.callKitID else { return }
        MXLog.info("Call answered on another device")
        reportEndedCall(incomingCallID: incomingCallID, reason: .answeredElsewhere)
    }

    private func reportEndedCall(incomingCallID: CallID, reason: CXCallEndedReason) {
        callProvider.reportCall(with: incomingCallID.callKitID, endedAt: nil, reason: reason)
        // Only the ring that still owns the incoming slot may clear it: a
        // late callback for a ring that was already replaced reports its own
        // CallKit call ended (above) and touches nothing else.
        guard self.incomingCallID?.callKitID == incomingCallID.callKitID else {
            MXLog.info("Ring \(incomingCallID.callKitID) ended after being replaced; the live ring is untouched")
            return
        }
        // Only the caller hanging up mid-ring is a missed call. Answered or
        // declined elsewhere means the user already dealt with it on another
        // device — notifying would nag about a decision they made. Neither
        // is a ring the user accepted here.
        if reason == .remoteEnded, acceptedInAppRing?.callKitID != incomingCallID.callKitID {
            postMissedCallNotification(roomID: incomingCallID.roomID,
                                       displayName: incomingCallID.ringDisplayName)
        }
        clearIncomingCallState()
        // G15 — when CallKit refused the ring, the in-app fallback screen is
        // ringing instead; every cancellation (remote hang-up, answered or
        // declined elsewhere) must take it down too, or it rings forever.
        actionsSubject.send(.stopInAppRinging(roomID: incomingCallID.roomID))
    }

    /// The lock-screen "Missed call from X" that CallKit will never post on
    /// its own: `.unanswered` writes to the Phone app's Recents and nothing
    /// else, which is why WhatsApp and Telegram post their own notification —
    /// and why until now our callee learnt about a missed call only by
    /// opening the room and finding the timeline tile.
    ///
    /// Tapping it routes to the room through the same userInfo keys the
    /// NSE's message notifications carry.
    private func postMissedCallNotification(roomID: String, displayName: String?) {
        guard let notificationCenter, let displayName else { return }

        // No session yet (cold launch, expired push beat the restore): park
        // it. Posting now would stamp no `receiver_id` and the tap would be
        // a silent no-op (critic A4).
        guard let clientProxy else {
            pendingMissedCallNotifications.append((roomID: roomID, displayName: displayName))
            return
        }

        // Brief 0068 Slice 3: a ring that died while another Spiral call was
        // live is a different fact from one nobody was there for — the
        // notification says so, so the user knows why they never heard it.
        let wasInAnotherCall = ongoingCallID != nil && ongoingCallID?.roomID != roomID
        let content = UNMutableNotificationContent()
        content.title = displayName
        content.body = wasInAnotherCall
            ? UntranslatedL10n.notificationMissedCallWhileInCall
            : UntranslatedL10n.notificationMissedCall
        content.sound = .default
        content.threadIdentifier = roomID
        content.categoryIdentifier = NotificationConstants.Category.message
        content.userInfo = [NotificationConstants.UserInfoKey.roomIdentifier: roomID,
                            NotificationConstants.UserInfoKey.receiverIdentifier: clientProxy.userID]

        let request = UNNotificationRequest(identifier: "missed-call-\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)
        Task {
            do {
                try await notificationCenter.add(request)
            } catch {
                MXLog.error("Failed posting the missed-call notification: \(error)")
            }
        }
    }

    private func donateCallInteraction(roomID: String,
                                       roomDisplayName: String,
                                       isVoiceCall: Bool,
                                       direction: INInteractionDirection) async {
        await donateCallInteraction(roomID: roomID,
                                    callerID: roomID,
                                    callerDisplayName: roomDisplayName,
                                    callerAvatarData: nil,
                                    isVoiceCall: isVoiceCall,
                                    direction: direction)
    }

    private func donateCallInteraction(roomID: String,
                                       callerID: String,
                                       callerDisplayName: String,
                                       callerAvatarData: Data?,
                                       isVoiceCall: Bool,
                                       direction: INInteractionDirection) async {
        guard !ProcessInfo.isRunningTests else { return }

        let image = (callerAvatarData ?? Avatars.generatePlaceholderAvatarImageData(name: callerDisplayName,
                                                                                    id: callerID,
                                                                                    size: .init(width: 100, height: 100)))
            .map(INImage.init(imageData:))
        let handle = INPersonHandle(value: callerID, type: .unknown)
        let person = INPerson(personHandle: handle,
                              nameComponents: nil,
                              displayName: callerDisplayName,
                              image: image,
                              contactIdentifier: nil,
                              customIdentifier: roomID)
        let intent = INStartCallIntent(callRecordFilter: nil,
                                       callRecordToCallBack: nil,
                                       audioRoute: .unknown,
                                       destinationType: .normal,
                                       contacts: [person],
                                       callCapability: isVoiceCall ? .audioCall : .videoCall)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = direction

        do {
            try await interaction.donate()
        } catch {
            MXLog.error("Failed donating call interaction: \(error)")
        }
    }

    /// A registration's ring leaves the ring slot; a ring for another room,
    /// up while a retired accepted ring is adopted, keeps ringing. An
    /// outgoing call (`nil`) ends the ring in the slot as the user's decline,
    /// unless the user accepted it.
    private func clearIncomingCallState(registering callID: CallID?) {
        guard callID == nil || incomingCallID?.callKitID == callID?.callKitID else { return }
        if callID == nil, let ring = incomingCallID {
            // A ring the user accepted rings on: its screen decides.
            guard ring.callKitID != acceptedInAppRing?.callKitID else { return }
            declineForOutgoingCall(ring)
        }
        clearIncomingCallState()
        // Follow-up N3: a ring adopted without an accept — its room's call
        // started another way — still shows in the app, haptic included.
        if let callID {
            actionsSubject.send(.stopInAppRinging(roomID: callID.roomID))
        }
    }

    /// Earlier follow-up 6b: the user calls out instead of answering, so the
    /// ring ends as their decline. Clearing it silently left a CallKit banner
    /// with nothing behind it (answering failed the UUID guard, ending it
    /// declined nothing) and an in-app ring ringing. Not a missed call.
    private func declineForOutgoingCall(_ ring: CallID) {
        MXLog.info("An outgoing call replaces the ring in \(ring.roomID); declining it")
        callProvider.reportCall(with: ring.callKitID, endedAt: nil, reason: .declinedElsewhere)
        actionsSubject.send(.stopInAppRinging(roomID: ring.roomID))
        Task {
            await sendDeclineCallEvent(ring)
        }
    }

    /// Cancels every subscription and task tied to a ringing incoming call and nils `incomingCallID`.
    /// Call this on every path that ends the incoming-call state (answered, declined, timed out,
    /// cancelled by remote, answered/declined elsewhere) so that follow-up calls to the same room
    /// start from a clean slate and the SDK decline-listener subscription doesn't leak.
    private func clearIncomingCallState() {
        if let incomingCallID, incomingCallID.callKitID != acceptedInAppRing?.callKitID {
            ringsCallKitRefused.remove(incomingCallID.callKitID)
        }
        endUnansweredCallTask?.cancel()
        endUnansweredCallTask = nil
        declineListenerHandle?.cancel()
        declineListenerHandle = nil
        incomingCallRoomInfoCancellable = nil
        incomingCallID = nil
    }
}
