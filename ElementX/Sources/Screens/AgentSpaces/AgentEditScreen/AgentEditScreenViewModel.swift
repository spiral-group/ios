//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AgentEditScreenViewModelType = StateStoreViewModelV2<AgentEditScreenViewState, AgentEditScreenViewAction>

class AgentEditScreenViewModel: AgentEditScreenViewModelType, AgentEditScreenViewModelProtocol {
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let userSession: UserSessionProtocol
    private let mediaUploadingPreprocessor: MediaUploadingPreprocessor
    private let userIndicatorController: UserIndicatorControllerProtocol
    /// The picked avatar once uploaded, so a retried Save doesn't upload it again.
    private var uploadedAvatarMXC: String?
    
    private let actionsSubject: PassthroughSubject<AgentEditScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentEditScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(agent: AgentSpaceAgentCard,
         agentPlatformService: AgentPlatformServiceProtocol,
         userSession: UserSessionProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         appSettings: AppSettings) {
        self.agentPlatformService = agentPlatformService
        self.userSession = userSession
        mediaUploadingPreprocessor = MediaUploadingPreprocessor(appSettings: appSettings)
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: AgentEditScreenViewState(card: agent),
                   mediaProvider: userSession.mediaProvider)
        state.avatarMXC = agent.avatarMXC
        state.initialAvatarMXC = agent.avatarMXC
        
        Task { await load() }
    }
    
    override func process(viewAction: AgentEditScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .save:
            Task { await save() }
        case .cancel:
            cancel()
        case .retry:
            state.loadState = .loading
            Task { await load() }
        case .presentMediaSource:
            state.bindings.showMediaSheet = true
        case .displayCameraPicker:
            actionsSubject.send(.displayCameraPicker)
        case .displayMediaPicker:
            actionsSubject.send(.displayMediaPicker)
        case .displayFilePicker:
            actionsSubject.send(.displayFilePicker)
        case .removeImage:
            state.localMedia = nil
            state.avatarMXC = nil
            uploadedAvatarMXC = nil
        }
    }
    
    func didSelectMediaUrl(url: URL) {
        Task {
            let userIndicatorID = UUID().uuidString
            defer { userIndicatorController.retractIndicatorWithId(userIndicatorID) }
            userIndicatorController.submitIndicator(UserIndicator(id: userIndicatorID,
                                                                  type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                                  title: L10n.commonLoading,
                                                                  persistent: true))
            
            guard case let .success(maxUploadSize) = await userSession.clientProxy.maxMediaUploadSize else {
                MXLog.error("Failed to get max upload size")
                state.bindings.alertInfo = AlertInfo(id: .failedProcessingMedia)
                return
            }
            let mediaResult = await mediaUploadingPreprocessor.processMedia(at: url, maxUploadSize: maxUploadSize)
            
            switch mediaResult {
            case .success(.image):
                // A fresh pick after a Remove re-enables the avatar.
                state.avatarMXC = state.initialAvatarMXC
                state.localMedia = try? mediaResult.get()
                uploadedAvatarMXC = nil
            case .failure, .success:
                state.bindings.alertInfo = AlertInfo(id: .failedProcessingMedia)
            }
        }
    }
    
    // MARK: - Private
    
    private func load() async {
        switch await agentPlatformService.fetchAgentEditSchema(agentID: state.card.agentID) {
        case .success(let schema):
            // Seed from the FRESH read-model (the tapped card can be stale
            // after an earlier save — 0038 I1 fix); the card only if it fails.
            let readModel = try? await agentPlatformService.fetchAgentReadModel(agentID: state.card.agentID).get()
            let displayName = readModel?.displayName ?? state.card.displayName
            let avatarMXC = readModel.map(\.avatarMXC) ?? state.card.avatarMXC
            state.bindings.displayName = displayName
            state.initialDisplayName = displayName
            state.avatarMXC = avatarMXC
            state.initialAvatarMXC = avatarMXC
            state.loadState = .loaded(schema)
        case .failure(let error):
            MXLog.error("Failed to load edit schema: \(error)")
            state.loadState = .failure
        }
    }
    
    /// Moves the baselines to what the server holds. A field the user
    /// hasn't edited follows the server too; an edited one keeps the
    /// edit, so the next Save sends only what still differs.
    private func adoptServerState(_ readModel: AgentReadModel) {
        if state.bindings.displayName.trimmingCharacters(in: .whitespacesAndNewlines) == state.initialDisplayName {
            state.bindings.displayName = readModel.displayName
        }
        state.initialDisplayName = readModel.displayName
        
        if let uploadedAvatarMXC, readModel.avatarMXC == uploadedAvatarMXC {
            state.localMedia = nil
            state.avatarMXC = uploadedAvatarMXC
            self.uploadedAvatarMXC = nil
        } else if !state.avatarDidChange {
            state.avatarMXC = readModel.avatarMXC
        }
        state.initialAvatarMXC = readModel.avatarMXC
    }
    
    /// RoomDetailsEdit canon: Cancel with unsaved changes offers
    /// Save / Discard before dismissing.
    private func cancel() {
        if state.canSave {
            state.bindings.alertInfo = AlertInfo(id: .unsavedChanges,
                                                 title: L10n.dialogUnsavedChangesTitle,
                                                 message: L10n.dialogUnsavedChangesDescription,
                                                 primaryButton: .init(title: L10n.actionSave) { Task { await self.save() } },
                                                 secondaryButton: .init(title: L10n.actionDiscard, role: .cancel) { self.actionsSubject.send(.cancel) })
        } else {
            actionsSubject.send(.cancel)
        }
    }
    
    private func save() async {
        state.isSaving = true
        defer { state.isSaving = false }
        
        // Deferred avatar (client-side upload, Brief 0039): a fresh pick
        // uploads via the Matrix SDK; Remove clears with "". `nil` keeps
        // avatar out of the profile patch entirely.
        var avatarMXC: String?
        if state.avatarDidChange {
            if let uploadedAvatarMXC {
                avatarMXC = uploadedAvatarMXC
            } else if let media = state.localMedia {
                switch await userSession.clientProxy.uploadMedia(media) {
                case .success(let mxc):
                    avatarMXC = mxc
                    uploadedAvatarMXC = mxc
                case .failure(let error):
                    MXLog.error("Failed to upload the agent avatar: \(error)")
                    state.bindings.alertInfo = AlertInfo(id: .failedUploadingAvatar,
                                                         title: UntranslatedL10n.screenAgentEditAvatarFailure)
                    return
                }
            } else {
                avatarMXC = ""
            }
        }
        
        // One PATCH with the changed fields (Brief 0038); after a failure the
        // baselines are re-read, so a retry sends only what still differs.
        let patch = AgentEditPatch(displayName: state.nameDidChange ? state.bindings.displayName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                                   avatarMXC: avatarMXC)
        guard !patch.isEmpty else {
            actionsSubject.send(.saved)
            return
        }
        
        switch await agentPlatformService.editAgent(agentID: state.card.agentID, patch: patch) {
        case .success(let readModel):
            adoptServerState(readModel)
            actionsSubject.send(.saved)
        case .failure(let error):
            showSaveFailure(error)
            if case .success(let readModel) = await agentPlatformService.fetchAgentReadModel(agentID: state.card.agentID) {
                adoptServerState(readModel)
            }
        }
    }
    
    private func showSaveFailure(_ error: AgentPlatformError) {
        MXLog.error("Failed to save agent edits: \(error)")
        state.bindings.alertInfo = AlertInfo(id: .saveFailed,
                                             title: UntranslatedL10n.screenAgentEditFailure)
    }
}
