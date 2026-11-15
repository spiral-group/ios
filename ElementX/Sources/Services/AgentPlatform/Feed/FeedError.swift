//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The feed's failures, told apart by the
// problem `type` the platform stamps on them (`docs/API.md` § "Problem types
// of the feed"). Read routes send the first four today; the write-side types
// are mapped here too, so I2–I4 branch on the same enum.
//

import Foundation

nonisolated enum FeedError: Error, Equatable, CustomStringConvertible {
    /// 404 `/errors/feed-not-found`: the post or author is not there for the caller. Final.
    case notFound
    /// 503 `/errors/feed-unavailable`: `FEED_MODE=off`; also the router's
    /// 404 `/errors/not-found`, a backend without the feed's routes (a rollback).
    case unavailable
    /// 503 `/errors/feed-read-only`: nothing was posted.
    case readOnly
    /// 503 `/errors/feed-temporarily-unavailable`: the authors could not be read; retry after
    /// `retryAfterSeconds`, the server's `Retry-After` (`nil` when it sent none).
    case temporarilyUnavailable(retryAfterSeconds: Int?)
    /// 400 on a cursor: start again from the first page.
    case invalidCursor
    /// 409 `/errors/feed-rules-not-accepted`: accept the rules first.
    /// `currentVersion` is the server's `rules_version`, `nil` when it sent none.
    case rulesNotAccepted(currentVersion: String?)
    /// 409 `/errors/feed-duplicate`.
    case duplicate
    /// 422 `/errors/feed-link-refused`.
    case linkRefused
    /// 422 `/errors/feed-media-refused`.
    case mediaRefused
    /// 422 `/errors/idempotency-key-reused`.
    case idempotencyKeyReused
    /// 403 `/errors/feed-suspended`: no posts, comments or reports (decision 276); reads go on.
    case suspended
    /// 429 `/errors/too-many-requests`: on a write, a burst window or a daily cap
    /// (nothing was posted); on a read, the per-account read window (lane B5).
    /// `retryAfterSeconds` is the server's `Retry-After`, `nil` when it sent none.
    case rateLimited(retryAfterSeconds: Int?)
    /// 503 `/errors/feed-media-check-unavailable`: nothing was stored.
    case mediaCheckUnavailable
    /// 422 `/errors/feed-share-bridged-room` (D-P12): Spiral chats only; nothing was recorded.
    case shareBridgedRoom
    /// 422 `/errors/unprocessable-entity`: on a comment, its `reply_to` is not one the person may see.
    case unprocessable
    case unauthorized
    case forbidden
    /// Any other answer, kept with its status so it is never read as "no posts".
    case server(status: Int)
    /// No answer at all: offline, DNS, TLS, or a body that did not decode.
    case transport

    static let notFoundType = "/errors/feed-not-found"
    static let unavailableType = "/errors/feed-unavailable"
    /// The router's fallback for a path it does not serve.
    static let routeNotFoundType = "/errors/not-found"
    static let readOnlyType = "/errors/feed-read-only"
    static let temporarilyUnavailableType = "/errors/feed-temporarily-unavailable"
    static let rulesNotAcceptedType = "/errors/feed-rules-not-accepted"
    static let duplicateType = "/errors/feed-duplicate"
    static let linkRefusedType = "/errors/feed-link-refused"
    static let mediaRefusedType = "/errors/feed-media-refused"
    static let idempotencyKeyReusedType = "/errors/idempotency-key-reused"
    static let suspendedType = "/errors/feed-suspended"
    static let tooManyRequestsType = "/errors/too-many-requests"
    static let mediaCheckUnavailableType = "/errors/feed-media-check-unavailable"
    static let shareBridgedRoomType = "/errors/feed-share-bridged-room"
    static let unprocessableType = "/errors/unprocessable-entity"

    /// The one mapping from an HTTP answer to a feed failure: the problem
    /// `type` first, the status only when the type says nothing the feed knows.
    init(status: Int, problemType: String?, retryAfterSeconds: Int64? = nil, rulesVersion: String? = nil) {
        switch problemType {
        case Self.notFoundType: self = .notFound
        case Self.unavailableType: self = .unavailable
        case Self.routeNotFoundType where status == 404: self = .unavailable
        case Self.readOnlyType: self = .readOnly
        case Self.temporarilyUnavailableType: self = .temporarilyUnavailable(retryAfterSeconds: retryAfterSeconds.map { Int(clamping: $0) })
        case Self.rulesNotAcceptedType: self = .rulesNotAccepted(currentVersion: rulesVersion)
        case Self.duplicateType: self = .duplicate
        case Self.linkRefusedType: self = .linkRefused
        case Self.mediaRefusedType: self = .mediaRefused
        case Self.idempotencyKeyReusedType: self = .idempotencyKeyReused
        case Self.suspendedType: self = .suspended
        case Self.tooManyRequestsType: self = .rateLimited(retryAfterSeconds: retryAfterSeconds.map { Int(clamping: $0) })
        case Self.mediaCheckUnavailableType: self = .mediaCheckUnavailable
        case Self.shareBridgedRoomType: self = .shareBridgedRoom
        case Self.unprocessableType: self = .unprocessable
        default:
            switch status {
            case 401: self = .unauthorized
            case 403: self = .forbidden
            case 429: self = .rateLimited(retryAfterSeconds: retryAfterSeconds.map { Int(clamping: $0) })
            default: self = .server(status: status)
            }
        }
    }

    var description: String {
        switch self {
        case .notFound: "not found"
        case .unavailable: "feed off"
        case .readOnly: "feed read-only"
        case .temporarilyUnavailable(let seconds): "temporarily unavailable, retry after \(seconds.map(String.init) ?? "-") s"
        case .invalidCursor: "invalid cursor"
        case .rulesNotAccepted(let version): "rules not accepted, current \(version ?? "-")"
        case .duplicate: "duplicate"
        case .linkRefused: "link refused"
        case .mediaRefused: "media refused"
        case .idempotencyKeyReused: "idempotency key reused"
        case .suspended: "suspended"
        case .rateLimited(let seconds): "rate limited, retry after \(seconds.map(String.init) ?? "-") s"
        case .mediaCheckUnavailable: "media check unavailable"
        case .shareBridgedRoom: "share into a bridged room"
        case .unprocessable: "unprocessable"
        case .unauthorized: "unauthorized"
        case .forbidden: "forbidden"
        case .server(let status): "server \(status)"
        case .transport: "transport"
        }
    }
}

/// Lane B5's per-account read window: every feed `GET` counts toward 30 per
/// 10 s, and the 31st is `429` with `Retry-After`. A read the person did not
/// ask for (a screen opening, a poll, the next page as it scrolls in) waits
/// that long and reads once more; one they asked for (pull to refresh, Retry)
/// says "slow down" instead. Either way what is on screen stays, and a refusal
/// is never shown as "empty" or "not available".
enum FeedReadWindow {
    /// The server's `Retry-After`, capped so a large value never leaves a
    /// screen waiting; 5 s, the feed's usual answer, when it sent none.
    static func delay(retryAfterSeconds: Int?) -> Duration {
        guard let retryAfterSeconds, retryAfterSeconds >= 0 else { return .seconds(5) }
        return .seconds(min(retryAfterSeconds, 30))
    }

    /// A read nobody asked for: over the window, once more after `Retry-After`.
    static func retryingOnce<Value>(_ read: () async -> Result<Value, FeedError>) async -> Result<Value, FeedError> {
        let first = await read()
        guard case .failure(.rateLimited(let retryAfterSeconds)) = first else { return first }
        try? await Task.sleep(for: delay(retryAfterSeconds: retryAfterSeconds))
        return await read()
    }

    /// A read the person asked for, over the window.
    static func showSlowDown(_ userIndicatorController: UserIndicatorControllerProtocol) {
        userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedSlowDown, icon: \.time))
    }
}

extension FeedError {
    /// `429`: over a window or a cap; on a read, the read window.
    var isRateLimited: Bool {
        if case .rateLimited = self { true } else { false }
    }
}

extension Result where Failure == FeedError {
    var isRateLimited: Bool {
        if case .failure(let error) = self { error.isRateLimited } else { false }
    }
}
