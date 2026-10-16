//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066 § 5.87): what the resolve screen does with the
// user's answer, for a send that went through the send queue AND for one
// that did not.
//
// Encryption refuses to share a room key when a VERIFIED user — the sender
// included — has a device they never signed, or when a user this device had
// verified now has a new identity. Upstream offers to put that right only
// for an item in the send queue: the item wedges, the timeline shows it, a
// tap opens `ResolveVerifiedUserSendFailureScreen`. Interactive Posts send
// raw — the thread's root, a published post, a move in a game — because they
// need the event id back or are not timeline items at all, so the same
// refusal reached the user as «Sorry, an error occurred» with nothing to do
// about it (prod, 2026-10-02: one unsigned device of the user's own made
// every Interactive Post send fail).
//
// Two resolvers, one screen:
// - `sendQueue`: upstream's behaviour unchanged — every answer ignores or
//   withdraws for the WHOLE failure and asks the queue to resend.
// - `RawSendResolution`: every answer resolves THAT user only, and the send
//   is made once, after the last user is answered. A raw send has no queue
//   item to resend idempotently; sending after each answer would repeat the
//   event once it went through.
//

import Foundation

struct VerifiedUserSendFailureResolver: Hashable {
    /// The room whose members the screen names.
    let roomProxy: JoinedRoomProxyProtocol
    /// The user agreed for `current` — one user's part of `failure`.
    /// `isLast`: nobody else in `failure` is still to be asked.
    let resolve: (_ current: TimelineItemSendFailure.VerifiedUser,
                  _ failure: TimelineItemSendFailure.VerifiedUser,
                  _ isLast: Bool) async -> Result<Void, Error>
    /// «Retry»: send again, changing nothing.
    let resend: () async -> Result<Void, Error>
    /// The sheet went away, however it went.
    let finished: () -> Void

    private let id = UUID()

    init(roomProxy: JoinedRoomProxyProtocol,
         resolve: @escaping (TimelineItemSendFailure.VerifiedUser, TimelineItemSendFailure.VerifiedUser, Bool) async -> Result<Void, Error>,
         resend: @escaping () async -> Result<Void, Error>,
         finished: @escaping () -> Void = { }) {
        self.roomProxy = roomProxy
        self.resolve = resolve
        self.resend = resend
        self.finished = finished
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// A send-queue item: upstream's semantics, unchanged.
    static func sendQueue(sendHandle: SendHandleProxy, roomProxy: JoinedRoomProxyProtocol) -> Self {
        .init(roomProxy: roomProxy,
              resolve: { _, failure, _ in
                  let result = switch failure {
                  case .hasUnsignedDevice(let devices):
                      await roomProxy.ignoreDeviceTrustAndResend(devices: devices, sendHandle: sendHandle)
                  case .changedIdentity(let users):
                      await roomProxy.withdrawVerificationAndResend(userIDs: users, sendHandle: sendHandle)
                  }
                  return result.mapError { $0 }
              },
              resend: {
                  await sendHandle.resend().mapError { $0 }
              })
    }
}

/// A raw send that encryption refused for a verified user, waiting for the
/// user to say whether to send anyway.
final class RawSendResolution<Value: Sendable> {
    private let roomProxy: JoinedRoomProxyProtocol
    private let attempt: () async -> Result<Value, RoomProxyError>
    private var value: Value?
    private var isFinished = false
    private var waiting: [CheckedContinuation<Value?, Never>] = []

    init(roomProxy: JoinedRoomProxyProtocol, attempt: @escaping () async -> Result<Value, RoomProxyError>) {
        self.roomProxy = roomProxy
        self.attempt = attempt
    }

    /// Built on demand rather than stored: the resolver holds this object,
    /// and holding the resolver back would keep both alive for ever.
    var resolver: VerifiedUserSendFailureResolver {
        .init(roomProxy: roomProxy,
              resolve: { current, _, isLast in await self.resolve(current, isLast: isLast) },
              resend: { await self.send() },
              finished: { self.finish() })
    }

    /// What the send produced, once the screen is gone: the value when it
    /// went through, `nil` when the user cancelled or it failed again.
    func outcome() async -> Value? {
        if isFinished { return value }
        return await withCheckedContinuation { waiting.append($0) }
    }

    /// Send with `attempt`; when encryption refuses a verified user's devices
    /// or identity, `present` the resolve screen and wait for the user.
    static func send(roomProxy: JoinedRoomProxyProtocol,
                     present: (TimelineItemSendFailure.VerifiedUser, VerifiedUserSendFailureResolver) -> Void,
                     attempt: @escaping () async -> Result<Value, RoomProxyError>) async -> Result<Value, RoomProxyError> {
        let first = await attempt()
        guard case .failure(.verifiedUser(let failure)) = first else { return first }

        MXLog.info("[SpiralApp] a raw send was refused for \(failure.affectedUserIDs); asking the user")
        let resolution = RawSendResolution(roomProxy: roomProxy, attempt: attempt)
        present(failure, resolution.resolver)
        guard let value = await resolution.outcome() else { return first }
        return .success(value)
    }

    // MARK: - Private

    private func resolve(_ current: TimelineItemSendFailure.VerifiedUser, isLast: Bool) async -> Result<Void, Error> {
        let result = switch current {
        case .hasUnsignedDevice(let devices):
            await roomProxy.ignoreDeviceTrust(devices: devices)
        case .changedIdentity(let users):
            await roomProxy.withdrawVerification(userIDs: users)
        }
        if case .failure(let error) = result { return .failure(error) }
        return isLast ? await send() : .success(())
    }

    private func send() async -> Result<Void, Error> {
        switch await attempt() {
        case .success(let value):
            self.value = value
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        let waiting = waiting
        self.waiting = []
        waiting.forEach { $0.resume(returning: value) }
    }
}
