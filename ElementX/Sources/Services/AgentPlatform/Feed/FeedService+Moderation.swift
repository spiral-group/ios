//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I3 on B4's contract: reports and
// their receipt, and the notices with the unread count. Only the feed's own `404` is "not there"; any
// other `404` or a `400` is a server failure. Logs carry ids and counts,
// never a report's text or a notice's statement.
//

import AgentPlatformClient
import Combine
import Foundation

extension FeedService {
    // MARK: - Reports

    func report(_ target: FeedReportTarget, reason: FeedReportReason, detail: String?) async -> Result<FeedReportReceipt, FeedError> {
        let body = Components.Schemas.FeedReportRequest(detail: detail, reason: reason.rawValue)
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<FeedReportReceipt, FeedError> in
            switch target {
            case .post(let id):
                switch try await client.underlying.reportPost(.init(path: .init(postId: id), body: .json(body))) {
                case .created(let created): return try .success(Self.receipt(created.body.json, isExisting: false))
                case .ok(let existing): return try .success(Self.receipt(existing.body.json, isExisting: true))
                case .badRequest(let bad): return .failure(Self.error(status: 400, problem: try? bad.body.applicationProblemJson))
                case .unauthorized: return .failure(.unauthorized)
                case .forbidden(let forbidden): return .failure(Self.error(status: 403, problem: try? forbidden.body.applicationProblemJson))
                case .notFound(let notFound): return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
                case .unsupportedMediaType: return .failure(.server(status: 415))
                case .unprocessableContent: return .failure(.server(status: 422))
                case .tooManyRequests(let tooMany):
                    return .failure(Self.error(status: 429, problem: try? tooMany.body.applicationProblemJson, retryAfter: tooMany.headers.retryAfter))
                case .internalServerError: return .failure(.server(status: 500))
                case .serviceUnavailable(let unavailable):
                    return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson, retryAfter: unavailable.headers.retryAfter))
                case .undocumented(let status, let payload): return await .failure(Self.error(status: status, payload: payload))
                }
            case .comment(let id):
                switch try await client.underlying.reportComment(.init(path: .init(commentId: id), body: .json(body))) {
                case .created(let created): return try .success(Self.receipt(created.body.json, isExisting: false))
                case .ok(let existing): return try .success(Self.receipt(existing.body.json, isExisting: true))
                case .badRequest(let bad): return .failure(Self.error(status: 400, problem: try? bad.body.applicationProblemJson))
                case .unauthorized: return .failure(.unauthorized)
                case .forbidden(let forbidden): return .failure(Self.error(status: 403, problem: try? forbidden.body.applicationProblemJson))
                case .notFound(let notFound): return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
                case .unsupportedMediaType: return .failure(.server(status: 415))
                case .unprocessableContent: return .failure(.server(status: 422))
                case .tooManyRequests(let tooMany):
                    return .failure(Self.error(status: 429, problem: try? tooMany.body.applicationProblemJson, retryAfter: tooMany.headers.retryAfter))
                case .internalServerError: return .failure(.server(status: 500))
                case .serviceUnavailable(let unavailable):
                    return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson, retryAfter: unavailable.headers.retryAfter))
                case .undocumented(let status, let payload): return await .failure(Self.error(status: status, payload: payload))
                }
            case .author(let userID):
                switch try await client.underlying.reportAuthor(.init(path: .init(mxid: userID), body: .json(body))) {
                case .created(let created): return try .success(Self.receipt(created.body.json, isExisting: false))
                case .ok(let existing): return try .success(Self.receipt(existing.body.json, isExisting: true))
                case .badRequest(let bad): return .failure(Self.error(status: 400, problem: try? bad.body.applicationProblemJson))
                case .unauthorized: return .failure(.unauthorized)
                case .forbidden(let forbidden): return .failure(Self.error(status: 403, problem: try? forbidden.body.applicationProblemJson))
                case .notFound(let notFound): return .failure(Self.notFoundOrServer(try? notFound.body.applicationProblemJson))
                case .unsupportedMediaType: return .failure(.server(status: 415))
                case .unprocessableContent: return .failure(.server(status: 422))
                case .tooManyRequests(let tooMany):
                    return .failure(Self.error(status: 429, problem: try? tooMany.body.applicationProblemJson, retryAfter: tooMany.headers.retryAfter))
                case .internalServerError: return .failure(.server(status: 500))
                case .serviceUnavailable(let unavailable):
                    return .failure(Self.error(status: 503, problem: try? unavailable.body.applicationProblemJson, retryAfter: unavailable.headers.retryAfter))
                case .undocumented(let status, let payload): return await .failure(Self.error(status: status, payload: payload))
                }
            }
        }

        switch result {
        case .success(let receipt):
            MXLog.info("Reported feed \(target) (\(reason.rawValue)) as report \(receipt.reportID)\(receipt.isExisting ? ", already open" : "")")
        case .failure(let error):
            MXLog.error("Failed to report feed \(target): \(error)")
        }
        return result
    }

    // MARK: - Notices

    func notices(cursor: String?, limit: Int, language: String?) async -> Result<FeedNoticePage, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<FeedNoticePage, FeedError> in
            let output = try await client.underlying.getNotices(.init(query: .init(cursor: cursor, limit: Int32(limit)),
                                                                      headers: .init(acceptLanguage: language)))
            switch output {
            case .ok(let ok):
                return try .success(Self.noticePage(ok.body.json))
            case .badRequest(let bad):
                return .failure(cursor == nil ? .server(status: 400) : Self.invalidCursorOr(try? bad.body.applicationProblemJson))
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
        // Only an answer sets the badge; a failed read leaves it as it was.
        if case .success(let page) = result {
            noticesUnreadSubject.send(page.unread)
        }
        return result
    }

    func markNoticeRead(id: String) async -> Result<Void, FeedError> {
        let result = await withUnauthorizedRetry { [client] () async throws -> Result<Void, FeedError> in
            switch try await client.underlying.postNoticeRead(.init(path: .init(noticeId: id))) {
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
        switch result {
        case .success:
            // The badge is the server's count, never a local one: read it again. A failed re-read
            // leaves the last server value (the read sets the subject only on an answer).
            _ = await notices(cursor: nil, limit: 1, language: nil)
        case .failure(let error):
            MXLog.error("Failed to mark feed notice \(id) read: \(error)")
        }
        return result
    }

    var noticesUnreadPublisher: AnyPublisher<Int, Never> {
        noticesUnreadSubject.compactMap(\.self).eraseToAnyPublisher()
    }

    // MARK: - Mapping

    private nonisolated static func receipt(_ wire: Components.Schemas.FeedReportReceipt, isExisting: Bool) -> FeedReportReceipt {
        FeedReportReceipt(reportID: wire.reportId.lowercased(), deadline: wire.deadlineAt, isExisting: isExisting)
    }

    nonisolated static func noticePage(_ wire: Components.Schemas.FeedNoticePage) -> FeedNoticePage {
        FeedNoticePage(items: wire.items.map(notice), nextCursor: wire.nextCursor, unread: Int(wire.unread))
    }

    nonisolated static func notice(_ wire: Components.Schemas.FeedNotice) -> FeedNotice {
        let statement = wire.statement
        return FeedNotice(id: wire.id.lowercased(),
                          kind: FeedNoticeKind(wireValue: wire.kind),
                          createdAt: wire.createdAt,
                          isRead: wire.read,
                          postID: wire.postId?.lowercased(),
                          commentID: wire.commentId?.lowercased(),
                          reportID: wire.reportId?.lowercased(),
                          statement: FeedNoticeStatement(restriction: statement.restriction.map(FeedNoticeKind.init(wireValue:)),
                                                         until: statement.until,
                                                         tier: statement.tier.map(Int.init),
                                                         trigger: statement.trigger.map(FeedNoticeTrigger.init(wireValue:)),
                                                         isAutomated: statement.automated,
                                                         isDetectedByAutomatedMeans: statement.detectedByAutomatedMeans ?? false,
                                                         rule: statement.rule,
                                                         ruleTitle: statement.ruleTitle,
                                                         ruleExplanation: statement.ruleExplanation,
                                                         moderatorComment: statement.moderatorComment,
                                                         legalGround: statement.legalGround,
                                                         appealContact: statement.appealContact,
                                                         targetKind: statement.targetKind.map(FeedNoticeTargetKind.init(wireValue:)),
                                                         deadline: statement.deadlineAt,
                                                         outcome: statement.outcome.map(FeedReportOutcome.init(wireValue:))))
    }
}
