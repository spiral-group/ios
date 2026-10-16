//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066 § 5.87): a post's actions, when encryption
// refuses them for a verified user's devices or identity.
//
// One question per room, not one per tap. A game sends an action per move
// and a live post one a second; every one of them is refused for the same
// reason until the user answers, so the first refusal asks and the rest
// wait for that answer — then go out, each with the `seq` it was given (the
// fold orders by the room and counts seqs for completeness, so the order the
// waiters wake in does not matter). «Not now» fails them all, and each post
// takes its own optimistic move back.
//
// Only where a timeline can show the sheet: the room and its threads. A
// timeline that drops `displayResolveSendFailure` (pinned events, media)
// passes no refusals, and its posts fail as before rather than wait for an
// answer nobody is asked for.
//

import Foundation

final class SpiralAppSendRefusals {
    private let roomProxy: JoinedRoomProxyProtocol
    private let present: (TimelineItemSendFailure.VerifiedUser, VerifiedUserSendFailureResolver) -> Void
    /// The question on screen, if any: resolves `true` when the user agreed
    /// and the first refused action went out.
    private var asking: Task<Bool, Never>?

    init(roomProxy: JoinedRoomProxyProtocol,
         present: @escaping (TimelineItemSendFailure.VerifiedUser, VerifiedUserSendFailureResolver) -> Void) {
        self.roomProxy = roomProxy
        self.present = present
    }

    func send(_ attempt: @escaping () async -> Result<Void, RoomProxyError>) async -> Result<Void, RoomProxyError> {
        let first = await attempt()
        guard case .failure(.verifiedUser(let failure)) = first else { return first }

        if let asking {
            return await asking.value ? await attempt() : first
        }

        let resolution = RawSendResolution(roomProxy: roomProxy, attempt: attempt)
        let present = present
        let question = Task { @MainActor in
            present(failure, resolution.resolver)
            return await resolution.outcome() != nil
        }
        asking = question
        let agreed = await question.value
        asking = nil
        return agreed ? .success(()) : first
    }
}
