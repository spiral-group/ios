//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I5 on B6's contract (decision 287):
// the person's activity and its seen mark, who liked a post and the push
// settings per kind. The badge's activity count moves only on a server
// answer (a page, the seen mark); a failed
// read leaves it as it was. Logs carry ids and counts, never names or text.
//

import AgentPlatformClient
import Combine
import Foundation
import OpenAPIRuntime

extension FeedService {
    // MARK: - Activity

    func activity(cursor: String?, limit: Int) async -> Result<FeedActivityPage, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<FeedActivityPage, FeedError> in
            switch try await client.underlying.getActivity(.init(query: .init(cursor: cursor, limit: Int32(limit)))) {
            case .ok(let ok):
                return try .success(Self.activityPage(ok.body.json))
            case .badRequest(let bad):
                return .failure(cursor == nil ? .server(status: 400) : Self.invalidCursorOr(try? bad.body.applicationProblemJson))
            case .unauthorized:
                return .failure(.unauthorized)
            case .tooManyRequests(let tooMany):
                return .failure(Self.error(status: 429, problem: try? tooMany.body.applicationProblemJson, retryAfter: tooMany.headers.retryAfter))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson, retryAfter: unavailable.headers.retryAfter))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }
        if case .success(let page) = result {
            activityUnreadSubject.send(page.unread)
        }
        return result
    }

    func markActivitySeen(upTo date: Date?) async -> Result<Int, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<Int, FeedError> in
            switch try await client.underlying.postActivitySeen(.init(body: .json(.init(at: date)))) {
            case .ok(let ok):
                return try .success(Int(ok.body.json.unread))
            case .badRequest:
                return .failure(.server(status: 400))
            case .unauthorized:
                return .failure(.unauthorized)
            case .unsupportedMediaType:
                return .failure(.server(status: 415))
            case .unprocessableContent:
                return .failure(.server(status: 422))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }
        switch result {
        case .success(let unread):
            activityUnreadSubject.send(unread)
        case .failure(let error):
            MXLog.error("Failed to mark the feed activity seen: \(error)")
        }
        return result
    }

    var activityUnreadPublisher: AnyPublisher<Int, Never> {
        activityUnreadSubject.compactMap(\.self).eraseToAnyPublisher()
    }

    // MARK: - Who liked

    func likers(postID: String, cursor: String?, limit: Int) async -> Result<FeedLikersPage, FeedError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.getLikes(.init(path: .init(postId: postID), query: .init(cursor: cursor, limit: Int32(limit)))) {
            case .ok(let ok):
                let wire = try ok.body.json
                return .success(FeedLikersPage(items: wire.items.map { FeedLiker(author: Self.author($0.author), likedAt: $0.likedAt) },
                                               nextCursor: wire.nextCursor))
            case .badRequest(let bad):
                return .failure(cursor == nil ? .notFound : Self.invalidCursorOr(try? bad.body.applicationProblemJson))
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound(let notFound):
                return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
            case .tooManyRequests(let tooMany):
                return .failure(Self.error(status: 429, problem: try? tooMany.body.applicationProblemJson, retryAfter: tooMany.headers.retryAfter))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson, retryAfter: unavailable.headers.retryAfter))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }
    }

    // MARK: - Push settings

    func notificationSettings() async -> Result<FeedNotificationSettings, FeedError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.getNotificationSettings() {
            case .ok(let ok):
                return try .success(Self.settings(ok.body.json))
            case .unauthorized:
                return .failure(.unauthorized)
            case .tooManyRequests(let tooMany):
                return .failure(Self.error(status: 429, problem: try? tooMany.body.applicationProblemJson, retryAfter: tooMany.headers.retryAfter))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }
    }

    func setNotificationSettings(_ settings: FeedNotificationSettings) async -> Result<FeedNotificationSettings, FeedError> {
        let body = Components.Schemas.FeedNotificationSettings(comments: settings.comments.wireValue,
                                                               likes: settings.likes.wireValue,
                                                               replies: settings.replies.wireValue)
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<FeedNotificationSettings, FeedError> in
            switch try await client.underlying.putNotificationSettings(.init(body: .json(body))) {
            case .ok(let ok):
                return try .success(Self.settings(ok.body.json))
            case .badRequest:
                return .failure(.server(status: 400))
            case .unauthorized:
                return .failure(.unauthorized)
            case .unsupportedMediaType:
                return .failure(.server(status: 415))
            case .unprocessableContent:
                return .failure(.server(status: 422))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }
        switch result {
        case .success(let stored):
            MXLog.info("Feed pushes: likes \(stored.likes.wireValue), comments \(stored.comments.wireValue), replies \(stored.replies.wireValue)")
        case .failure(let error):
            MXLog.error("Failed to change the feed's push settings: \(error)")
        }
        return result
    }

    // MARK: - Mapping

    nonisolated static func activityPage(_ wire: Components.Schemas.FeedActivityPage) -> FeedActivityPage {
        FeedActivityPage(items: wire.items.compactMap(activityEntry), nextCursor: wire.nextCursor, unread: Int(wire.unread),
                         newestAt: wire.items.map(\.at).max())
    }

    /// `nil` for a kind newer than this build, which the list skips (decision 96), or an entry with nobody in it.
    nonisolated static func activityEntry(_ wire: Components.Schemas.FeedActivityEntry) -> FeedActivityEntry? {
        guard let kind = FeedActivityKind(wireValue: wire.kind), !wire.actors.isEmpty else { return nil }
        return FeedActivityEntry(id: wire.id,
                                 kind: kind,
                                 at: wire.at,
                                 postID: wire.postId.lowercased(),
                                 commentID: wire.commentId?.lowercased(),
                                 actors: wire.actors.map(author),
                                 total: max(Int(wire.total), wire.actors.count),
                                 preview: wire.preview,
                                 postPreview: wire.postPreview,
                                 isSensitive: wire.sensitive,
                                 isUnread: wire.unread)
    }

    private nonisolated static func settings(_ wire: Components.Schemas.FeedNotificationSettings) -> FeedNotificationSettings {
        FeedNotificationSettings(likes: FeedPushAudience(wireValue: wire.likes),
                                 comments: FeedPushAudience(wireValue: wire.comments),
                                 replies: FeedPushAudience(wireValue: wire.replies))
    }
}
