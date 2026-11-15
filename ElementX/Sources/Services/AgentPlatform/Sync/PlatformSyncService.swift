//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: platform sync (decision 289, backend ADR-0092).
// `GET /api/v1/sync?since=` as one SSE stream through the generated client;
// the frames are decoded here (the spec cannot type an event stream's
// events), from `SyncReady`, `SyncChanges` and `SyncLimited`. Logs carry
// statuses and kinds, never ids of people or content.
//

import AgentPlatformClient
import Foundation
import OpenAPIRuntime

// sourcery: AutoMockable
protocol PlatformSyncServiceProtocol {
    /// Opens the stream after `since` (`nil`: from now, answered with `ready {fresh: true}`).
    /// The stream ends when the server ends it (after 30 minutes) and throws when it fails.
    func open(since position: String?) async -> Result<PlatformSyncEventStream, PlatformSyncError>
}

final class PlatformSyncService: PlatformSyncServiceProtocol {
    private let client: AgentPlatformClient

    init(client: AgentPlatformClient) {
        self.client = client
    }

    func open(since position: String?) async -> Result<PlatformSyncEventStream, PlatformSyncError> {
        var result = await request(since: position)
        if case .failure(.unauthorized) = result {
            // As every platform call: the SDK may be landing a refreshed token.
            try? await Task.sleep(for: AgentPlatformService.unauthorizedRetryDelay)
            result = await request(since: position)
        }
        return result
    }

    /// `since` and `Last-Event-ID`, the same position: the header wins on the server.
    private func request(since position: String?) async -> Result<PlatformSyncEventStream, PlatformSyncError> {
        do {
            switch try await client.underlying.getSync(.init(query: .init(since: position), headers: .init(lastEventID: position))) {
            case .ok(let ok):
                return try .success(Self.events(from: ok.body.textEventStream))
            case .badRequest:
                return .failure(.invalidPosition)
            case .unauthorized:
                return .failure(.unauthorized)
            case .tooManyRequests(let tooMany):
                return .failure(.rateLimited(retryAfterSeconds: tooMany.headers.retryAfter.map(Int.init)))
            case .internalServerError:
                return .failure(.server(status: 500))
            case .serviceUnavailable:
                return .failure(.temporarilyUnavailable(retryAfterSeconds: nil))
            case .undocumented(let status, let payload):
                MXLog.info("The sync stream was refused: \(status)")
                return await .failure(Self.error(status: status, payload: payload))
            }
        } catch {
            // The app went to the background during the open: that closed it on purpose.
            if Self.isCancellation(error) {
                MXLog.debug("The sync stream's open was cancelled")
            } else {
                MXLog.error("The sync stream failed in transport: \(type(of: error))")
            }
            return .failure(.transport)
        }
    }

    /// A task's cancellation, as Swift or URLSession raises it, also inside the generated client's wrapper.
    nonisolated static func isCancellation(_ error: any Error) -> Bool {
        switch error {
        case is CancellationError:
            true
        case let error as URLError:
            error.code == .cancelled
        case let error as ClientError:
            isCancellation(error.underlyingError)
        default:
            false
        }
    }

    /// The frames this build knows, in order.
    nonisolated static func events(from body: HTTPBody) -> PlatformSyncEventStream {
        PlatformSyncEventStream { continuation in
            let task = Task {
                do {
                    for try await frame in body.asDecodedServerSentEvents() {
                        guard let event = PlatformSyncEvent(event: frame.event, data: frame.data) else {
                            MXLog.info("Skipped a sync frame this build does not read: \(frame.event ?? "message")")
                            continue
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// An answer the spec does not list: the router's fallback 404 is a backend without the route.
    nonisolated static func error(status: Int, payload: UndocumentedPayload) async -> PlatformSyncError {
        guard status == 404 else { return .server(status: status) }
        var problemType: String?
        if let body = payload.body, let data = try? await Data(collecting: body, upTo: 64 * 1024) {
            problemType = (try? JSONDecoder().decode(Problem.self, from: data))?.type
        }
        // Any other 404 (a proxy) is retried.
        return problemType == FeedError.routeNotFoundType ? .unavailable : .server(status: 404)
    }

    private struct Problem: Decodable {
        let type: String?
    }
}
