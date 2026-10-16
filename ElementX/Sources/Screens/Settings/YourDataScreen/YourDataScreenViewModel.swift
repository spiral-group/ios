//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0078, GDPR): «Your data» — the account export and
// one call's export, each handed to the share sheet.
//

import SwiftUI

typealias YourDataScreenViewModelType = StateStoreViewModelV2<YourDataScreenViewState, YourDataScreenViewAction>

class YourDataScreenViewModel: YourDataScreenViewModelType, YourDataScreenViewModelProtocol {
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let clientProxy: ClientProxyProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol

    private var exportTask: Task<Void, Never>?
    private var callsTask: Task<Void, Never>?
    /// The file the share sheet holds, removed once the sheet is gone.
    private var sharedFile: PersonalDataExportFile?

    init(agentPlatformService: AgentPlatformServiceProtocol,
         clientProxy: ClientProxyProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.agentPlatformService = agentPlatformService
        self.clientProxy = clientProxy
        self.userIndicatorController = userIndicatorController
        super.init(initialViewState: YourDataScreenViewState())

        loadCalls(after: nil)
        Task { await PersonalDataExportFile.removeLeftovers(now: .now) }
    }

    /// The tasks hold the view model weakly while they wait on the network, so
    /// leaving the screen cancels them; an export written just before that is
    /// removed here.
    isolated deinit {
        exportTask?.cancel()
        callsTask?.cancel()
        sharedFile?.discard()
    }

    override func process(viewAction: YourDataScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .exportAccount:
            guard !state.isExporting else { return }
            state.isExportingAccount = true
            let service = agentPlatformService
            exportTask = Task { [weak self] in
                let result = await service.exportAccountData()
                await self?.share(result, as: .account)
                self?.state.isExportingAccount = false
            }
        case .exportCall(let id):
            guard !state.isExporting, case .loaded(let calls, _) = state.calls,
                  let call = calls.first(where: { $0.id == id }) else {
                return
            }
            state.exportingCallID = id
            let service = agentPlatformService
            exportTask = Task { [weak self] in
                let result = await service.exportVoiceSession(sessionID: call.session.id)
                await self?.share(result, as: .call(date: call.session.date))
                self?.state.exportingCallID = nil
            }
        case .loadMoreCalls:
            guard !state.isLoadingMoreCalls, case .loaded(_, let cursor?) = state.calls else { return }
            state.isLoadingMoreCalls = true
            loadCalls(after: cursor)
        case .retryCalls:
            state.calls = .loading
            loadCalls(after: nil)
        case .exportDismissed:
            state.bindings.exportFile = nil
            sharedFile?.discard()
            sharedFile = nil
        }
    }

    // MARK: - Exports

    private func share(_ result: Result<Data, AgentPlatformError>, as kind: PersonalDataExportFile.Kind) async {
        switch result {
        case .success(let data):
            do {
                let file = try await PersonalDataExportFile.write(data, kind: kind)
                sharedFile?.discard()
                sharedFile = file
                state.bindings.exportFile = file
            } catch {
                MXLog.error("Failed to write a personal data export: \(error)")
                showExportFailure()
            }
        case .failure(let error):
            MXLog.error("Failed to fetch a personal data export: \(error)")
            showExportFailure()
        }
    }

    private func showExportFailure() {
        userIndicatorController.submitIndicator(.init(title: UntranslatedL10n.screenYourDataExportFailed))
    }

    // MARK: - Calls

    private func loadCalls(after cursor: String?) {
        callsTask?.cancel()
        let service = agentPlatformService
        callsTask = Task { [weak self] in
            let result = await service.listVoiceSessions(cursor: cursor)
            guard !Task.isCancelled else { return }
            self?.showCalls(result, after: cursor)
        }
    }
    
    private func showCalls(_ result: Result<VoiceSessionsPage, AgentPlatformError>, after cursor: String?) {
        defer { state.isLoadingMoreCalls = false }
        
        switch result {
        case .success(let page):
            let calls = page.sessions.map { session in
                YourDataScreenCall(session: session, roomName: clientProxy.roomSummaryForIdentifier(session.roomID)?.name)
            }
            if cursor != nil, case .loaded(let shown, _) = state.calls {
                state.calls = .loaded(shown + calls, nextCursor: page.nextCursor)
            } else {
                state.calls = .loaded(calls, nextCursor: page.nextCursor)
            }
        case .failure(let error):
            MXLog.error("Failed to list the calls to export: \(error)")
            if cursor == nil {
                state.calls = .failure
            } else {
                userIndicatorController.submitIndicator(.init(title: UntranslatedL10n.screenYourDataCallsLoadFailed))
            }
        }
    }
}
