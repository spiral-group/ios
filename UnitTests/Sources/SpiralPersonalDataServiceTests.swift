//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0078, GDPR): the service calls behind «Your data» and
// the per-contact memory erase, against a stubbed transport, and the file the
// share sheet receives.
//

import AgentPlatformClient
import Foundation
@testable import Spiral
import Synchronization
import Testing

@MainActor
struct SpiralPersonalDataServiceTests {
    private let testID = UUID().uuidString
    private let service: AgentPlatformService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PersonalDataURLProtocol.self]
        configuration.httpAdditionalHeaders = [PersonalDataURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = AgentPlatformService(client: client)
    }

    // MARK: - The session

    @Test
    func theClientKeepsNoCopyOfAnyResponse() throws {
        let client = try AgentPlatformClient(serverURL: "https://platform.test", authProvider: StaticAuthTokenProvider(token: nil))
        let configuration = client.urlSession.configuration

        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForRequest == URLSession.shared.configuration.timeoutIntervalForRequest)
        #expect(configuration.timeoutIntervalForResource == URLSession.shared.configuration.timeoutIntervalForResource)
    }

    // MARK: - Account export

    @Test
    func accountExportIsTheDocumentTheServerSent() async throws {
        let document = Data(#"{"export_metadata":{"agents_count":1},"tenant":{"id":"t-1"},"agents":[]}"#.utf8)
        stub(status: 200, body: document)

        let result = try await service.exportAccountData().get()

        #expect(result == document)
        let request = try #require(lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == "/api/v1/me/export")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mat_test")
    }

    @Test
    func accountExportFailureCarriesTheStatus() async {
        stub(status: 404, body: problem(404))
        guard case .failure(.notFound) = await service.exportAccountData() else {
            Issue.record("A missing account should be .notFound")
            return
        }

        stub(status: 500, body: problem(500))
        guard case .failure(.serverError(status: 500)) = await service.exportAccountData() else {
            Issue.record("A failed export should be .serverError(500)")
            return
        }
    }

    // MARK: - Account deletion

    /// The six feed counters are optional on the wire (backend f4ca9664): a
    /// receipt from a server without them is still a deleted account.
    @Test
    func accountDeletionReadsAReceiptWithoutTheFeedCounters() async {
        stub(status: 200, body: Data(#"""
        {"status":"purged","counts":{"agents":1,"voice_sessions":0,"voice_transcripts":0,"voice_summaries":0,
         "voice_consent_log":0,"approvals":0,"mas_deactivated":true,"agents_deactivated":1,"recordings_queued":0,
         "login_links_deleted":0,"identity_erased":true,"bridge_logins_ended":0,"bridges_failed":0,
         "ai_consent_decisions":0,"recording_publications":0,"push_devices":0,"notification_read_markers":0,
         "organization_memberships":0,"queue_jobs_erased":0,"action_log_entries":0,"gdpr_audit_rows":0,
         "as_contact":{"memory_entries":0,"relationships":0,"transcript_lines":0,"outreach_targets":0,
                       "approvals":0,"key_relay_rows":0,"action_log_entries_scrubbed":0,"session_controls_scrubbed":0,
                       "invite_redemptions_scrubbed":0,"verifications":0,"tool_scopes_rewritten":0,"tools_turned_off":0}}}
        """#.utf8))

        let result = await service.deleteAccount()

        guard case .success = result else {
            Issue.record("A receipt without the feed counters should be a deleted account, got \(result)")
            return
        }
        #expect(lastRequest?.httpMethod == "DELETE")
        #expect(lastRequest?.url?.path() == "/api/v1/me")
    }

    // MARK: - Calls

    @Test
    func callsListMapsEachSessionAndTheNextPage() async throws {
        stub(status: 200, body: Data("""
        {"items":[
          {"id":"s-ended","agent_id":"a-1","agent_mxid":"@assistant-alice:spiral.md","room_id":"!standup:spiral.md",
           "state":"ended","voice_mode":"assistant","leave_policy":"call_end","was_room_member_before":false,
           "mode_state":{"kind":"owner_assistant"},"created_at":"2026-10-09T10:00:00Z",
           "started_at":"2026-10-09T10:00:04Z","ended_at":"2026-10-09T10:25:04Z","end_reason":"call_ended"},
          {"id":"s-live","agent_id":"a-1","agent_mxid":"@assistant-alice:spiral.md","room_id":"!dm:spiral.md",
           "state":"active","voice_mode":"assistant","leave_policy":"call_end","was_room_member_before":true,
           "mode_state":{"kind":"owner_assistant"},"created_at":"2026-10-10T09:00:00Z"}
        ],"next_cursor":"2026-10-09T10:00:00+00:00|s-ended"}
        """.utf8))

        let page = try await service.listVoiceSessions(cursor: "previous").get()

        #expect(page.nextCursor == "2026-10-09T10:00:00+00:00|s-ended")
        #expect(page.sessions.map(\.id) == ["s-ended", "s-live"])
        #expect(page.sessions[0].roomID == "!standup:spiral.md")
        #expect(page.sessions[0].isEnded)
        #expect(page.sessions[0].date == page.sessions[0].startedAt)
        #expect(!page.sessions[1].isEnded)
        #expect(page.sessions[1].date == page.sessions[1].createdAt)

        let query = try #require(lastRequest?.url).queryItems
        #expect(query["cursor"] == "previous")
    }

    @Test
    func callExportIsThatCallsDocument() async throws {
        let document = Data(#"{"session":{"id":"s-1"},"transcripts":[],"summary":null,"audit":[]}"#.utf8)
        stub(status: 200, body: document)

        let result = try await service.exportVoiceSession(sessionID: "s-1").get()

        #expect(result == document)
        #expect(lastRequest?.url?.path() == "/api/v1/voice-sessions/s-1/export")
    }

    @Test
    func someoneElsesCallIsForbidden() async {
        stub(status: 403, body: problem(403))
        guard case .failure(.forbidden) = await service.exportVoiceSession(sessionID: "s-1") else {
            Issue.record("Another owner's call should be .forbidden")
            return
        }
    }

    // MARK: - Memory erase

    @Test
    func memoryEraseNamesTheContactAndCountsWhatWent() async throws {
        stub(status: 200, body: Self.erasedBody(memoryEntries: 3))

        let erased = try await service.eraseAssistantMemory(aboutContact: "@bob:spiral.md").get()

        #expect(erased.memoryEntries == 3)
        let request = try #require(lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path() == "/api/v1/me/memory")
        #expect(try #require(request.url).queryItems["contact_mxid"] == "@bob:spiral.md")
    }

    @Test
    func memoryEraseWithNoAccountErasedNothing() async throws {
        stub(status: 404, body: problem(404, detail: "account"))
        #expect(try await service.eraseAssistantMemory(aboutContact: "@bob:spiral.md").get() == .nothing)
    }

    /// Every count of the cross-agent erase reaches the app, each to its own field.
    @Test
    func memoryEraseReadsEveryCount() async throws {
        stub(status: 200, body: Data(#"""
        {"status":"purged","contact_mxid":"@bob:spiral.md","deleted_count":1,
         "erased":{"memory_entries":1,"relationships":2,"transcript_lines":3,"outreach_targets":4,"approvals":5,
                   "key_relay_rows":6,"action_log_entries_scrubbed":7,"session_controls_scrubbed":8,
                   "invite_redemptions_scrubbed":9,"verifications":10,"tool_scopes_rewritten":11,"tools_turned_off":12}}
        """#.utf8))

        let erased = try await service.eraseAssistantMemory(aboutContact: "@bob:spiral.md").get()

        #expect(erased == ContactErasure(memoryEntries: 1, relationships: 2, transcriptLines: 3, outreachTargets: 4,
                                         approvals: 5, keyRelayRows: 6, verifications: 10, actionLogEntriesScrubbed: 7,
                                         sessionControlsScrubbed: 8, inviteRedemptionsScrubbed: 9,
                                         toolScopesRewritten: 11, toolsTurnedOff: 12))
        #expect(erased.erasedAnything)
    }

    /// The person or their own agent is not a contact; the profile never
    /// offers it, and if it ever goes out it reads as a refusal, not a failure.
    @Test
    func erasingOneselfIsAValidationRefusal() async {
        stub(status: 400, body: problem(400, detail: "your own account and your own agents are not contacts"))
        guard case .failure(.validation) = await service.eraseAssistantMemory(aboutContact: "@me:spiral.md") else {
            Issue.record("A 400 should be .validation")
            return
        }
    }

    @Test
    func anyOther404FromTheEraseIsNotAnErase() async {
        stub(status: 404, body: problem(404, detail: "no route for DELETE /api/v1/me/memory"))
        guard case .failure(.notFound) = await service.eraseAssistantMemory(aboutContact: "@bob:spiral.md") else {
            Issue.record("A 404 that is not the route's own should stay .notFound")
            return
        }

        stub(status: 404, body: Data("<html>Not Found</html>".utf8))
        guard case .failure = await service.eraseAssistantMemory(aboutContact: "@bob:spiral.md") else {
            Issue.record("A 404 page should be a failure")
            return
        }
    }

    // MARK: - The file

    @Test
    func accountExportFileIsTheServersBytesNamedForTheDay() async throws {
        let now = try Date("2026-10-10T08:30:00Z", strategy: .iso8601)
        let body = Data(#"{"b":1,"a":["x\/y"]}"#.utf8)
        let file = try await PersonalDataExportFile.write(body, kind: .account, now: now)
        defer { file.discard() }

        #expect(file.url.lastPathComponent == "spiral-data-2026-10-10.json")
        #expect(try Data(contentsOf: file.url) == body)
    }

    @Test
    func aBodyThatIsJSONButNotAnObjectIsRefused() async {
        await #expect(throws: PersonalDataExportFile.WriteError.notJSON) {
            try await PersonalDataExportFile.write(Data("[1, 2]".utf8), kind: .account)
        }
    }

    @Test
    func callExportFileIsNamedForTheCall() throws {
        let start = try Date("2026-10-09T14:23:05Z", strategy: .iso8601)
        #expect(PersonalDataExportFile.fileName(for: .call(date: start), now: .now) == "spiral-call-2026-10-09T142305Z.json")
    }

    @Test
    func aBodyThatIsNotJSONIsRefused() async {
        await #expect(throws: PersonalDataExportFile.WriteError.notJSON) {
            try await PersonalDataExportFile.write(Data("<html>Bad gateway</html>".utf8), kind: .account)
        }
    }

    @Test
    func leftoverExportsAreRemovedAfterAnHour() async throws {
        let file = try await PersonalDataExportFile.write(Data("{}".utf8), kind: .account)
        let folder = file.url.deletingLastPathComponent().path(percentEncoded: false)

        await PersonalDataExportFile.removeLeftovers(now: .now)
        #expect(FileManager.default.fileExists(atPath: folder))

        await PersonalDataExportFile.removeLeftovers(now: .now.addingTimeInterval(PersonalDataExportFile.leftoverAge + 60))
        #expect(!FileManager.default.fileExists(atPath: folder))
    }

    @Test
    func discardRemovesTheFileAndItsFolder() async throws {
        let file = try await PersonalDataExportFile.write(Data("{}".utf8), kind: .account)
        file.discard()

        #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path(percentEncoded: false)))
    }

    // MARK: - Helpers

    private func stub(status: Int, body: Data) {
        PersonalDataURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: body) }
    }

    private var lastRequest: URLRequest? {
        PersonalDataURLProtocol.requests.withLock { $0[testID]?.last }
    }

    /// `DELETE /me/memory`'s 200 (`DeleteMemoryResponse`), every count zero but the memory entries.
    private static func erasedBody(memoryEntries: Int) -> Data {
        Data(#"""
        {"status":"purged","contact_mxid":"@bob:spiral.md","deleted_count":\#(memoryEntries),
         "erased":{"memory_entries":\#(memoryEntries),"relationships":0,"transcript_lines":0,"outreach_targets":0,
                   "approvals":0,"key_relay_rows":0,"action_log_entries_scrubbed":0,"session_controls_scrubbed":0,
                   "invite_redemptions_scrubbed":0,"verifications":0,"tool_scopes_rewritten":0,"tools_turned_off":0}}
        """#.utf8)
    }

    private func problem(_ status: Int, detail: String = "x") -> Data {
        Data(#"{"type":"/errors/x","title":"x","status":\#(status),"detail":"\#(detail)"}"#.utf8)
    }
}

private extension URL {
    var queryItems: [String: String] {
        let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }
}

/// Answers each test from its own stub, told apart by a header every request
/// of that test's session carries.
private nonisolated class PersonalDataURLProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let body: Data
    }

    static let testIDHeader = "X-Test-ID"
    static let stubs = Mutex<[String: Stub]>([:])
    static let requests = Mutex<[String: [URLRequest]]>([:])

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let testID = request.value(forHTTPHeaderField: Self.testIDHeader) ?? ""
        Self.requests.withLock { $0[testID, default: []].append(request) }
        let stub = Self.stubs.withLock { $0[testID] } ?? Stub(status: 500, body: Data())

        let contentType = stub.status == 200 ? "application/json" : "application/problem+json"
        guard let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
