//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0078, GDPR): «Your data» — the account export and one
// call's export reach the share sheet as a file, which goes once it closes.
//

import Foundation
import os
@testable import Spiral
import Testing

@MainActor
struct YourDataScreenViewModelTests {
    let service = AgentPlatformServiceMock()
    let clientProxy = ClientProxyMock(.init())
    let userIndicatorController = UserIndicatorControllerMock()

    static let start = Date(timeIntervalSince1970: 1_791_540_000) // 2026-10-09 10:00 UTC
    static let standup = VoiceSessionRecord(id: "s-standup", agentMXID: "@assistant-alice:spiral.md", roomID: "!standup:spiral.md",
                                            createdAt: start, startedAt: start, endedAt: start.addingTimeInterval(1500))
    static let left = VoiceSessionRecord(id: "s-left", agentMXID: "@assistant-alice:spiral.md", roomID: "!gone:spiral.md",
                                         createdAt: start.addingTimeInterval(-86400), startedAt: nil, endedAt: start.addingTimeInterval(-86000))

    init() {
        service.listVoiceSessionsCursorReturnValue = .success(.init(sessions: [Self.standup, Self.left], nextCursor: nil))
        service.exportAccountDataReturnValue = .success(Data(#"{"tenant":{"id":"t-1"}}"#.utf8))
        service.exportVoiceSessionSessionIDReturnValue = .success(Data(#"{"session":{"id":"s-standup"}}"#.utf8))
        let standupRoom = RoomSummary.mock(id: "!standup:spiral.md", name: "Daily standup")
        clientProxy.roomSummaryForIdentifierClosure = { $0 == standupRoom.id ? standupRoom : nil }
    }

    private func makeLoadedViewModel() async throws -> YourDataScreenViewModel {
        let viewModel = YourDataScreenViewModel(agentPlatformService: service,
                                                clientProxy: clientProxy,
                                                userIndicatorController: userIndicatorController)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.calls)) { $0 != .loading }
        try await loaded.fulfill()
        return viewModel
    }

    // MARK: - Calls

    @Test
    func listsTheCallsWithTheRoomsThePersonIsStillIn() async throws {
        let viewModel = try await makeLoadedViewModel()

        guard case .loaded(let calls, let nextCursor) = viewModel.context.viewState.calls else {
            Issue.record("Expected the calls")
            return
        }
        #expect(calls.map(\.id) == ["s-standup", "s-left"])
        #expect(calls.map(\.roomName) == ["Daily standup", nil])
        #expect(nextCursor == nil)
        #expect(service.listVoiceSessionsCursorReceivedCursor == nil)
    }

    @Test
    func loadMoreAppendsTheNextPage() async throws {
        service.listVoiceSessionsCursorReturnValue = .success(.init(sessions: [Self.standup], nextCursor: "page-2"))
        let viewModel = try await makeLoadedViewModel()

        service.listVoiceSessionsCursorReturnValue = .success(.init(sessions: [Self.left], nextCursor: nil))
        let appended = deferFulfillment(viewModel.context.observe(\.viewState.calls)) {
            if case .loaded(let calls, nil) = $0 { calls.count == 2 } else { false }
        }
        viewModel.context.send(viewAction: .loadMoreCalls)
        try await appended.fulfill()

        #expect(service.listVoiceSessionsCursorReceivedInvocations == [nil, "page-2"])
    }

    @Test
    func callsThatFailToLoadCanBeRetried() async throws {
        service.listVoiceSessionsCursorReturnValue = .failure(.serverError(status: 500))
        let viewModel = try await makeLoadedViewModel()
        #expect(viewModel.context.viewState.calls == .failure)

        service.listVoiceSessionsCursorReturnValue = .success(.init(sessions: [Self.standup], nextCursor: nil))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.calls)) {
            if case .loaded = $0 { true } else { false }
        }
        viewModel.context.send(viewAction: .retryCalls)
        try await loaded.fulfill()
    }

    // MARK: - Exports

    @Test
    func accountExportHandsAFileToTheShareSheetAndRemovesItAfter() async throws {
        let viewModel = try await makeLoadedViewModel()

        let shown = deferFulfillment(viewModel.context.observe(\.viewState.bindings.exportFile)) { $0 != nil }
        viewModel.context.send(viewAction: .exportAccount)
        try await shown.fulfill()

        let file = try #require(viewModel.context.exportFile)
        #expect(file.url.lastPathComponent.hasPrefix("spiral-data-"))
        #expect(FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
        #expect(!viewModel.context.viewState.isExporting)
        #expect(service.exportAccountDataCallsCount == 1)

        viewModel.context.send(viewAction: .exportDismissed)
        #expect(viewModel.context.exportFile == nil)
        #expect(!FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
    }

    @Test
    func callExportFetchesThatCall() async throws {
        let viewModel = try await makeLoadedViewModel()

        let shown = deferFulfillment(viewModel.context.observe(\.viewState.bindings.exportFile)) { $0 != nil }
        viewModel.context.send(viewAction: .exportCall(id: "s-standup"))
        try await shown.fulfill()

        #expect(service.exportVoiceSessionSessionIDReceivedSessionID == "s-standup")
        #expect(viewModel.context.exportFile?.url.lastPathComponent == "spiral-call-2026-10-09T100000Z.json")
        #expect(viewModel.context.viewState.exportingCallID == nil)
        viewModel.context.send(viewAction: .exportDismissed)
    }

    @Test
    func aFailedExportSaysSoAndOpensNothing() async throws {
        service.exportAccountDataReturnValue = .failure(.serverError(status: 500))
        let viewModel = try await makeLoadedViewModel()

        let done = deferFulfillment(viewModel.context.observe(\.viewState.isExportingAccount)) { !$0 }
        viewModel.context.send(viewAction: .exportAccount)
        try await done.fulfill()

        #expect(viewModel.context.exportFile == nil)
        #expect(userIndicatorController.submitIndicatorDelayReceivedArguments?.indicator.title == UntranslatedL10n.screenYourDataExportFailed)
    }

    @Test
    func oneExportAtATime() async throws {
        service.exportAccountDataClosure = {
            try? await Task.sleep(for: .milliseconds(300))
            return .success(Data("{}".utf8))
        }
        let viewModel = try await makeLoadedViewModel()

        let shown = deferFulfillment(viewModel.context.observe(\.viewState.bindings.exportFile)) { $0 != nil }
        viewModel.context.send(viewAction: .exportAccount)
        viewModel.context.send(viewAction: .exportCall(id: "s-standup"))
        viewModel.context.send(viewAction: .exportAccount)
        try await shown.fulfill()

        #expect(service.exportAccountDataCallsCount == 1)
        #expect(!service.exportVoiceSessionSessionIDCalled)
        viewModel.context.send(viewAction: .exportDismissed)
    }

    // MARK: - Leaving the screen
    
    @Test
    func leavingTheScreenRemovesTheFileItShowed() async throws {
        var viewModel: YourDataScreenViewModel? = try await makeLoadedViewModel()
        let context = try #require(viewModel?.context)
        
        let shown = deferFulfillment(context.observe(\.viewState.bindings.exportFile)) { $0 != nil }
        context.send(viewAction: .exportAccount)
        try await shown.fulfill()
        let folder = try #require(context.exportFile).url.deletingLastPathComponent()
        #expect(Self.exists(folder))
        
        viewModel = nil
        
        #expect(await Self.eventually { !Self.exists(folder) })
    }
    
    @Test
    func leavingTheScreenWhileExportingCancelsTheExport() async throws {
        let sawCancellation = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        service.exportAccountDataClosure = {
            try? await Task.sleep(for: .seconds(2))
            sawCancellation.withLock { $0 = Task.isCancelled }
            return .success(Data("{}".utf8))
        }
        let exportsBefore = Self.exportFolders()
        var viewModel: YourDataScreenViewModel? = try await makeLoadedViewModel()
        
        viewModel?.context.send(viewAction: .exportAccount)
        try await Task.sleep(for: .milliseconds(100))
        viewModel = nil
        
        #expect(await Self.eventually { sawCancellation.withLock { $0 } != nil })
        #expect(sawCancellation.withLock { $0 } == true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(Self.exportFolders() == exportsBefore)
    }
    
    @Test
    func openingTheScreenRemovesLeftoverExports() async throws {
        let leftover = PersonalDataExportFile.exportsFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-2 * 3600)],
                                              ofItemAtPath: leftover.path(percentEncoded: false))
        
        _ = try await makeLoadedViewModel()
        
        #expect(await Self.eventually { !Self.exists(leftover) })
    }
    
    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
    
    private static func exportFolders() -> Set<String> {
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: PersonalDataExportFile.exportsFolder.path(percentEncoded: false))) ?? []
        return Set(folders)
    }
    
    /// Polls for up to three seconds.
    private static func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<60 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
    
    // MARK: - The Settings row

    @Test
    func settingsOffersYourDataToASpiralAccountOnly() async throws {
        let spiralSession = UserSessionMock(.init())
        spiralSession.agentPlatformService = service
        let settings = makeSettings(userSession: spiralSession)
        #expect(settings.context.viewState.showYourData)
        #expect(!makeSettings(userSession: UserSessionMock(.init())).context.viewState.showYourData)

        let opened = deferFulfillment(settings.actions) { action in
            if case .yourData = action { true } else { false }
        }
        settings.context.send(viewAction: .yourData)
        try await opened.fulfill()
    }

    private func makeSettings(userSession: UserSessionMock) -> SettingsScreenViewModel {
        SettingsScreenViewModel(userSession: userSession,
                                isBugReportServiceEnabled: false,
                                isInSecondaryWindow: false,
                                userIndicatorController: UserIndicatorControllerMock())
    }

    @Test
    func callDescriptionSaysHowLongOrThatItIsOngoing() {
        let ongoing = VoiceSessionRecord(id: "s", agentMXID: "@a:b", roomID: "!r:b", createdAt: Self.start, startedAt: Self.start, endedAt: nil)

        #expect(YourDataScreen.callDescription(Self.standup).hasSuffix(" · 25 min"))
        #expect(YourDataScreen.callDescription(ongoing).hasSuffix(" · \(UntranslatedL10n.screenYourDataCallOngoing)"))
        #expect(!YourDataScreen.callDescription(Self.left).contains("·"))
    }
}
