//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias CompanyEditScreenViewModelType = StateStoreViewModelV2<CompanyEditScreenViewState, CompanyEditScreenViewAction>

class CompanyEditScreenViewModel: CompanyEditScreenViewModelType, CompanyEditScreenViewModelProtocol {
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let userSession: UserSessionProtocol
    private let mediaUploadingPreprocessor: MediaUploadingPreprocessor
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private let actionsSubject: PassthroughSubject<CompanyEditScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CompanyEditScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(detail: AgentSpaceDetail,
         agentPlatformService: AgentPlatformServiceProtocol,
         userSession: UserSessionProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         appSettings: AppSettings) {
        self.agentPlatformService = agentPlatformService
        self.userSession = userSession
        mediaUploadingPreprocessor = MediaUploadingPreprocessor(appSettings: appSettings)
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: CompanyEditScreenViewState(orgID: detail.orgID,
                                                                initialName: detail.name,
                                                                initialIndustry: detail.industry ?? "",
                                                                initialWebsite: detail.website ?? "",
                                                                initialLogoMXC: detail.avatarMXC,
                                                                logoMXC: detail.avatarMXC,
                                                                bindings: .init(name: detail.name,
                                                                                industry: detail.industry ?? "",
                                                                                website: detail.website ?? "")),
                   mediaProvider: userSession.mediaProvider)
    }
    
    override func process(viewAction: CompanyEditScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .cancel:
            cancel()
        case .save:
            Task { await save() }
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
            state.logoMXC = nil
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
                state.localMedia = try? mediaResult.get()
            case .failure, .success:
                state.bindings.alertInfo = AlertInfo(id: .failedProcessingMedia)
            }
        }
    }
    
    // MARK: - Private
    
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
        
        // Deferred logo: upload the replacement with the owner's own token
        // (the Element-room pattern); Remove sends the explicit empty-string
        // clear. `nil` keeps the field out of the patch entirely.
        var brandingMXC: String?
        if state.logoDidChange {
            if let media = state.localMedia {
                switch await userSession.clientProxy.uploadMedia(media) {
                case .success(let mxc):
                    brandingMXC = mxc
                case .failure(let error):
                    MXLog.error("Failed to upload the company logo: \(error)")
                    state.bindings.alertInfo = AlertInfo(id: .failedUploadingLogo,
                                                         title: UntranslatedL10n.screenCreateCompanyLogoFailure)
                    return
                }
            } else {
                brandingMXC = ""
            }
        }
        
        let name = state.bindings.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let industry = state.bindings.industry.trimmingCharacters(in: .whitespacesAndNewlines)
        let website = state.bindings.website.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch await agentPlatformService.updateCompanySpace(orgID: state.orgID,
                                                             name: state.nameDidChange ? name : nil,
                                                             industry: state.industryDidChange ? industry : nil,
                                                             website: state.websiteDidChange ? website : nil,
                                                             brandingMXC: brandingMXC) {
        case .success:
            actionsSubject.send(.saveFinished)
        case .failure(let error):
            MXLog.error("Failed to save the company profile: \(error)")
            state.bindings.alertInfo = AlertInfo(id: .saveFailed,
                                                 title: UntranslatedL10n.screenCompanyEditFailure)
        }
    }
}
