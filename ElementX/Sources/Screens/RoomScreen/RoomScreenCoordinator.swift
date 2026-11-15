//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import HTMLParser
import SwiftUI
import WysiwygComposer

struct RoomScreenCoordinatorParameters {
    let userSession: UserSessionProtocol
    let roomProxy: JoinedRoomProxyProtocol
    var focussedEvent: FocusEvent?
    var sharedText: String?
    let timelineController: TimelineControllerProtocol
    let mediaPlayerProvider: MediaPlayerProviderProtocol
    let emojiProvider: EmojiProviderProtocol
    let linkMetadataProvider: LinkMetadataProviderProtocol
    let completionSuggestionService: CompletionSuggestionServiceProtocol
    let ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never>
    let appMediator: AppMediatorProtocol
    let analytics: AnalyticsServiceProtocol
    let composerDraftService: ComposerDraftServiceProtocol
    let timelineControllerFactory: TimelineControllerFactoryProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum RoomScreenCoordinatorAction {
    case presentAIConsentSettings // AGENT-PLATFORM (decision 150)
    case presentReportContent(itemID: TimelineItemIdentifier, senderID: String)
    case presentMediaUploadPicker(mode: MediaPickerScreenMode, caption: NSAttributedString)
    case presentMediaUploadPreviewScreen(mediaURLs: [URL], caption: NSAttributedString)
    case presentRoomDetails
    case presentLocationPicker
    case presentPollForm(mode: PollFormMode)
    case presentLocationViewer(StaticLocationData)
    case presentLiveLocationViewer(sender: TimelineItemSender?, initialLiveLocationShare: LiveLocationShare?)
    case presentEmojiPicker(selectedEmojis: Set<String>, continuation: EmojiPickerScreenContinuation)
    case presentRoomMemberDetails(userID: String)
    case presentMessageForwarding(forwardingPayload: MessageForwardingPayload)
    case presentCallScreen(isVoiceCall: Bool)
    case presentPinnedEventsTimeline
    case presentResolveSendFailure(failure: TimelineItemSendFailure.VerifiedUser, resolver: VerifiedUserSendFailureResolver) // AGENT-PLATFORM: § 5.87
    case presentKnockRequestsList
    case presentThread(threadRootEventID: String, focussedEventID: String?)
    case presentRoom(roomID: String, via: [String])
    // AGENT-PLATFORM: the composer "+" and the in-chat active-tools banner open the chat's tools.
    case presentAgentTools
    case presentInteractivePostAgentPicker
    case presentInteractivePostEditor(eventID: String, post: SpiralAppPost, title: String)
}

final class RoomScreenCoordinator: CoordinatorProtocol {
    private var roomViewModel: RoomScreenViewModelProtocol
    private var timelineViewModel: TimelineViewModelProtocol
    private var composerViewModel: ComposerToolbarViewModelProtocol
    private let userSettings: UserSettings
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<RoomScreenCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<RoomScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: RoomScreenCoordinatorParameters) {
        userSettings = parameters.userSession.userSettings
        
        var selectedPinnedEventID: String?
        if let focussedEvent = parameters.focussedEvent {
            selectedPinnedEventID = focussedEvent.shouldSetPin ? focussedEvent.eventID : nil
        }
        
        roomViewModel = RoomScreenViewModel(userSession: parameters.userSession,
                                            roomProxy: parameters.roomProxy,
                                            initialSelectedPinnedEventID: selectedPinnedEventID,
                                            ongoingCallRoomIDPublisher: parameters.ongoingCallRoomIDPublisher,
                                            analyticsService: parameters.analytics,
                                            userIndicatorController: parameters.userIndicatorController)
        
        timelineViewModel = TimelineViewModel(roomProxy: parameters.roomProxy,
                                              focussedEventID: parameters.focussedEvent?.eventID,
                                              timelineController: parameters.timelineController,
                                              userSession: parameters.userSession,
                                              mediaPlayerProvider: parameters.mediaPlayerProvider,
                                              userIndicatorController: parameters.userIndicatorController,
                                              appMediator: parameters.appMediator,
                                              analyticsService: parameters.analytics,
                                              emojiProvider: parameters.emojiProvider,
                                              linkMetadataProvider: parameters.linkMetadataProvider,
                                              timelineControllerFactory: parameters.timelineControllerFactory)
        
        let wysiwygViewModel = WysiwygComposerViewModel(minHeight: ComposerConstant.minHeight,
                                                        maxCompressedHeight: ComposerConstant.maxHeight,
                                                        maxExpandedHeight: ComposerConstant.maxHeight,
                                                        parserStyle: .elementX)
        let composerViewModel = ComposerToolbarViewModel(initialText: parameters.sharedText,
                                                         roomProxy: parameters.roomProxy,
                                                         wysiwygViewModel: wysiwygViewModel,
                                                         completionSuggestionService: parameters.completionSuggestionService,
                                                         mediaProvider: parameters.userSession.mediaProvider,
                                                         mentionDisplayHelper: ComposerMentionDisplayHelper(timelineContext: timelineViewModel.context),
                                                         userSettings: parameters.userSession.userSettings,
                                                         analyticsService: parameters.analytics,
                                                         composerDraftService: parameters.composerDraftService)
        self.composerViewModel = composerViewModel
    }
    
    // MARK: - Public
    
    func start() {
        timelineViewModel.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .displayEmojiPicker(let selectedEmojis, let continuation):
                    actionsSubject.send(.presentEmojiPicker(selectedEmojis: selectedEmojis, continuation: continuation))
                case .displayReportContent(let itemID, let senderID):
                    actionsSubject.send(.presentReportContent(itemID: itemID, senderID: senderID))
                case .displayCameraPicker:
                    actionsSubject.send(.presentMediaUploadPicker(mode: .init(source: .camera, selectionType: .multipleItems),
                                                                  caption: composerViewModel.context.plainComposerText))
                case .displayMediaPicker:
                    actionsSubject.send(.presentMediaUploadPicker(mode: .init(source: .photoLibrary, selectionType: .multipleItems),
                                                                  caption: composerViewModel.context.plainComposerText))
                case .displayDocumentPicker:
                    actionsSubject.send(.presentMediaUploadPicker(mode: .init(source: .documents(), selectionType: .multipleItems),
                                                                  caption: composerViewModel.context.plainComposerText))
                case .displayMediaPreview(let mediaPreviewViewModel):
                    roomViewModel.displayMediaPreview(mediaPreviewViewModel)
                case .displayLocationPicker:
                    actionsSubject.send(.presentLocationPicker)
                case .displayNewPollForm:
                    actionsSubject.send(.presentPollForm(mode: .new(topic: composerViewModel.context.plainComposerText.string)))
                case .displayEditPollForm(let eventID, let poll):
                    actionsSubject.send(.presentPollForm(mode: .edit(eventID: eventID, poll: poll)))
                case .displayMediaUploadPreviewScreen(let mediaURLs):
                    actionsSubject.send(.presentMediaUploadPreviewScreen(mediaURLs: mediaURLs,
                                                                         caption: composerViewModel.context.plainComposerText))
                case .displaySenderDetails(userID: let userID):
                    actionsSubject.send(.presentRoomMemberDetails(userID: userID))
                case .displayMessageForwarding(let forwardingPayload):
                    actionsSubject.send(.presentMessageForwarding(forwardingPayload: forwardingPayload))
                case .displayLocation(let location):
                    actionsSubject.send(.presentLocationViewer(location))
                case .displayLiveLocation(let sender, let initialLiveLocationShare):
                    actionsSubject.send(.presentLiveLocationViewer(sender: sender, initialLiveLocationShare: initialLiveLocationShare))
                case .displayResolveSendFailure(let failure, let resolver): // AGENT-PLATFORM: § 5.87
                    actionsSubject.send(.presentResolveSendFailure(failure: failure, resolver: resolver))
                case .displayThread(let itemID):
                    guard let eventID = itemID.eventID else {
                        fatalError("A thread root has always an eventID")
                    }
                    actionsSubject.send(.presentThread(threadRootEventID: eventID, focussedEventID: nil))
                case .composer(let action):
                    composerViewModel.process(timelineAction: action)
                case .hasScrolled(direction: let direction):
                    roomViewModel.timelineHasScrolled(direction: direction)
                case .displayRoom(let roomID, let via):
                    actionsSubject.send(.presentRoom(roomID: roomID, via: via))
                case .presentCallScreen(let isVoiceCall):
                    actionsSubject.send(.presentCallScreen(isVoiceCall: isVoiceCall))
                case .displayAIConsentSettings: // AGENT-PLATFORM (decision 150)
                    actionsSubject.send(.presentAIConsentSettings)
                case .interactivePostPublished:
                    // Published from a draft in this very room; the row's
                    // toast already said so.
                    break
                case .editInteractivePost(let eventID, let post, let title):
                    actionsSubject.send(.presentInteractivePostEditor(eventID: eventID, post: post, title: title))
                case .viewInRoomTimeline, .displayMediaDetails:
                    fatalError("The action: \(action) should not be sent to this coordinator")
                }
            }
            .store(in: &cancellables)
        
        composerViewModel.actions
            .sink { [weak self] action in self?.route(composerAction: action) }
            .store(in: &cancellables)
        
        roomViewModel.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .focusEvent(eventID: let eventID):
                    focusOnEvent(FocusEvent(eventID: eventID, shouldSetPin: false))
                case .displayPinnedEventsTimeline:
                    actionsSubject.send(.presentPinnedEventsTimeline)
                case .displayRoomDetails:
                    actionsSubject.send(.presentRoomDetails)
                case .displayAgentTools:
                    actionsSubject.send(.presentAgentTools)
                case .displayCall(let isVoiceCall):
                    actionsSubject.send(.presentCallScreen(isVoiceCall: isVoiceCall))
                case .removeComposerFocus:
                    composerViewModel.process(timelineAction: .removeFocus)
                case .displayKnockRequests:
                    actionsSubject.send(.presentKnockRequestsList)
                case .displayRoom(let roomID, let via):
                    actionsSubject.send(.presentRoom(roomID: roomID, via: via))
                case .displayMessageForwarding(let forwardingPayload):
                    actionsSubject.send(.presentMessageForwarding(forwardingPayload: forwardingPayload))
                case .displayThread(let threadRootEventID, let focussedEventID):
                    actionsSubject.send(.presentThread(threadRootEventID: threadRootEventID, focussedEventID: focussedEventID))
                case .stopLiveLocationSharing:
                    Task { [weak self] in await self?.timelineViewModel.stopLiveLocationSharing() }
                case .displayLiveLocation:
                    actionsSubject.send(.presentLiveLocationViewer(sender: nil, initialLiveLocationShare: nil))
                }
            }
            .store(in: &cancellables)
        
        // Loading the draft requires the subscriptions to be set up first otherwise
        // the room won't be be able to propagate the information to the composer.
        composerViewModel.start()
    }
    
    func focusOnEvent(_ focussedEvent: FocusEvent) {
        let eventID = focussedEvent.eventID
        if focussedEvent.shouldSetPin {
            roomViewModel.setSelectedPinnedEventID(eventID)
        }
        Task { await timelineViewModel.focusOnEvent(eventID: eventID) }
    }
    
    /// Sets the banner to selection to a specific event ID, even if not visible in the main timeline (like a threaded event).
    func setSelectedPin(eventID: String) {
        roomViewModel.setSelectedPinnedEventID(eventID)
    }

    // AGENT-PLATFORM: re-pull the active-tools banner after an agent-tools
    // sheet change (Brief 0036 F2).
    func refreshAgentToolsBanner() {
        roomViewModel.refreshAgentToolsBanner()
    }

    // AGENT-PLATFORM (Brief 0066, § 5.80): the room's Interactive Posts stop
    // while one of our sheets covers the room.
    func setInteractivePostsCovered(_ covered: Bool) {
        timelineViewModel.context.viewState.spiralAppHosts?.setCovered(covered)
    }

    // AGENT-PLATFORM (Brief 0066, § 5.84): a post published into this room
    // from one of our sheets lands at the bottom, as a sent message does —
    // the same scroll the composer's send takes.
    func scrollToBottom() {
        timelineViewModel.context.send(viewAction: .scrollToBottom)
    }
    
    func shareText(_ string: String) {
        composerViewModel.process(timelineAction: .setMode(mode: .default)) // Make sure we're not e.g. replying.
        composerViewModel.process(timelineAction: .setText(plainText: string, htmlText: nil))
        composerViewModel.process(timelineAction: .setFocus)
    }
    
    func clearMessageSelection() {
        timelineViewModel.clearMessageSelection()
    }
    
    func stop() {
        composerViewModel.stop()
        roomViewModel.stop()
        timelineViewModel.stop() // AGENT-PLATFORM (Brief 0083, questions 363 and 364)
    }
    
    // AGENT-PLATFORM: the "Agent" and "Interactive post" compose-menu items
    // are not timeline concerns — they go straight to the flow.
    private func route(composerAction action: ComposerToolbarViewModelAction) {
        switch action {
        case .presentAgentTools:
            actionsSubject.send(.presentAgentTools)
        case .presentInteractivePostAgentPicker:
            actionsSubject.send(.presentInteractivePostAgentPicker)
        default:
            timelineViewModel.process(composerAction: action)
        }
    }

    func toPresentable() -> AnyView {
        let composerToolbar = ComposerToolbar(context: composerViewModel.context)
        
        return AnyView(RoomScreen(context: roomViewModel.context,
                                  timelineContext: timelineViewModel.context,
                                  composerToolbar: composerToolbar))
    }
}

enum ComposerConstant {
    static let minHeight: CGFloat = 22
    static let maxHeight: CGFloat = 250
    static let allowedHeightRange = minHeight...maxHeight
    static let translationThreshold: CGFloat = 60
}
