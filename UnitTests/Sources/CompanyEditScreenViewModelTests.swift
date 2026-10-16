//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Brief 0039 S4b — company profile edit form on the
// RoomDetailsEdit canon (deferred save + unsaved-changes gate).
//

@testable import ElementX
import Combine
import Foundation
import Testing

@MainActor
struct CompanyEditScreenViewModelTests {
    private static let detail = AgentSpaceDetail(orgID: "org-acme",
                                                 name: "Acme Corporation",
                                                 kind: .company,
                                                 avatarMXC: "mxc://host/old-logo",
                                                 industry: "Logistics",
                                                 website: "acme.com",
                                                 agents: [])
    
    private func makeViewModel(service: AgentPlatformServiceMock? = nil,
                               clientProxy: ClientProxyMock? = nil,
                               detail: AgentSpaceDetail? = nil) -> CompanyEditScreenViewModel {
        CompanyEditScreenViewModel(detail: detail ?? Self.detail,
                                   agentPlatformService: service ?? AgentPlatformServiceMock(),
                                   userSession: UserSessionMock(.init(clientProxy: clientProxy ?? ClientProxyMock(.init()))),
                                   userIndicatorController: UserIndicatorControllerMock(),
                                   appSettings: .volatile())
    }
    
    private static func imageMediaInfo() -> MediaInfo {
        .image(imageURL: .picturesDirectory,
               thumbnailURL: .picturesDirectory,
               imageInfo: .init(height: 1, width: 1, mimetype: "image/png", size: nil, thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: nil))
    }
    
    @Test
    func seedsFromDetail_andCannotSaveUnchanged() {
        let viewModel = makeViewModel()
        #expect(viewModel.context.name == "Acme Corporation")
        #expect(viewModel.context.industry == "Logistics")
        #expect(viewModel.context.website == "acme.com")
        #expect(viewModel.context.viewState.canSave == false, "no change → Save disabled")
    }
    
    @Test
    func changedFieldsOnly_landInOnePatch() async throws {
        let service = AgentPlatformServiceMock()
        let updated = AgentSpaceSummary(orgID: "org-acme", name: "Acme Corp", kind: .company, avatarMXC: nil, agentCount: 0)
        service.updateCompanySpaceOrgIDNameIndustryWebsiteBrandingMXCReturnValue = .success(updated)
        
        let viewModel = makeViewModel(service: service)
        viewModel.context.name = "Acme Corp"
        #expect(viewModel.context.viewState.canSave == true)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .saveFinished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .save)
        try await deferred.fulfill()
        
        let args = service.updateCompanySpaceOrgIDNameIndustryWebsiteBrandingMXCReceivedArguments
        #expect(args?.orgID == "org-acme")
        #expect(args?.name == "Acme Corp")
        #expect(args?.industry == nil, "unchanged fields stay out of the patch")
        #expect(args?.website == nil)
        #expect(args?.brandingMXC == nil, "unchanged logo stays out of the patch")
    }
    
    @Test
    func changedLogo_uploadsDeferredAndPatchesMXC() async throws {
        let service = AgentPlatformServiceMock()
        service.updateCompanySpaceOrgIDNameIndustryWebsiteBrandingMXCReturnValue = .success(AgentSpaceSummary(orgID: "org-acme", name: "Acme Corporation", kind: .company, avatarMXC: "mxc://host/new-logo", agentCount: 0))
        let clientProxy = ClientProxyMock(.init())
        clientProxy.uploadMediaReturnValue = .success("mxc://host/new-logo")
        
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        viewModel.state.localMedia = Self.imageMediaInfo()
        #expect(viewModel.context.viewState.canSave == true)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .saveFinished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .save)
        try await deferred.fulfill()
        
        #expect(clientProxy.uploadMediaCallsCount == 1)
        #expect(service.updateCompanySpaceOrgIDNameIndustryWebsiteBrandingMXCReceivedArguments?.brandingMXC == "mxc://host/new-logo")
    }
    
    @Test
    func removeLogo_patchesEmptyStringClear() async throws {
        let service = AgentPlatformServiceMock()
        service.updateCompanySpaceOrgIDNameIndustryWebsiteBrandingMXCReturnValue = .success(AgentSpaceSummary(orgID: "org-acme", name: "Acme Corporation", kind: .company, avatarMXC: nil, agentCount: 0))
        let clientProxy = ClientProxyMock(.init())
        
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        viewModel.context.send(viewAction: .removeImage)
        #expect(viewModel.context.viewState.canSave == true, "removing the existing logo is a change")
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .saveFinished = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .save)
        try await deferred.fulfill()
        
        #expect(clientProxy.uploadMediaCallsCount == 0, "clear uploads nothing")
        #expect(service.updateCompanySpaceOrgIDNameIndustryWebsiteBrandingMXCReceivedArguments?.brandingMXC == "", "empty string = explicit clear")
    }
    
    @Test
    func logoUploadFailure_alertsAndDoesNotPatch() async throws {
        let service = AgentPlatformServiceMock()
        let clientProxy = ClientProxyMock(.init())
        clientProxy.uploadMediaReturnValue = .failure(.failedUploadingMedia(.unknown))
        
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        viewModel.state.localMedia = Self.imageMediaInfo()
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .failedUploadingLogo }
        viewModel.context.send(viewAction: .save)
        try await deferred.fulfill()
        
        #expect(service.updateCompanySpaceOrgIDNameIndustryWebsiteBrandingMXCCallsCount == 0)
    }
    
    @Test
    func cancelWithUnsavedChanges_gatesWithAlert() async throws {
        let viewModel = makeViewModel()
        viewModel.context.name = "Renamed"
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .unsavedChanges }
        viewModel.context.send(viewAction: .cancel)
        try await deferred.fulfill()
    }
    
    @Test
    func cancelWithoutChanges_dismissesImmediately() async throws {
        let viewModel = makeViewModel()
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .cancel = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .cancel)
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.bindings.alertInfo == nil)
    }
    
    @Test
    func saveFailure_showsAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.updateCompanySpaceOrgIDNameIndustryWebsiteBrandingMXCReturnValue = .failure(.forbidden)
        
        let viewModel = makeViewModel(service: service)
        viewModel.context.name = "Renamed"
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .saveFailed }
        viewModel.context.send(viewAction: .save)
        try await deferred.fulfill()
    }
}
