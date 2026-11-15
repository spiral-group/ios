//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I3 on B3's contract: like, hide,
// the comments, the author's comment switch and the share. Every route
// checks the post first, so only the feed's own `404` is "not there"; any
// other `404` or a `400` is a server failure with a Retry. A change is sent
// to the lists only once the server has made it.
//

import AgentPlatformClient
import Foundation

extension FeedService {
    func setLiked(_ liked: Bool, postID: String) async -> Result<FeedLikes, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<FeedLikes, FeedError> in
            if liked {
                switch try await client.underlying.putLike(.init(path: .init(postId: postID))) {
                case .ok(let ok):
                    return try .success(Self.likes(ok.body.json))
                case .badRequest:
                    return .failure(.server(status: 400))
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
            } else {
                switch try await client.underlying.deleteLike(.init(path: .init(postId: postID))) {
                case .ok(let ok):
                    return try .success(Self.likes(ok.body.json))
                case .badRequest:
                    return .failure(.server(status: 400))
                case .unauthorized:
                    return .failure(.unauthorized)
                case .notFound(let notFound):
                    return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
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

        return result
    }

    func setHidden(_ hidden: Bool, postID: String) async -> Result<Void, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<Void, FeedError> in
            if hidden {
                switch try await client.underlying.putHide(.init(path: .init(postId: postID))) {
                case .noContent:
                    return .success(())
                case .badRequest:
                    return .failure(.server(status: 400))
                case .unauthorized:
                    return .failure(.unauthorized)
                case .notFound(let notFound):
                    return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
                case .internalServerError:
                    return .failure(.server(status: 500))
                case .serviceUnavailable(let unavailable):
                    return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson))
                case .undocumented(let status, let payload):
                    return await .failure(Self.error(status: status, payload: payload))
                }
            } else {
                switch try await client.underlying.deleteHide(.init(path: .init(postId: postID))) {
                case .noContent:
                    return .success(())
                case .badRequest:
                    return .failure(.server(status: 400))
                case .unauthorized:
                    return .failure(.unauthorized)
                case .notFound(let notFound):
                    return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
                case .internalServerError:
                    return .failure(.server(status: 500))
                case .serviceUnavailable(let unavailable):
                    return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson))
                case .undocumented(let status, let payload):
                    return await .failure(Self.error(status: status, payload: payload))
                }
            }
        }

        if case .success = result {
            MXLog.info("\(hidden ? "Hid" : "Showed again") feed post \(postID)")
        }
        return result
    }

    func comments(postID: String, cursor: String?, limit: Int) async -> Result<FeedCommentPage, FeedError> {
        await withUnauthorizedRetry { [client] in
            let output = try await client.underlying.getComments(.init(path: .init(postId: postID),
                                                                       query: .init(cursor: cursor, limit: Int32(limit))))
            switch output {
            case .ok(let ok):
                return try .success(Self.commentPage(ok.body.json))
            case .badRequest(let bad):
                return .failure(cursor == nil ? .server(status: 400) : Self.invalidCursorOr(try? bad.body.applicationProblemJson))
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

    func createComment(postID: String, text: String, replyTo: String?, idempotencyKey: UUID) async -> Result<FeedComment, FeedError> {
        let body = Components.Schemas.CreateFeedCommentRequest(idempotencyKey: idempotencyKey.uuidString.lowercased(),
                                                               replyTo: replyTo,
                                                               text: text)
        // A replay after a 401 carries the same key, so it can only answer the comment it made.
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<FeedComment, FeedError> in
            let output = try await client.underlying.postComment(.init(path: .init(postId: postID), body: .json(body)))
            switch output {
            case .created(let created):
                return try .success(Self.comment(created.body.json))
            case .ok(let replayed):
                return try .success(Self.comment(replayed.body.json))
            case .badRequest(let bad):
                return .failure(Self.error(status: 400, problem: try? bad.body.applicationProblemJson))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden(let forbidden):
                return .failure(Self.error(status: 403, problem: try? forbidden.body.applicationProblemJson))
            case .notFound(let notFound):
                return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
            case .conflict(let conflict):
                return .failure(Self.error(status: 409, problem: try? conflict.body.applicationProblemJson))
            case .unsupportedMediaType:
                return .failure(.server(status: 415))
            case .unprocessableContent(let unprocessable):
                return .failure(Self.error(status: 422, problem: try? unprocessable.body.applicationProblemJson))
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
        if case .success(let comment) = result {
            MXLog.info("Commented \(comment.id) on feed post \(postID) (\(comment.state))")
            if comment.state == .held || comment.isSensitive {
                await readUnreadNoticesAfterTheFilter()
            }
        }
        return result
    }

    func deleteComment(id: String) async -> Result<Void, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<Void, FeedError> in
            switch try await client.underlying.deleteComment(.init(path: .init(commentId: id))) {
            case .noContent:
                return .success(())
            case .badRequest:
                return .failure(.server(status: 400))
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound(let notFound):
                return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }
        if case .success = result {
            MXLog.info("Deleted feed comment \(id)")
        }
        return result
    }

    func setCommentsEnabled(_ enabled: Bool, postID: String) async -> Result<FeedPost, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<FeedPost, FeedError> in
            let output = try await client.underlying.patchPost(.init(path: .init(postId: postID),
                                                                     body: .json(.init(commentsEnabled: enabled))))
            switch output {
            case .ok(let ok):
                return try .success(Self.post(ok.body.json))
            case .badRequest:
                return .failure(.server(status: 400))
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound(let notFound):
                return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
            case .unsupportedMediaType:
                return .failure(.server(status: 415))
            case .unprocessableContent:
                return .failure(.server(status: 422))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson, retryAfter: unavailable.headers.retryAfter))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }
        if case .success(let post) = result {
            MXLog.info("Turned comments \(post.commentsEnabled ? "on" : "off") on feed post \(postID)")
        }
        return result
    }

    func share(postID: String, roomID: String, language: String?) async -> Result<FeedShareMessage, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<FeedShareMessage, FeedError> in
            let output = try await client.underlying.postShare(.init(path: .init(postId: postID),
                                                                     body: .json(.init(lang: language, roomId: roomID))))
            switch output {
            case .ok(let ok):
                return try .success(Self.share(ok.body.json))
            case .badRequest:
                return .failure(.server(status: 400))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden(let forbidden):
                return .failure(Self.error(status: 403, problem: try? forbidden.body.applicationProblemJson))
            case .notFound(let notFound):
                return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
            case .unsupportedMediaType:
                return .failure(.server(status: 415))
            case .unprocessableContent(let unprocessable):
                return .failure(Self.error(status: 422, problem: try? unprocessable.body.applicationProblemJson))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson, retryAfter: unavailable.headers.retryAfter))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }
        if case .success = result {
            MXLog.info("Shared feed post \(postID) into \(roomID)")
        }
        return result
    }

    // MARK: - Mapping

    private nonisolated static func likes(_ wire: Components.Schemas.FeedLikes) -> FeedLikes {
        FeedLikes(likes: Int(wire.likes), liked: wire.liked)
    }

    private nonisolated static func share(_ wire: Components.Schemas.FeedShare) -> FeedShareMessage {
        FeedShareMessage(body: wire.content.body, shares: Int(wire.shares))
    }

    nonisolated static func commentPage(_ wire: Components.Schemas.FeedCommentPage) -> FeedCommentPage {
        FeedCommentPage(items: wire.items.map(comment), nextCursor: wire.nextCursor)
    }

    nonisolated static func comment(_ wire: Components.Schemas.FeedComment) -> FeedComment {
        let state = FeedCommentState(wireValue: wire.state)
        return FeedComment(id: wire.id.lowercased(),
                           postID: wire.postId.lowercased(),
                           author: author(wire.author),
                           text: wire.text,
                           replyTo: wire.replyTo.map { FeedCommentReply(id: $0.id.lowercased(), author: author($0.author)) },
                           createdAt: wire.createdAt,
                           state: state,
                           heldReason: state == .held ? wire.heldReason.map(FeedHeldReason.init(wireValue:)) : nil,
                           isAuthor: wire.viewer.isAuthor,
                           canDelete: wire.viewer.canDelete,
                           isSensitive: wire.sensitive ?? false)
    }
}
