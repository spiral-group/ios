//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias MessageForwardingScreenViewModelType = StateStoreViewModel<MessageForwardingScreenViewState, MessageForwardingScreenViewAction>

class MessageForwardingScreenViewModel: MessageForwardingScreenViewModelType, MessageForwardingScreenViewModelProtocol {
    private static let maxSuggestedRoomCount = 5
    
    private let forwardingPayload: any MessageForwardingSource // AGENT-PLATFORM: feed (Brief 0082)
    private let clientProxy: ClientProxyProtocol
    private let roomSummaryProvider: RoomSummaryProviderProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    // AGENT-PLATFORM: feed (Brief 0082): the sheet went away mid-send; a source that stops there sends to no further room.
    private var isStopped = false
    
    private var actionsSubject: PassthroughSubject<MessageForwardingScreenViewModelAction, Never> = .init()
    
    var actions: AnyPublisher<MessageForwardingScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(forwardingPayload: any MessageForwardingSource, // AGENT-PLATFORM: feed (Brief 0082)
         userSession: UserSessionProtocol,
         roomSummaryProvider: RoomSummaryProviderProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.forwardingPayload = forwardingPayload
        clientProxy = userSession.clientProxy
        self.roomSummaryProvider = roomSummaryProvider
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: MessageForwardingScreenViewState(title: forwardingPayload.title), // AGENT-PLATFORM: feed (Brief 0082)
                   mediaProvider: userSession.mediaProvider)
        
        roomSummaryProvider.roomListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRooms()
            }
            .store(in: &cancellables)
        
        context.$viewState
            .map(\.bindings.searchQuery)
            .removeDuplicates()
            .sink { [weak self] searchQuery in
                if searchQuery.isEmpty {
                    self?.roomSummaryProvider.setFilter(.all(filters: []))
                } else {
                    self?.roomSummaryProvider.setFilter(.search(query: searchQuery))
                }
            }
            .store(in: &cancellables)
        
        updateRooms()
        
        Task { await loadSuggestedRooms() }
    }
    
    override func process(viewAction: MessageForwardingScreenViewAction) {
        switch viewAction {
        case .cancel:
            guard !state.isForwarding else { return } // AGENT-PLATFORM: feed (Brief 0082)
            actionsSubject.send(.dismiss)
        case .send:
            // AGENT-PLATFORM: feed (Brief 0082): a second tap must not send everything again.
            guard !state.isForwarding else { return }
            state.isForwarding = true
            Task { await forward() }
        case .selectRoom(let roomID):
            if state.selectedRoomIDs.contains(roomID) == false, state.selectedRoomIDs.count < state.maxRoomSelectionCount {
                state.selectedRoomIDs.insert(roomID)
            } else {
                state.selectedRoomIDs.remove(roomID)
            }
        case .reachedTop:
            updateVisibleRange(edge: .top)
        case .reachedBottom:
            updateVisibleRange(edge: .bottom)
        }
    }
    
    func stop() {
        isStopped = true // AGENT-PLATFORM: feed (Brief 0082)
        // This is a shared provider so we should reset the filtering when we are done with the view
        roomSummaryProvider.setFilter(.all(filters: []))
    }
    
    // MARK: - Private
    
    private func updateRooms() {
        state.rooms = roomSummaryProvider.roomListPublisher.value
            .filter { !forwardingPayload.excludes($0) && !$0.isTombstoned } // AGENT-PLATFORM: feed (Brief 0082)
            .map(MessageForwardingRoom.init(summary:))
    }
    
    /// Built from the room summaries: building room proxies is slow and would shift the list down when the section appears.
    private func loadSuggestedRooms() async {
        guard case let .success(roomIDs) = await clientProxy.recentlyVisitedRoomIDs() else { return }
        
        state.suggestedRooms = roomIDs
            .compactMap(clientProxy.roomSummaryForIdentifier)
            .filter { !forwardingPayload.excludes($0) && $0.isJoined && !$0.isSpace && !$0.isTombstoned } // AGENT-PLATFORM: feed (Brief 0082)
            .prefix(Self.maxSuggestedRoomCount)
            .map(MessageForwardingRoom.init(summary:))
    }
    
    /// The actual range values don't matter as long as they contain the lower
    /// or upper bounds. updateVisibleRange is a hybrid API that powers both
    /// sliding sync visible range update and list paginations
    /// For lists other than the home screen one we don't care about visible ranges,
    /// we just need the respective bounds to be there to trigger a next page load or
    /// a reset to just one page
    private func updateVisibleRange(edge: UIRectEdge) {
        switch edge {
        case .top:
            roomSummaryProvider.updateVisibleRange(0..<0)
        case .bottom:
            let roomCount = roomSummaryProvider.roomListPublisher.value.count
            roomSummaryProvider.updateVisibleRange(roomCount..<roomCount)
        default:
            break
        }
    }
    
    private func forward() async {
        guard !state.selectedRoomIDs.isEmpty else {
            fatalError()
        }
        
        var succeededRoomIdentifiers = [String]()
        var hasFailures = false
        // AGENT-PLATFORM: feed (Brief 0082): the rooms nothing reached, and what the source said about them.
        var failedRoomIdentifiers = [String]()
        var failureMessage: String?
        defer { state.isForwarding = false }
        
        for roomID in state.selectedRoomIDs {
            // AGENT-PLATFORM: feed (Brief 0082): dismissed mid-send, a feed share counts only the rooms already sent.
            guard !(isStopped && forwardingPayload.stopsWhenDismissed) else { break }
            
            guard case let .joined(targetRoomProxy) = await clientProxy.roomForIdentifier(roomID) else {
                MXLog.error("Failed retrieving room to forward to with id: \(roomID)")
                hasFailures = true
                failedRoomIdentifiers.append(roomID) // AGENT-PLATFORM: feed (Brief 0082)
                continue
            }
            
            // AGENT-PLATFORM: feed (Brief 0082): a feed post's content is built per room.
            let built = await forwardingPayload.contents(for: roomID)
            guard case .success(let contents) = built else {
                if case .failure(let error) = built {
                    failureMessage = error.message
                }
                hasFailures = true
                failedRoomIdentifiers.append(roomID)
                continue
            }
            
            // The contents are already in timeline order and the send queue preserves it.
            var sentCount = 0 // AGENT-PLATFORM: feed (Brief 0082)
            for content in contents {
                if case .failure(let error) = await targetRoomProxy.timeline.sendMessageEventContent(content) {
                    MXLog.error("Failed forwarding message with error: \(error)")
                    hasFailures = true
                } else {
                    sentCount += 1
                }
            }
            
            // AGENT-PLATFORM: feed (Brief 0082): a room nothing reached is not one sent to.
            guard sentCount > 0 else {
                failedRoomIdentifiers.append(roomID)
                continue
            }
            
            succeededRoomIdentifiers.append(roomID)
        }
        
        forwardingPayload.didFinish(sentRoomIDs: succeededRoomIdentifiers, failedRoomIDs: failedRoomIdentifiers) // AGENT-PLATFORM: feed (Brief 0082)
        
        if hasFailures {
            userIndicatorController.submitIndicator(UserIndicator(title: failureMessage ?? L10n.errorUnknown)) // AGENT-PLATFORM: feed (Brief 0082)
        } else if let sentMessage = forwardingPayload.sentMessage(roomCount: succeededRoomIdentifiers.count) { // AGENT-PLATFORM: feed (Brief 0082)
            userIndicatorController.submitIndicator(UserIndicator(title: sentMessage))
        }
        
        if !succeededRoomIdentifiers.isEmpty {
            actionsSubject.send(.sent(roomIDs: succeededRoomIdentifiers))
        }
    }
}
