//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias UserDetailsEditScreenViewModelType = StateStoreViewModelV2<UserDetailsEditScreenViewState, UserDetailsEditScreenViewAction>

class UserDetailsEditScreenViewModel: UserDetailsEditScreenViewModelType, UserDetailsEditScreenViewModelProtocol {
    private let actionsSubject: PassthroughSubject<UserDetailsEditScreenViewModelAction, Never> = .init()
    private let clientProxy: ClientProxyProtocol
    private let appMediator: AppMediatorProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let mediaUploadingPreprocessor: MediaUploadingPreprocessor
    
    var actions: AnyPublisher<UserDetailsEditScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(userSession: UserSessionProtocol,
         mediaUploadingPreprocessor: MediaUploadingPreprocessor,
         appMediator: AppMediatorProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        clientProxy = userSession.clientProxy
        self.mediaUploadingPreprocessor = mediaUploadingPreprocessor
        self.userIndicatorController = userIndicatorController
        self.appMediator = appMediator
        
        let profile = clientProxy.userProfilePublisher.value
        super.init(initialViewState: UserDetailsEditScreenViewState(currentUserProfile: profile,
                                                                    selectedAvatarURL: profile.avatarURL,
                                                                    bindings: .init(name: profile.displayName ?? "")),
                   mediaProvider: userSession.mediaProvider)
        
        clientProxy.userProfilePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                guard let self else { return }
                
                state.currentUserProfile = profile
                state.selectedAvatarURL = profile.avatarURL
                state.bindings.name = profile.displayName ?? ""
            }
            .store(in: &cancellables)
        
        Task {
            await self.clientProxy.loadUserProfileIfNeeded()
            state.canEditAvatar = await clientProxy.capabilities.canChangeAvatar()
            state.canEditDisplayName = await clientProxy.capabilities.canChangeDisplayName()
        }
        
        // AGENT-PLATFORM: feed (Brief 0082)
        Task { await self.loadBio() }
    }
    
    // MARK: - Public
    
    override func process(viewAction: UserDetailsEditScreenViewAction) {
        switch viewAction {
        case .cancel:
            showUnsavedChangesAlert() // The cancel button is only shown when there are unsaved changes.
        case .save:
            Task { await saveUserDetails() }
        case .presentMediaSource:
            state.bindings.showMediaSheet = true
        case .displayCameraPicker:
            guard appMediator.isCameraAvailable else {
                MXLog.info("Camera unavailable, not presenting the picker.")
                userIndicatorController.submitIndicator(UserIndicator(title: L10n.errorCameraUnavailable))
                return
            }
            actionsSubject.send(.displayCameraPicker)
        case .displayMediaPicker:
            actionsSubject.send(.displayMediaPicker)
        case .displayFilePicker:
            actionsSubject.send(.displayFilePicker)
        case .removeImage:
            state.localMedia = nil
            state.selectedAvatarURL = nil
        // AGENT-PLATFORM: feed (Brief 0082)
        case .retryLoadingBio:
            guard state.bio == .loadFailed else { return }
            Task { await loadBio() }
        case .bioChanged(let previous):
            limitBio(editedFrom: previous)
        }
    }
    
    func didSelectMediaURL(url: URL) {
        Task {
            let userIndicatorID = UUID().uuidString
            defer { userIndicatorController.retractIndicatorWithId(userIndicatorID) }
            userIndicatorController.submitIndicator(UserIndicator(id: userIndicatorID,
                                                                  type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                                  title: L10n.commonLoading,
                                                                  persistent: true))
            
            guard case let .success(maxUploadSize) = await clientProxy.maxMediaUploadSize else {
                MXLog.error("Failed to get max upload size")
                state.bindings.alertInfo = .init(id: .unknown)
                return
            }
            let mediaResult = await mediaUploadingPreprocessor.processMedia(at: url, maxUploadSize: maxUploadSize)
            
            switch mediaResult {
            case .success(.image):
                state.localMedia = try? mediaResult.get()
            case .failure, .success:
                state.bindings.alertInfo = .init(id: .failedProcessingMedia)
            }
        }
    }
    
    // MARK: - Private
    
    private func showUnsavedChangesAlert() {
        state.bindings.alertInfo = .init(id: .unsavedChanges,
                                         title: L10n.dialogUnsavedChangesTitle,
                                         message: L10n.dialogUnsavedChangesDescription,
                                         primaryButton: .init(title: L10n.actionSave) { Task { await self.saveUserDetails() } },
                                         secondaryButton: .init(title: L10n.actionDiscard, role: .cancel) { self.actionsSubject.send(.dismiss) })
    }
    
    private func saveUserDetails() async {
        let userIndicatorID = UUID().uuidString
        defer {
            userIndicatorController.retractIndicatorWithId(userIndicatorID)
        }
        userIndicatorController.submitIndicator(UserIndicator(id: userIndicatorID,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                              title: L10n.screenEditProfileUpdatingDetails,
                                                              persistent: true))
        
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                if state.avatarDidChange {
                    group.addTask {
                        try await self.saveAvatar()
                    }
                }
                
                if state.nameDidChange {
                    group.addTask {
                        try await self.saveDisplayName()
                    }
                }
                
                // AGENT-PLATFORM: feed (Brief 0082)
                if state.bioDidChange {
                    let bio = state.normalisedBio
                    group.addTask {
                        try await self.saveBio(bio)
                    }
                }
                
                try await group.waitForAll()
            }
            
            actionsSubject.send(.dismiss)
        } catch is UserDetailsEditBioSaveError {
            // AGENT-PLATFORM: feed (Brief 0082): the typed bio stays in the field.
            state.bindings.alertInfo = .init(id: .bioSaveError,
                                             title: L10n.screenEditProfileErrorTitle,
                                             message: UntranslatedL10n.screenEditProfileBioSaveFailed)
        } catch {
            state.bindings.alertInfo = .init(id: .saveError,
                                             title: L10n.screenEditProfileErrorTitle,
                                             message: L10n.screenEditProfileError)
        }
    }
    
    private func saveAvatar() async throws {
        if let localMedia = state.localMedia {
            try await clientProxy.setUserAvatar(media: localMedia).get()
        } else if state.selectedAvatarURL == nil {
            try await clientProxy.removeUserAvatar().get()
        }
    }
    
    private func saveDisplayName() async throws {
        try await clientProxy.setUserDisplayName(state.bindings.name).get()
    }
    
    // MARK: Bio
    
    // AGENT-PLATFORM: feed (Brief 0082, decision 284). Offered only when the server allows the field. A failed
    // check reads as not allowed: no field this time, and the next opening of the screen (a new model) checks again.
    private func loadBio() async {
        guard await clientProxy.canSetUserBio() else {
            state.bio = .unavailable
            return
        }
        
        state.bio = .loading // A retry's.
        switch await clientProxy.userBio() {
        case .success(let bio):
            state.bindings.bio = bio ?? ""
            state.bio = .loaded(bio)
        case .failure:
            state.bio = .loadFailed
        }
    }
    
    /// AGENT-PLATFORM (1.0.3 B11, operator 2026-11-18): the field stops at the limit, so Save never waits on the bio
    /// and Back always gets the unsaved-changes alert. The stored bio, as loaded, stays as it is even when longer.
    private func limitBio(editedFrom previous: String) {
        guard case let .loaded(savedBio) = state.bio, state.bindings.bio != (savedBio ?? "") else { return }
        let limited = FeedBio.limited(state.bindings.bio, editing: previous)
        if limited != state.bindings.bio {
            state.bindings.bio = limited
        }
    }
    
    /// `bio` is already normalised; an empty one removes the field.
    private func saveBio(_ bio: String) async throws {
        let result = if bio.isEmpty {
            await clientProxy.removeUserBio()
        } else {
            await clientProxy.setUserBio(bio)
        }
        
        guard case .success = result else {
            throw UserDetailsEditBioSaveError()
        }
        
        state.bindings.bio = bio
        state.bio = .loaded(bio.isEmpty ? nil : bio)
    }
}

// AGENT-PLATFORM: feed (Brief 0082)
private struct UserDetailsEditBioSaveError: Error { }
