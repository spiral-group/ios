//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0037 — create-company (0037-H) and
// create-agent (0037-F) sheet forms.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct CreateCompanyScreenViewModelTests {
    private func makeViewModel(service: AgentPlatformServiceMock? = nil,
                               clientProxy: ClientProxyMock? = nil) -> CreateCompanyScreenViewModel {
        CreateCompanyScreenViewModel(agentPlatformService: service ?? AgentPlatformServiceMock(),
                                     userSession: UserSessionMock(.init(clientProxy: clientProxy ?? ClientProxyMock(.init()))),
                                     userIndicatorController: UserIndicatorControllerMock())
    }
    
    @Test
    func canCreate_requiresNonEmptyName() {
        let viewModel = makeViewModel()
        #expect(viewModel.context.viewState.canCreate == false)
        
        viewModel.context.name = "  Acme  "
        #expect(viewModel.context.viewState.canCreate == true)
    }
    
    @Test
    func create_success_emitsCreatedWithTrimmedFields() async throws {
        let service = AgentPlatformServiceMock()
        let space = AgentSpaceSummary(orgID: "org-acme", name: "Acme", kind: .company, avatarMXC: nil, agentCount: 0)
        service.createCompanyNameIndustryWebsiteBrandingMXCReturnValue = .success(space)
        
        let viewModel = makeViewModel(service: service)
        viewModel.context.name = " Acme "
        viewModel.context.industry = ""
        viewModel.context.website = " acme.com "
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .created(let created) = action { return created.orgID == "org-acme" }
            return false
        }
        viewModel.context.send(viewAction: .create)
        try await deferred.fulfill()
        
        let args = service.createCompanyNameIndustryWebsiteBrandingMXCReceivedArguments
        #expect(args?.name == "Acme")
        #expect(args?.industry == nil)
        #expect(args?.website == "acme.com")
        // No logo picked → no upload, no branding_mxc.
        #expect(args?.brandingMXC == nil)
    }
    
    @Test
    func create_withLogo_uploadsDeferredAndSendsBrandingMXC() async throws {
        // Brief 0039 S3 deferred save: the logo accumulated as local
        // MediaInfo uploads via clientProxy.uploadMedia at Create time
        // and the mxc rides the ONE create call as branding_mxc.
        let service = AgentPlatformServiceMock()
        let space = AgentSpaceSummary(orgID: "org-acme", name: "Acme", kind: .company, avatarMXC: "mxc://host/logo", agentCount: 0)
        service.createCompanyNameIndustryWebsiteBrandingMXCReturnValue = .success(space)
        
        let clientProxy = ClientProxyMock(.init())
        clientProxy.uploadMediaReturnValue = .success("mxc://host/logo")
        
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        viewModel.context.name = "Acme"
        viewModel.state.avatarMediaInfo = .image(imageURL: .picturesDirectory,
                                                 thumbnailURL: .picturesDirectory,
                                                 imageInfo: .init(height: 1, width: 1, mimetype: "image/png", size: nil, thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: nil))
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .created = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .create)
        try await deferred.fulfill()
        
        #expect(clientProxy.uploadMediaCallsCount == 1)
        #expect(service.createCompanyNameIndustryWebsiteBrandingMXCReceivedArguments?.brandingMXC == "mxc://host/logo")
    }
    
    @Test
    func create_logoUploadFailure_alertsAndDoesNotCreate() async throws {
        let service = AgentPlatformServiceMock()
        let clientProxy = ClientProxyMock(.init())
        clientProxy.uploadMediaReturnValue = .failure(.failedUploadingMedia(.unknown))
        
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        viewModel.context.name = "Acme"
        viewModel.state.avatarMediaInfo = .image(imageURL: .picturesDirectory,
                                                 thumbnailURL: .picturesDirectory,
                                                 imageInfo: .init(height: 1, width: 1, mimetype: "image/png", size: nil, thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: nil))
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .failedUploadingLogo }
        viewModel.context.send(viewAction: .create)
        try await deferred.fulfill()
        
        #expect(service.createCompanyNameIndustryWebsiteBrandingMXCCallsCount == 0)
    }
    
    @Test
    func removeImage_clearsTheAccumulatedLogo() {
        let viewModel = makeViewModel()
        viewModel.state.avatarMediaInfo = .image(imageURL: .picturesDirectory,
                                                 thumbnailURL: .picturesDirectory,
                                                 imageInfo: .init(height: 1, width: 1, mimetype: "image/png", size: nil, thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: nil))
        #expect(viewModel.context.viewState.avatarMediaInfo != nil)
        
        viewModel.context.send(viewAction: .removeImage)
        #expect(viewModel.context.viewState.avatarMediaInfo == nil)
    }
    
    @Test
    func create_failure_showsAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.createCompanyNameIndustryWebsiteBrandingMXCReturnValue = .failure(.validation(detail: "empty name"))
        
        let viewModel = makeViewModel(service: service)
        viewModel.context.name = "Acme"
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .createFailed }
        viewModel.context.send(viewAction: .create)
        try await deferred.fulfill()
    }
}

@MainActor
struct CreateAgentScreenViewModelTests {
    private func makeViewModel(service: AgentPlatformServiceMock) -> CreateAgentScreenViewModel {
        CreateAgentScreenViewModel(companyID: "org-acme",
                                   companyName: "Acme Corp",
                                   agentPlatformService: service)
    }
    
    /// Step B.8: «Продажи · Кофейня Зерно», in the app's language.
    @Test
    func defaultDisplayName_followsSelectedRole() {
        let viewModel = makeViewModel(service: AgentPlatformServiceMock())
        #expect(viewModel.context.viewState.defaultDisplayName == "\(UntranslatedL10n.screenCreateAgentRoleSales) · Acme Corp")
        
        viewModel.context.send(viewAction: .selectRole(.support))
        #expect(viewModel.context.viewState.defaultDisplayName == "\(UntranslatedL10n.screenCreateAgentRoleSupport) · Acme Corp")
    }
    
    @Test
    /// No typed name: the app sends its own default, since the server's is English.
    func create_success_sendsRoleAndTheDefaultName() async throws {
        let service = AgentPlatformServiceMock()
        service.createCompanyAgentCompanyIDRoleDisplayNameRoleBriefReturnValue = .success(())
        
        let viewModel = makeViewModel(service: service)
        viewModel.context.send(viewAction: .selectRole(.outreach))
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .created = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .create)
        try await deferred.fulfill()
        
        let args = service.createCompanyAgentCompanyIDRoleDisplayNameRoleBriefReceivedArguments
        #expect(args?.companyID == "org-acme")
        #expect(args?.role == "outreach")
        #expect(args?.displayName == "\(UntranslatedL10n.screenCreateAgentRoleOutreach) · Acme Corp")
        #expect(args?.roleBrief == nil)
    }
    
    @Test
    func create_sendsTrimmedRoleBriefInTheSameRequest() async throws {
        let service = AgentPlatformServiceMock()
        service.createCompanyAgentCompanyIDRoleDisplayNameRoleBriefReturnValue = .success(())
        
        let viewModel = makeViewModel(service: service)
        viewModel.context.roleBrief = "  Qualify inbound leads.  "
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .created = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .create)
        try await deferred.fulfill()
        
        let args = service.createCompanyAgentCompanyIDRoleDisplayNameRoleBriefReceivedArguments
        #expect(args?.roleBrief == "Qualify inbound leads.")
    }
    
    @Test
    func create_failure_showsAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.createCompanyAgentCompanyIDRoleDisplayNameRoleBriefReturnValue = .failure(.forbidden)
        
        let viewModel = makeViewModel(service: service)
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .createFailed }
        viewModel.context.send(viewAction: .create)
        try await deferred.fulfill()
    }
}
