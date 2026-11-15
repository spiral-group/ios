//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). `FeedServiceProtocol` over the generated
// client: the four read routes of lane B1a, the problem types mapped into
// `FeedError`, and the first page of Latest kept on disk for the offline state.
//

import AgentPlatformClient
import Combine
import Foundation
import HTTPTypes
import OpenAPIRuntime

final class FeedService: FeedServiceProtocol {
    let client: AgentPlatformClient
    private let firstPageCache: FeedFirstPageCache?
    let draftStore: FeedDraftStore?
    /// The app's language, sent with Latest and an author's posts: an official post with translations is shown in it.
    /// Explicit, as the ephemeral session would send the device's language list, or nothing.
    private let language: String?

    /// The last unread count the server gave (lane I3); `nil` until a read answers.
    let noticesUnreadSubject = CurrentValueSubject<Int?, Never>(nil)
    /// The last unread activity the server gave (lane I5): a page or the seen mark; `nil` until one has.
    let activityUnreadSubject = CurrentValueSubject<Int?, Never>(nil)

    /// - Parameter cacheDirectory: the session's cache directory, deleted with
    ///   the session at sign-out; `nil` keeps nothing on disk.
    /// - Parameter language: the reader's language, the app's own unless a test says otherwise.
    init(client: AgentPlatformClient, cacheDirectory: URL?, language: String? = FeedAppLanguage.current) {
        self.client = client
        self.language = language
        firstPageCache = cacheDirectory.map(FeedFirstPageCache.init(directory:))
        draftStore = cacheDirectory.map(FeedDraftStore.init(directory:))
    }

    func latest(cursor: String?, limit: Int) async -> Result<FeedPage, FeedError> {
        let result = await withUnauthorizedRetry { [client, language] () async throws -> Result<FeedPage, FeedError> in
            let output = try await client.underlying.getLatest(.init(query: .init(cursor: cursor, limit: Int32(limit)),
                                                                     headers: .init(acceptLanguage: language)))
            switch output {
            case .ok(let ok):
                return try .success(Self.page(ok.body.json))
            case .badRequest(let bad):
                return .failure(cursor == nil ? .server(status: 400) : Self.invalidCursorOr(try? bad.body.applicationProblemJson))
            case .unauthorized:
                return .failure(.unauthorized)
            case .tooManyRequests(let tooMany):
                return .failure(Self.error(status: 429, problem: try? tooMany.body.applicationProblemJson, retryAfter: tooMany.headers.retryAfter))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(FeedError(status: 503, problemType: (try? unavailable.body.applicationProblemJson)?._type, retryAfterSeconds: unavailable.headers.retryAfter))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }

        if cursor == nil, case .success(let page) = result {
            firstPageCache?.store(page)
        }
        return result
    }

    func post(id: String) async -> Result<FeedPost, FeedError> {
        await withUnauthorizedRetry { [client] in
            let output = try await client.underlying.getPost(.init(path: .init(postId: id)))
            switch output {
            case .ok(let ok):
                return try .success(Self.post(ok.body.json))
            case .notFound(let notFound):
                return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
            case .badRequest:
                // Not a post id at all: nothing is there under it.
                return .failure(.notFound)
            case .unauthorized:
                return .failure(.unauthorized)
            case .tooManyRequests(let tooMany):
                return .failure(Self.error(status: 429, problem: try? tooMany.body.applicationProblemJson, retryAfter: tooMany.headers.retryAfter))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(FeedError(status: 503, problemType: (try? unavailable.body.applicationProblemJson)?._type, retryAfterSeconds: unavailable.headers.retryAfter))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }
    }

    func authorPosts(userID: String, cursor: String?, limit: Int) async -> Result<FeedPage, FeedError> {
        await withUnauthorizedRetry { [client, language] in
            let output = try await client.underlying.listAuthorPosts(.init(path: .init(mxid: userID),
                                                                           query: .init(cursor: cursor, limit: Int32(limit)),
                                                                           headers: .init(acceptLanguage: language)))
            switch output {
            case .ok(let ok):
                return try .success(Self.page(ok.body.json))
            case .notFound(let notFound):
                return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
            case .badRequest(let bad):
                return .failure(cursor == nil ? .notFound : Self.invalidCursorOr(try? bad.body.applicationProblemJson))
            case .unauthorized:
                return .failure(.unauthorized)
            case .tooManyRequests(let tooMany):
                return .failure(Self.error(status: 429, problem: try? tooMany.body.applicationProblemJson, retryAfter: tooMany.headers.retryAfter))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(FeedError(status: 503, problemType: (try? unavailable.body.applicationProblemJson)?._type, retryAfterSeconds: unavailable.headers.retryAfter))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }
    }

    func cachedFirstPage() -> FeedPage? {
        firstPageCache?.load()
    }

    // MARK: - Private

    /// One replay after a 401, as `AgentPlatformService` does: the SDK may be
    /// landing a refreshed token. Anything thrown is a transport failure.
    func withUnauthorizedRetry<Value>(_ operation: () async throws -> Result<Value, FeedError>) async -> Result<Value, FeedError> {
        do {
            let first = try await operation()
            guard case .failure(.unauthorized) = first else { return first }
            try? await Task.sleep(for: AgentPlatformService.unauthorizedRetryDelay)
            return try await operation()
        } catch {
            MXLog.error("Feed request failed in transport: \(type(of: error))")
            return .failure(.transport)
        }
    }

    /// Only the feed's own 404 is final. The router's fallback is a backend
    /// without the feed (`.unavailable`); any other (a proxy) is a failure with a Retry.
    nonisolated static func notFoundOrServer(_ problem: Components.Schemas.ProblemDetails?) -> FeedError {
        switch problem?._type {
        case FeedError.notFoundType: .notFound
        case FeedError.routeNotFoundType: .unavailable
        default: .server(status: 404)
        }
    }

    /// An answer the spec does not list for the route (the router's fallback
    /// 404 on every feed path of a backend without the feed): still read by its problem type.
    static func error(status: Int, payload: UndocumentedPayload) async -> FeedError {
        var problem: UndocumentedProblem?
        if let body = payload.body, let data = try? await Data(collecting: body, upTo: 64 * 1024) {
            problem = try? JSONDecoder().decode(UndocumentedProblem.self, from: data)
        }
        let retryAfter = payload.headerFields[.retryAfter].flatMap { Int64($0) }
        return FeedError(status: status, problemType: problem?.type, retryAfterSeconds: retryAfter, rulesVersion: problem?.rulesVersion)
    }

    private struct UndocumentedProblem: Decodable {
        let type: String?
        let rulesVersion: String?

        enum CodingKeys: String, CodingKey {
            case type
            case rulesVersion = "rules_version"
        }
    }

    /// A 400 on a request with a cursor: the cursor is old or malformed, unless the problem says otherwise.
    nonisolated static func invalidCursorOr(_ problem: Components.Schemas.ProblemDetails?) -> FeedError {
        guard let type = problem?._type, type != "/errors/validation-failed" else { return .invalidCursor }
        return FeedError(status: 400, problemType: type)
    }

    // MARK: - Mapping

    nonisolated static func page(_ wire: Components.Schemas.FeedPage) -> FeedPage {
        FeedPage(items: wire.items.map(post), nextCursor: wire.nextCursor, pinned: wire.pinned.map(post))
    }

    nonisolated static func post(_ wire: Components.Schemas.FeedPost) -> FeedPost {
        let state = FeedPostState(wireValue: wire.state)
        return FeedPost(id: wire.id.lowercased(),
                        createdAt: wire.createdAt,
                        author: author(wire.author),
                        content: FeedContent(kind: FeedContentKind(wireValue: wire.content.kind),
                                             text: wire.content.text,
                                             media: wire.content.media.map(media),
                                             isSensitive: wire.content.sensitive),
                        counts: FeedCounts(likes: Int(wire.counts.likes),
                                           comments: Int(wire.counts.comments),
                                           shares: Int(wire.counts.shares)),
                        viewer: FeedViewer(liked: wire.viewer.liked,
                                           hidden: wire.viewer.hidden,
                                           isAuthor: wire.viewer.isAuthor),
                        state: state,
                        heldReason: state == .held ? wire.heldReason.map(FeedHeldReason.init(wireValue:)) : nil,
                        commentsEnabled: wire.commentsEnabled)
    }

    /// A withheld name comes without one; a bio sent with it is left out all the same.
    nonisolated static func author(_ wire: Components.Schemas.FeedAuthor) -> FeedAuthor {
        let isNameWithheld = wire.nameWithheld ?? false
        return FeedAuthor(userID: wire.mxid,
                          name: isNameWithheld ? nil : wire.name,
                          avatarURL: wire.avatarMxc.flatMap(URL.init(string:)),
                          bio: isNameWithheld ? nil : wire.bio,
                          isOfficial: wire.official,
                          isNameWithheld: isNameWithheld)
    }

    private nonisolated static func media(_ wire: Components.Schemas.FeedMediaRef) -> FeedMediaRef {
        FeedMediaRef(id: wire.id,
                     mxcURL: URL(string: wire.mxc),
                     mimeType: wire.mime,
                     width: Int(wire.width),
                     height: Int(wire.height),
                     blurhash: wire.blurhash,
                     altText: wire.alt)
    }
}

/// The first page of Latest as last read, one JSON file in the session's
/// cache directory, which sign-out deletes. A file that does not decode (an
/// older build wrote it) is not a page: `load` answers `nil`.
nonisolated struct FeedFirstPageCache {
    let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appending(component: "spiral-feed-latest.json")
    }

    func store(_ page: FeedPage) {
        do {
            let data = try JSONEncoder().encode(page)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            MXLog.error("Failed to keep the feed's first page: \(type(of: error))")
        }
    }

    func load() -> FeedPage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(FeedPage.self, from: data)
    }
}
