//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Brief 0037 — agent-in-room screen (artboard 0037-E).
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct AgentInRoomScreenViewModelTests {
    private static let agent = AgentSpaceAgentCard(agentID: "agent-1",
                                                   matrixUserID: "@assistant-owner:spiral.md",
                                                   displayName: "Personal Assistant",
                                                   avatarMXC: nil,
                                                   kind: "personal_assistant",
                                                   visibility: "public",
                                                   lifecycleState: "active",
                                                   roomCount: 1,
                                                   activeToolCount: 1)
    
    private static let tool = AgentRoomToolSummary(toolID: "t1",
                                                   toolKind: "translate",
                                                   targetLanguages: ["en"])
    
    private static let room = AgentRoomEntry(roomID: "!dm:host",
                                             displayName: "Alice",
                                             kind: "dm",
                                             activeTools: [tool])
    
    private func makeViewModel(service: AgentPlatformServiceMock,
                               room: AgentRoomEntry = Self.room,
                               clientProxy: ClientProxyMock = ClientProxyMock(.init())) -> AgentInRoomScreenViewModel {
        AgentInRoomScreenViewModel(agent: .init(card: Self.agent),
                                   room: room,
                                   agentPlatformService: service,
                                   clientProxy: clientProxy,
                                   mediaProvider: MediaProviderMock(.init()))
    }
    
    /// The owner's own chat with the agent is theirs with it (357 item 6).
    @Test
    func theOwnersOwnChatWithTheAgentHasNoRemove() {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success(Self.room.roomID)
        let service = AgentPlatformServiceMock()
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        
        #expect(!viewModel.context.viewState.canRemoveFromRoom)
        
        viewModel.context.send(viewAction: .removeTapped)
        viewModel.context.send(viewAction: .confirmRemove)
        
        #expect(viewModel.context.viewState.bindings.alertInfo == nil)
        #expect(service.leaveRoomAgentIDRoomIDCallsCount == 0)
    }
    
    @Test
    func anyOtherChatKeepsRemove() {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success("!another:host")
        
        #expect(makeViewModel(service: AgentPlatformServiceMock(), clientProxy: clientProxy).context.viewState.canRemoveFromRoom)
    }
    
    /// A DM the agent was added to reads as it does on this device, not as the server's «X and Y» (357 item 5).
    @Test
    func theChatReadsAsItDoesOnThisDevice() {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierClosure = { .mock(id: $0, name: "Stage A") }
        let room = AgentRoomEntry(roomID: "!dm:host", displayName: "Personal Assistant and Stage A", kind: "group", activeTools: [])
        
        #expect(makeViewModel(service: AgentPlatformServiceMock(), room: room, clientProxy: clientProxy).context.viewState.roomTitle == "Stage A")
    }
    
    @Test
    func removeTapped_asksForConfirmationFirst() {
        let service = AgentPlatformServiceMock()
        let viewModel = makeViewModel(service: service)
        
        viewModel.context.send(viewAction: .removeTapped)
        
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .confirmRemove)
        #expect(service.leaveRoomAgentIDRoomIDCallsCount == 0)
    }
    
    @Test
    func confirmRemove_success_emitsRemoved() async throws {
        let service = AgentPlatformServiceMock()
        service.leaveRoomAgentIDRoomIDReturnValue = .success(())
        
        let viewModel = makeViewModel(service: service)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .removed = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .confirmRemove)
        try await deferred.fulfill()
        
        #expect(service.leaveRoomAgentIDRoomIDReceivedArguments?.agentID == "agent-1")
        #expect(service.leaveRoomAgentIDRoomIDReceivedArguments?.roomID == "!dm:host")
    }
    
    @Test
    func confirmRemove_failure_showsAlertAndStops() async throws {
        let service = AgentPlatformServiceMock()
        service.leaveRoomAgentIDRoomIDReturnValue = .failure(.forbidden)
        
        let viewModel = makeViewModel(service: service)
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .removeFailed }
        viewModel.context.send(viewAction: .confirmRemove)
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.isRemoving == false)
    }

    /// Question 359, item 7: the chat itself, by the room this screen is about.
    @Test
    func openChat_asksForThisScreensRoom() async throws {
        let viewModel = makeViewModel(service: AgentPlatformServiceMock())
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .openChat(let roomID) = action { return roomID == Self.room.roomID }
            return false
        }
        viewModel.context.send(viewAction: .openChat)
        try await deferred.fulfill()
    }

    @Test
    func addTool_emitsHandoffAction() async throws {
        let service = AgentPlatformServiceMock()
        let viewModel = makeViewModel(service: service)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .addTool = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .addTool)
        try await deferred.fulfill()
    }

    @Test
    func translationSummary_usesStructuredCodesInsteadOfServerCopy() {
        let tool = AgentRoomToolSummary(toolID: "t1",
                                        toolKind: "live_translate",
                                        targetLanguages: ["zh-Hans", "pt-BR"])
        let names = ["zh-Hans", "pt-BR"]
            .map { TranslationLanguageDisplayName.localizedName(for: $0) }
            .joined(separator: ", ")

        #expect(tool.localizedTitle == UntranslatedL10n.screenAgentToolsListTitleTranslate(names))
        #expect(!tool.localizedTitle.contains("zh-Hans"))
        #expect(!tool.localizedTitle.contains("pt-BR"))
    }
    
    // MARK: - B3: the app's own words for every tool and trigger
    
    @Test
    func everyKindIsNamedAndTimedInTheAppsLanguage() {
        let textKinds = ["translate", "simplify", "correct", "rephrase", "summarize", "custom"]
        let callKinds = ["live_translate", "call_summary", "call_recording"]
        for kind in textKinds {
            let tool = AgentRoomToolSummary(toolID: kind, toolKind: kind, targetLanguages: [], firing: .onMessage)
            #expect(tool.localizedTitle == ToolDisplayName.name(forKind: kind))
            #expect(tool.localizedTrigger() == UntranslatedL10n.screenAgentRoomToolTriggerMessages)
        }
        for kind in callKinds {
            let tool = AgentRoomToolSummary(toolID: kind, toolKind: kind, targetLanguages: [], firing: .onVoiceCall)
            #expect(tool.localizedTitle == ToolDisplayName.name(forKind: kind))
            #expect(tool.localizedTrigger() == UntranslatedL10n.screenAgentRoomToolTriggerCalls)
        }
        // Every kind the app can arm is covered by one of the two lists.
        #expect(Set(AgentToolKind.allCases.map(\.rawValue)).isSubset(of: Set(textKinds + callKinds)))
    }
    
    @Test
    func aKindNewerThanTheAppGetsAGenericLabelAndNoTrigger() {
        let tool = AgentRoomToolSummary(toolID: "t9", toolKind: "teleport", targetLanguages: [])
        #expect(tool.localizedTitle == UntranslatedL10n.screenAgentToolsListTitleUnknown)
        #expect(tool.localizedTrigger() == nil)
    }
    
    // MARK: - B7: the owner DM's title
    
    @Test
    func theOwnerDMIsTitledAsTheOwnersChat() {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success(Self.room.roomID)
        let viewModel = makeViewModel(service: AgentPlatformServiceMock(), clientProxy: clientProxy)
        #expect(viewModel.context.viewState.roomTitle == UntranslatedL10n.screenAgentRoomOwnerDm)
        
        let other = makeViewModel(service: AgentPlatformServiceMock())
        #expect(other.context.viewState.roomTitle == "Alice")
    }
    
    // MARK: - Step B: a tool opens its form
    
    @Test
    func aToolOpensItsFormFromTheRoomsOwnRead() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(RoomToolsView(roomID: Self.room.roomID,
                                                                         agents: [RoomToolAgentEntry(agentID: Self.agent.agentID,
                                                                                                     matrixUserID: Self.agent.matrixUserID,
                                                                                                     displayName: Self.agent.displayName,
                                                                                                     ownerUserID: "@owner:host",
                                                                                                     isMine: true,
                                                                                                     tools: [RoomToolView(toolID: "t1",
                                                                                                                          toolKind: "translate",
                                                                                                                          triggerKind: "on_message",
                                                                                                                          targetLanguage: "en",
                                                                                                                          params: .translate(targetLanguage: "en"),
                                                                                                                          trigger: .onMessage(senderScope: .anyone),
                                                                                                                          safeSliceSalt: "s", appliesToViewer: .yes)])]))
        let viewModel = makeViewModel(service: service)
        
        let opened = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .editTool(let detail) = action { return detail.toolID == "t1" && detail.params == .translate(targetLanguage: "en") }
            return false
        }
        viewModel.context.send(viewAction: .selectTool(id: "t1"))
        try await opened.fulfill()
    }
    
    /// A chat the owner isn't in can't be read for the tool: say so, open nothing.
    @Test
    func aToolThatCantBeReadSaysSo() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .failure(.forbidden)
        let viewModel = makeViewModel(service: service)
        
        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .toolUnavailable }
        viewModel.context.send(viewAction: .selectTool(id: "t1"))
        try await alerted.fulfill()
        #expect(viewModel.context.viewState.openingToolID == nil)
    }
    
    /// The line is the server's trigger and audience in the app's words; a
    /// value this build doesn't know leaves its half out.
    @Test
    func theTriggerLineCarriesTheAudience() {
        let anyone = AgentRoomToolSummary(toolID: "t1", toolKind: "translate", targetLanguages: ["en"], firing: .onMessage, audience: .anyone)
        #expect(anyone.localizedTrigger() == "\(UntranslatedL10n.screenAgentRoomToolTriggerMessages) · \(UntranslatedL10n.screenAgentRoomToolAudienceAnyone)")
        let owner = AgentRoomToolSummary(toolID: "t2", toolKind: "call_summary", targetLanguages: [], firing: .onVoiceCall, audience: .ownerOnly)
        #expect(owner.localizedTrigger() == "\(UntranslatedL10n.screenAgentRoomToolTriggerCalls) · \(UntranslatedL10n.screenAgentRoomToolAudienceOwner)")
        let newer = AgentRoomToolSummary(toolID: "t3", toolKind: "translate", targetLanguages: ["en"], firing: nil,
                                         audience: .unknown(tag: "new", members: []))
        #expect(newer.localizedTrigger() == nil)
    }
    
    /// Chosen people are named when the chat's member list knows every one of
    /// them, else the general words.
    @Test
    func chosenPeopleAreNamedWhenKnown() {
        let specific = AgentRoomToolSummary(toolID: "t1", toolKind: "translate", targetLanguages: ["en"], firing: .onMessage,
                                            audience: .specificSenders(members: ["@bob:host", "@eve:host"]))
        let names = ["@bob:host": "Bob", "@eve:host": "Eve"]
        #expect(specific.localizedTrigger(memberNames: names)
            == "\(UntranslatedL10n.screenAgentRoomToolTriggerMessages) · \(UntranslatedL10n.screenAgentRoomToolAudienceSpecificNamed("Bob, Eve"))")
        #expect(specific.localizedTrigger(memberNames: ["@bob:host": "Bob"])
            == "\(UntranslatedL10n.screenAgentRoomToolTriggerMessages) · \(UntranslatedL10n.screenAgentRoomToolAudienceSpecific)")
        
        let except = AgentRoomToolSummary(toolID: "t2", toolKind: "live_translate", targetLanguages: ["en"], firing: .onVoiceCall,
                                          audience: .everyoneExcept(members: ["@bob:host"]))
        #expect(except.localizedTrigger(memberNames: names)
            == "\(UntranslatedL10n.screenAgentRoomToolTriggerCalls) · \(UntranslatedL10n.screenAgentRoomToolAudienceExceptNamed("Bob"))")
        #expect(except.localizedTrigger()
            == "\(UntranslatedL10n.screenAgentRoomToolTriggerCalls) · \(UntranslatedL10n.screenAgentRoomToolAudienceExcept)")
    }
    
    /// The screen reads the names from this device's copy of the chat.
    @Test
    func theScreenNamesTheChosenPeople() async throws {
        let tool = AgentRoomToolSummary(toolID: "t1", toolKind: "translate", targetLanguages: ["en"], firing: .onMessage,
                                        audience: .specificSenders(members: ["@bob:host"]))
        let bob = RoomMemberProxyMock(with: .init(userID: "@bob:host", displayName: "Bob", membership: .join))
        let roomProxy = JoinedRoomProxyMock(.init(id: Self.room.roomID, members: [bob]))
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }
        
        let viewModel = makeViewModel(service: AgentPlatformServiceMock(),
                                      room: .init(roomID: Self.room.roomID, displayName: "Team", kind: "group", activeTools: [tool]),
                                      clientProxy: clientProxy)
        let named = deferFulfillment(viewModel.context.observe(\.viewState.memberNames)) { $0 == ["@bob:host": "Bob"] }
        try await named.fulfill()
    }
}
