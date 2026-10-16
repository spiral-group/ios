//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias CreateCompanyScreenViewModelType = StateStoreViewModelV2<CreateCompanyScreenViewState, CreateCompanyScreenViewAction>

class CreateCompanyScreenViewModel: CreateCompanyScreenViewModelType, CreateCompanyScreenViewModelProtocol {
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let userSession: UserSessionProtocol
    private let mediaUploadingPreprocessor: MediaUploadingPreprocessor
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private let actionsSubject: PassthroughSubject<CreateCompanyScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CreateCompanyScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(agentPlatformService: AgentPlatformServiceProtocol,
         userSession: UserSessionProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         appSettings: AppSettings) {
        self.agentPlatformService = agentPlatformService
        self.userSession = userSession
        mediaUploadingPreprocessor = MediaUploadingPreprocessor(appSettings: appSettings)
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: CreateCompanyScreenViewState(),
                   mediaProvider: userSession.mediaProvider)
    }
    
    override func process(viewAction: CreateCompanyScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .create:
            Task { await create() }
        case .cancel:
            actionsSubject.send(.cancel)
        case .displayCameraPicker:
            actionsSubject.send(.displayCameraPicker)
        case .displayMediaPicker:
            actionsSubject.send(.displayMediaPicker)
        case .displayFilePicker:
            actionsSubject.send(.displayFilePicker)
        case .removeImage:
            state.avatarMediaInfo = nil
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
                state.avatarMediaInfo = try? mediaResult.get()
            case .failure, .success:
                state.bindings.alertInfo = AlertInfo(id: .failedProcessingMedia)
            }
        }
    }
    
    // MARK: - Private
    
    private func create() async {
        state.isCreating = true
        defer { state.isCreating = false }
        
        let name = state.bindings.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let industry = state.bindings.industry.trimmingCharacters(in: .whitespacesAndNewlines)
        let website = state.bindings.website.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Deferred logo (CreateRoom canon): upload the accumulated media
        // with the owner's own token, take the mxc, send it as
        // `branding_mxc` inside the ONE create call. Client-side upload
        // needs no org id, so the logo lands atomically with the space.
        var brandingMXC: String?
        if let media = state.avatarMediaInfo {
            switch await userSession.clientProxy.uploadMedia(media) {
            case .success(let mxc):
                brandingMXC = mxc
            case .failure(let error):
                MXLog.error("Failed to upload the company logo: \(error)")
                state.bindings.alertInfo = AlertInfo(id: .failedUploadingLogo,
                                                     title: UntranslatedL10n.screenCreateCompanyLogoFailure)
                return
            }
        }
        
        switch await agentPlatformService.createCompany(name: name,
                                                        industry: industry.isEmpty ? nil : industry,
                                                        website: website.isEmpty ? nil : website,
                                                        brandingMXC: brandingMXC) {
        case .success(let space):
            actionsSubject.send(.created(space))
        case .failure(let error):
            MXLog.error("Failed to create company: \(error)")
            state.bindings.alertInfo = AlertInfo(id: .createFailed,
                                                 title: UntranslatedL10n.screenCreateCompanyFailure)
        }
    }
}
