//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias RoomMembersListScreenViewModelType = StateStoreViewModel<RoomMembersListScreenViewState, RoomMembersListScreenViewAction>

class RoomMembersListScreenViewModel: RoomMembersListScreenViewModelType, RoomMembersListScreenViewModelProtocol {
    private let userSession: UserSessionProtocol
    private let roomProxy: JoinedRoomProxyProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let analytics: AnalyticsServiceProtocol
    
    private var members: [RoomMemberProxyProtocol] = []
    /// AGENT-PLATFORM (1.0.3 B14): which members read is the newest, so an older one's answer doesn't override it.
    private var membersReadGeneration = 0
    private var currentUserProxy: RoomMemberProxyProtocol?
    
    // AGENT-PLATFORM (Brief 0072, ADR-0083)
    private var presenceScope: PresenceScope?
    private var visibleMemberIDs = Set<String>()
    private let visibleMembersSubject = PassthroughSubject<Set<String>, Never>()
    private var memberIDs = Set<String>()
    
    private var actionsSubject: PassthroughSubject<RoomMembersListScreenViewModelAction, Never> = .init()
    
    var actions: AnyPublisher<RoomMembersListScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(initialMode: RoomMembersListScreenMode = .members,
         userSession: UserSessionProtocol,
         roomProxy: JoinedRoomProxyProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         analytics: AnalyticsServiceProtocol) {
        self.userSession = userSession
        self.roomProxy = roomProxy
        self.userIndicatorController = userIndicatorController
        self.analytics = analytics
        
        super.init(initialViewState: .init(joinedMembersCount: roomProxy.infoPublisher.value.joinedMembersCount,
                                           bindings: .init(mode: initialMode)),
                   mediaProvider: userSession.mediaProvider)
        
        setupMembers()
        setupPresence()
    }
    
    // MARK: - Public
    
    override func process(viewAction: RoomMembersListScreenViewAction) {
        switch viewAction {
        case .selectMember(let member):
            selectMember(member)
        case .invite:
            actionsSubject.send(.invite)
        case .memberAppeared(let userID):
            visibleMemberIDs.insert(userID)
            visibleMembersSubject.send(visibleMemberIDs)
        case .memberDisappeared(let userID):
            visibleMemberIDs.remove(userID)
            visibleMembersSubject.send(visibleMemberIDs)
        case .retry: // AGENT-PLATFORM (1.0.3 B14)
            state.hasFailedToLoad = false
            loadMembers()
        }
    }
    
    func stop() {
        hideLoadingIndicator(Self.setupMembersLoadingIndicatorIdentifier)
        hideLoadingIndicator(Self.updateStateLoadingIndicatorIdentifier)
        // AGENT-PLATFORM (Brief 0072, ADR-0083)
        presenceScope?.cancel()
    }
    
    // MARK: - Presence
    
    // AGENT-PLATFORM (Brief 0072, ADR-0083): the joined members on screen
    // are asked for as list rows; a scroll settles before the set is sent.
    private func setupPresence() {
        guard let presenceObserverService = userSession.presenceObserverService else { return }
        let presenceScope = PresenceScope(service: presenceObserverService)
        self.presenceScope = presenceScope
        
        visibleMembersSubject
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak presenceScope] userIDs in presenceScope?.observe(userIDs) }
            .store(in: &cancellables)
        
        presenceObserverService.presencePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presences in self?.updatePresences(presences) }
            .store(in: &cancellables)
    }
    
    /// Only this room's members: another screen's users are no news here.
    private func updatePresences(_ presences: [String: UserPresence]) {
        let roomPresences = presences.filter { memberIDs.contains($0.key) }
        if roomPresences != state.presences {
            state.presences = roomPresences
        }
    }
    
    // MARK: - Members
    
    private func setupMembers() {
        loadMembers()
        
        roomProxy.membersPublisher
            .combineLatest(roomProxy.identityStatusChangesPublisher)
            .filter { !$0.0.isEmpty }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] members, _ in
                self?.updateState(members: members)
            }
            .store(in: &cancellables)
        
        roomProxy.timeline.timelineItemProvider.membershipChangePublisher.sink { [weak self] _ in
            Task { await self?.updateMembers() } // AGENT-PLATFORM (1.0.3 B14): records the outcome.
        }
        .store(in: &cancellables)
        
        roomProxy.infoPublisher
            .map(\.powerLevels)
            .removeDuplicates { $0?.userPowerLevels == $1?.userPowerLevels }
            .sink { [weak self] _ in
                Task { await self?.updateMembers() } // AGENT-PLATFORM (1.0.3 B14): records the outcome.
            }
            .store(in: &cancellables)
    }
    
    private func loadMembers() {
        Task {
            showLoadingIndicator(Self.setupMembersLoadingIndicatorIdentifier)
            await updateMembers()
            hideLoadingIndicator(Self.setupMembersLoadingIndicatorIdentifier)
        }
    }
    
    /// AGENT-PLATFORM (1.0.3 B14): a failed read is kept, so it neither shimmers for good nor reads as an empty room.
    /// It counts only with nobody to show: cached members are on their way to the list, and Retry mustn't flash first.
    private func updateMembers() async {
        membersReadGeneration += 1
        let generation = membersReadGeneration
        let result = await roomProxy.updateMembers()
        guard generation == membersReadGeneration else { return }
        
        switch result {
        case .success:
            state.hasFailedToLoad = false
        case .failure:
            state.hasFailedToLoad = roomProxy.membersPublisher.value.isEmpty
        }
    }
    
    private func updateState(members: [RoomMemberProxyProtocol]) {
        Task {
            showLoadingIndicator(Self.updateStateLoadingIndicatorIdentifier)
            
            defer {
                hideLoadingIndicator(Self.updateStateLoadingIndicatorIdentifier)
            }
            
            let members = members.sorted(prioritisingRoomCallParticipants: roomProxy.infoPublisher.value.activeRoomCallParticipants)
            let roomMembersDetails = await buildMembersDetails(members: members)
            self.members = members
            self.currentUserProxy = members.first { $0.userID == roomProxy.ownUserID }
            
            var newBindings = state.bindings
            if roomMembersDetails.bannedMembers.isEmpty {
                newBindings.mode = .members
            }
            let hasFailedToLoad = state.hasFailedToLoad // AGENT-PLATFORM (1.0.3 B14)
            self.state = .init(joinedMembersCount: roomProxy.infoPublisher.value.joinedMembersCount,
                               joinedMembers: roomMembersDetails.joinedMembers,
                               invitedMembers: roomMembersDetails.invitedMembers,
                               bannedMembers: roomMembersDetails.bannedMembers,
                               bindings: newBindings)
            self.state.hasFailedToLoad = hasFailedToLoad // AGENT-PLATFORM (1.0.3 B14): the rebuild keeps the last read's outcome.
            
            // AGENT-PLATFORM (Brief 0072, ADR-0083): the state was rebuilt;
            // the presence known so far carries over, for today's members.
            memberIDs = Set(members.map(\.userID))
            if let presences = userSession.presenceObserverService?.presencePublisher.value {
                updatePresences(presences)
            }
            
            if let powerLevels = roomProxy.infoPublisher.value.powerLevels {
                self.state.canInviteUsers = powerLevels.canOwnUserInvite()
                self.state.canKickUsers = powerLevels.canOwnUserKick()
                self.state.canBanUsers = powerLevels.canOwnUserBan()
            }
        }
    }
    
    private func buildMembersDetails(members: [RoomMemberProxyProtocol]) async -> RoomMembersDetails {
        // We don't care about identity statuses on non-encrypted rooms
        let isEncrypted = roomProxy.infoPublisher.value.isEncrypted
        let activeRoomCallParticipants = Set(roomProxy.infoPublisher.value.activeRoomCallParticipants)
        
        return await Task.detached { [weak self] in
            // accessing RoomMember's properties is very slow. We need to do it in a background thread.
            var invitedMembers: [RoomMemberListScreenEntry] = .init()
            var joinedMembers: [RoomMemberListScreenEntry] = .init()
            var bannedMembers: [RoomMemberListScreenEntry] = .init()
            
            for member in members {
                var verificationState: UserIdentityVerificationState = .notVerified
                if isEncrypted, let fetchedState = await self?.userIdentityVerificationState(for: member.userID) {
                    verificationState = fetchedState
                }
                let isActiveRoomCallParticipant = activeRoomCallParticipants.contains(member.userID)
                
                switch member.membership {
                case .invite:
                    invitedMembers.append(.init(member: .init(withProxy: member), verificationState: verificationState, isActiveRoomCallParticipant: isActiveRoomCallParticipant))
                case .join:
                    joinedMembers.append(.init(member: .init(withProxy: member), verificationState: verificationState, isActiveRoomCallParticipant: isActiveRoomCallParticipant))
                case .ban:
                    bannedMembers.append(.init(member: .init(withProxy: member), verificationState: verificationState, isActiveRoomCallParticipant: isActiveRoomCallParticipant))
                default:
                    continue
                }
            }
            
            return .init(invitedMembers: invitedMembers,
                         joinedMembers: joinedMembers,
                         bannedMembers: bannedMembers.sorted { $0.member.id.localizedStandardCompare($1.member.id) == .orderedAscending }) // Re-sort ignoring display name.
        }
        .value
    }
    
    /// The client proxy isn't Sendable, fetch identities through this helper so
    /// that it never leaves the main actor.
    private func userIdentityVerificationState(for userID: String) async -> UserIdentityVerificationState? {
        guard case let .success(userIdentity) = await userSession.clientProxy.userIdentity(for: userID, fallBackToServer: false) else {
            return nil
        }
        return userIdentity?.verificationState
    }
    
    private func selectMember(_ member: RoomMemberDetails) {
        guard currentUserProxy?.userID != member.id else {
            showMemberDetails(member)
            return
        }
        
        let manageMemberViewModel = ManageRoomMemberSheetViewModel(memberDetails: .memberDetails(roomMember: member),
                                                                   permissions: .init(canKick: state.canKickUsers,
                                                                                      canBan: state.canBanUsers,
                                                                                      ownPowerLevel: currentUserProxy?.powerLevel ?? .init(value: 0)),
                                                                   roomProxy: roomProxy,
                                                                   userIndicatorController: userIndicatorController,
                                                                   analyticsService: analytics,
                                                                   mediaProvider: userSession.mediaProvider)
        manageMemberViewModel.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss(let shouldShowDetails):
                state.bindings.manageMemeberViewModel = nil
                if shouldShowDetails {
                    showMemberDetails(member)
                }
            }
        }
        .store(in: &cancellables)
        state.bindings.manageMemeberViewModel = manageMemberViewModel
    }
    
    private func showMemberDetails(_ member: RoomMemberDetails) {
        guard let member = members.first(where: { $0.userID == member.id }) else {
            MXLog.error("Selected member \(member.id) not found")
            return
        }
        actionsSubject.send(.selectMember(member))
    }
    
    // MARK: - Indicators
    
    private static let setupMembersLoadingIndicatorIdentifier = "\(RoomMembersListScreenViewModel.self)-SetupMembers"
    private static let updateStateLoadingIndicatorIdentifier = "\(RoomMembersListScreenViewModel.self)-UpdateState"
    
    private func showLoadingIndicator(_ identifier: String) {
        userIndicatorController.submitIndicator(UserIndicator(id: identifier,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: false, allowsInteraction: true),
                                                              title: L10n.commonLoading,
                                                              persistent: true),
                                                delay: .milliseconds(200))
    }
    
    private func hideLoadingIndicator(_ identifier: String) {
        userIndicatorController.retractIndicatorWithId(identifier)
    }
}

private nonisolated struct RoomMembersDetails {
    var invitedMembers: [RoomMemberListScreenEntry]
    var joinedMembers: [RoomMemberListScreenEntry]
    var bannedMembers: [RoomMemberListScreenEntry]
}
