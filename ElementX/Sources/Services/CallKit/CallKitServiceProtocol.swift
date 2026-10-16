//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

/// A one-shot answer from whoever owns the media, so a CallKit action can be
/// completed on the RESULT of the change rather than on the request.
///
/// A refused mute MUST fail its action: the system call UI showing "muted"
/// over a microphone that is still publishing is a privacy defect, not a
/// cosmetic one.
final class CallKitActionReply {
    private var handler: ((Bool) -> Void)?

    init(_ handler: @escaping (Bool) -> Void) {
        self.handler = handler
    }

    /// Only the first answer counts — CallKit refuses a second completion for
    /// the same action, and the first answer is the one the engine gave.
    func send(_ succeeded: Bool) {
        guard let handler else { return }
        self.handler = nil
        handler(succeeded)
    }
}

enum CallKitServiceAction {
    case receivedIncomingCallRequest
    case startCall(roomID: String, isVoiceCall: Bool)
    case endCall(roomID: String)
    /// The receiver owns the microphone and must answer through `reply`,
    /// whether or not the change took effect.
    case setAudioEnabled(_ enabled: Bool, roomID: String, reply: CallKitActionReply)
    /// CallKit held or resumed the call (call waiting, the system UI's
    /// hold button).
    case setCallHeld(_ isHeld: Bool, roomID: String)
    // AGENT-PLATFORM (Brief 0063, G15): CallKit could not present the ring
    // (`reportNewIncomingCall` failed — build/region without CallKit). The
    // in-app incoming screen is the fallback with the same accept/decline
    // semantics; it must never fire alongside a successful CallKit ring.
    case startInAppRinging(roomID: String, callerDisplayName: String, callerAvatarData: Data?, isVoiceCall: Bool, rtcNotificationID: String?)
    /// The fallback ring is over (expired or answered elsewhere).
    case stopInAppRinging(roomID: String)
    /// Brief 0068 Slice 2 — call waiting: the ACTIVE call changed hands
    /// between two live Spiral calls (a swap, or the active one ending
    /// with a held one behind it). The flow coordinator brings this
    /// room's screen forward; the other call's screen stays alive, held.
    case activeCallChanged(roomID: String)
}

/// Brief 0068 Slice 2: the second Spiral call, parked behind the active
/// one. What the active screen shows in its "on hold" pill.
struct CallKitHeldCall: Equatable {
    let roomID: String
    let displayName: String
}

// sourcery: AutoMockable
// AGENT-PLATFORM (Brief 0067): upstream's `ElementCallServiceProtocol`, renamed (ADR-0079).
protocol CallKitServiceProtocol {
    var actions: AnyPublisher<CallKitServiceAction, Never> { get }
    
    var ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never> { get }

    /// Brief 0068 Slice 2: the held Spiral call behind the active one, if any.
    var heldCallPublisher: CurrentValuePublisher<CallKitHeldCall?, Never> { get }

    /// Brief 0068 Slice 2: hold the active call and resume the held one, as
    /// one CallKit transaction so the system UI and Recents agree.
    func swapCalls()
    
    func setClientProxy(_ clientProxy: ClientProxyProtocol)
    
    /// `isVoiceCall` decides the CallKit metadata: a video call must be
    /// reported as one or the system UI, Recents and the lock screen all
    /// describe it wrongly. `callKitID` is the call the screen was opened
    /// for (`callKitID(forRoomID:)`), `nil` for a call it starts. Returns the
    /// CallKit call the screen registered, which is what it tears down by, or
    /// `nil` when the call it was opened for is gone: then it registers
    /// nothing.
    @discardableResult
    func setupCallSession(roomID: String, roomDisplayName: String, isVoiceCall: Bool, callKitID: UUID?) async -> UUID?

    /// The CallKit call a call screen for `roomID` is opened for: the room's
    /// live or held call, else the in-app ring the user accepted for it.
    /// `nil` for a call that starts here, until `setupCallSession`
    /// registers it.
    func callKitID(forRoomID roomID: String) -> UUID?

    /// Marks the ringing outgoing CallKit call as answered so the system call
    /// timer starts.
    func reportOutgoingCallConnected(roomID: String)

    /// Keep CallKit metadata aligned when camera video starts or stops mid-call.
    /// `callKitID` is the screen's call: a stopping screen of the room must
    /// not rewrite a newer call's state (L3 review).
    func updateCallVideoState(hasVideo: Bool, callKitID: UUID?)
    
    /// Gives up the call of `roomID` — and the in-app ring accepted for it —
    /// for a call that never got a screen: the room not joined, the
    /// accepted ring gone, the screen failing to build. `nil` ends whatever
    /// is live, which is what signing out wants. A screen ends its own call
    /// with `tearDownCallSession(forRoomID:callKitID:)`.
    func tearDownCallSession(forRoomID roomID: String?)

    /// A call screen's stop has begun. Its call is over for the app at once:
    /// the room no longer shows it as ongoing, and a new screen of the room
    /// neither takes it for its own nor registers onto it. CallKit keeps it
    /// until the screen's teardown lands, seconds later.
    func markCallEnding(callKitID: UUID)
    
    /// A call screen ending its own call: `callKitID` is the one it was
    /// opened for or registered, `nil` when it never had one.
    ///
    /// A screen stops asynchronously — an end tone, a Matrix leave, a
    /// transport disconnect, seconds in all — and by then its room may have
    /// a newer call, a redial the user accepted in the meantime. A teardown
    /// by room took that call (follow-up N1); this one ends only the
    /// screen's own, and nothing once it is over.
    func tearDownCallSession(forRoomID roomID: String, callKitID: UUID?)

    /// A screen that shows its call's end, replaced by a fresh screen of its
    /// room (M1 review): its call ends now, scoped like the screen's own
    /// teardown, which then finds it gone. The parked call stays parked: the
    /// fresh screen's registration settles it as it would with any live
    /// call, an answer keeping it behind, an outgoing call replacing it.
    func tearDownReplacedCallSession(forRoomID roomID: String, callKitID: UUID?)

    /// AGENT-PLATFORM (Brief 0067, call audit 2026-09-05): the in-app mute
    /// button asks CallKit to carry the change so the system UI, Recents
    /// and the call's own state never disagree — sync used to be one-way,
    /// CallKit → app, and "mute in the system UI, unmute in-app" left a
    /// live microphone under a CallKit call that said muted.
    ///
    /// Returns `true` when CallKit accepted the transaction: the change
    /// arrives as `.setAudioEnabled` through `actions`, and the caller must
    /// NOT apply it itself. `false` means CallKit will not carry it — no
    /// live CallKit call for this room, a refused transaction, or the
    /// simulator, whose `CXSetMutedCallAction` never reaches the media —
    /// and the caller applies the change directly.
    func requestAudioEnabled(_ enabled: Bool, roomID: String) async -> Bool
    
    /// The user decided on the IN-APP fallback ring (the one that exists only
    /// when CallKit refused the system ring). Must be called synchronously
    /// with the tap: the accept path takes seconds to reach
    /// `setupCallSession` (room lookup, screen presentation) and the decline
    /// path used to rely on the MSC4310 decline event echoing back — either
    /// gap let the unanswered timer post a "Missed call" over an explicit
    /// decision the user already made.
    func handleInAppRingDecision(roomID: String, accepted: Bool)
    
    /// Whether the in-app ring the user accepted for `roomID` — that ring,
    /// not any ring of the room — is still up: false once its caller hung
    /// up, another device answered or declined it, or a newer ring replaced
    /// it. What the in-app answer re-checks before it presents a screen
    /// (follow-up L1). Not a lifetime: once the screen joins, our own
    /// membership echoes back as "answered elsewhere" and retires the ring
    /// before `setupCallSession` registers the call.
    func isAcceptedRingLive(forRoomID roomID: String) -> Bool
}
