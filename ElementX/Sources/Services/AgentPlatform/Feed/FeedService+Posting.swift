//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I2 on B1b's contract: text
// posting, the rules accept, the composer's standing, the author's delete,
// the author's own posts and the composer's draft. A refusal is told apart
// by its problem `type` (`docs/API.md` § "Problem types of the feed"), the
// status only when the type says nothing the feed knows.
//

import AgentPlatformClient
import Foundation
import HTTPTypes
import OpenAPIRuntime

extension FeedService {
    func ownPosts(cursor: String?, limit: Int) async -> Result<FeedPage, FeedError> {
        await withUnauthorizedRetry { [client] in
            let output = try await client.underlying.listOwnPosts(.init(query: .init(cursor: cursor, limit: Int32(limit))))
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
    }

    func createPost(text: String, idempotencyKey: UUID) async -> Result<FeedPost, FeedError> {
        let body = Components.Schemas.CreateFeedPostRequest(content: .init(kind: "text", mediaIds: [], text: text),
                                                            idempotencyKey: idempotencyKey.uuidString.lowercased())
        // A replay after a 401 carries the same key, so it can only answer the post it made.
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<FeedPost, FeedError> in
            let output = try await client.underlying.createPost(.init(body: .json(body)))
            switch output {
            case .created(let created):
                return try .success(Self.post(created.body.json))
            case .ok(let replayed):
                return try .success(Self.post(replayed.body.json))
            case .badRequest(let bad):
                return .failure(Self.error(status: 400, problem: try? bad.body.applicationProblemJson))
            case .unauthorized:
                return .failure(.unauthorized)
            case .forbidden(let forbidden):
                return .failure(Self.error(status: 403, problem: try? forbidden.body.applicationProblemJson))
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
                return .failure(FeedError(status: 503, problemType: (try? unavailable.body.applicationProblemJson)?._type, retryAfterSeconds: unavailable.headers.retryAfter))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }

        switch result {
        case .success(let post):
            MXLog.info("Published feed post \(post.id) (\(post.state))")
            if post.state == .held || post.content.isSensitive {
                await readUnreadNoticesAfterTheFilter()
            }
        case .failure:
            break
        }
        return result
    }

    func deletePost(id: String) async -> Result<Void, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<Void, FeedError> in
            let output = try await client.underlying.deletePost(.init(path: .init(postId: id)))
            switch output {
            case .noContent:
                return .success(())
            case .notFound(let notFound):
                return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
            case .badRequest:
                // An id that does not parse: nothing was deleted.
                return .failure(.server(status: 400))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable(let unavailable):
                return .failure(FeedError(status: 503, problemType: (try? unavailable.body.applicationProblemJson)?._type))
            case .undocumented(let status, let payload):
                return await .failure(Self.error(status: status, payload: payload))
            }
        }

        switch result {
        case .success, .failure(.notFound):
            // The feed's own 404 is "no post of yours with this id": it is gone either way.
            MXLog.info("Deleted feed post \(id)")
        case .failure:
            break
        }
        return result
    }

    func standing() async -> Result<FeedStanding, FeedError> {
        await withUnauthorizedRetry { [client] in
            let output = try await client.underlying.getStanding(.init())
            switch output {
            case .ok(let ok):
                return try .success(Self.standing(ok.body.json))
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

    func acceptRules(version: String) async -> Result<FeedStanding, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<FeedStanding, FeedError> in
            let output = try await client.underlying.acceptRules(.init(body: .json(.init(version: version))))
            switch output {
            case .ok(let ok):
                return try .success(Self.standing(ok.body.json))
            case .badRequest:
                return .failure(.server(status: 400))
            case .unauthorized:
                return .failure(.unauthorized)
            case .conflict(let conflict):
                return .failure(Self.error(status: 409, problem: try? conflict.body.applicationProblemJson))
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
        if case .success = result {
            MXLog.info("Accepted the feed rules \(version)")
        }
        return result
    }

    // MARK: - Draft

    func draft() -> FeedDraft? {
        draftStore?.load()
    }

    func saveDraft(_ draft: FeedDraft) {
        draftStore?.store(draft)
    }

    func deleteDraft() {
        draftStore?.delete()
    }

    /// Decision 278: what the filter holds or marks at publish gets a notice at
    /// once, which is not pushed (the author is in the app): the badge is read again.
    func readUnreadNoticesAfterTheFilter() async {
        if case .failure(let error) = await notices(cursor: nil, limit: 1, language: nil) {
            MXLog.info("Could not read the feed notices' unread count after a filtered publish: \(error)")
        }
    }

    // MARK: - Private

    static func error(status: Int, problem: Components.Schemas.ProblemDetails?, retryAfter: Int64? = nil) -> FeedError {
        FeedError(status: status, problemType: problem?._type, retryAfterSeconds: retryAfter, rulesVersion: problem?.rulesVersion)
    }

    private nonisolated static func standing(_ wire: Components.Schemas.FeedStanding) -> FeedStanding {
        FeedStanding(rulesVersion: wire.rulesVersion,
                     rulesAccepted: wire.rulesAccepted,
                     postsPerDay: wire.postsPerDay.map(Int.init),
                     postsToday: Int(wire.postsToday),
                     suspendedUntil: wire.suspendedUntil,
                     commentsPerDay: wire.commentsPerDay.map(Int.init),
                     commentsToday: wire.commentsToday.map(Int.init))
    }
}

/// The composer's draft, one JSON file in the session's cache directory,
/// which sign-out deletes. Readable only while the device is unlocked.
nonisolated struct FeedDraftStore {
    let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appending(component: "spiral-feed-draft.json")
    }

    func store(_ draft: FeedDraft) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(draft)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            MXLog.error("Failed to keep the feed draft: \(type(of: error))")
        }
    }

    func load() -> FeedDraft? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(FeedDraft.self, from: data)
    }

    func delete() {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch CocoaError.fileNoSuchFile {
            // Nothing was kept.
        } catch {
            MXLog.error("Failed to delete the feed draft: \(type(of: error))")
        }
    }
}
