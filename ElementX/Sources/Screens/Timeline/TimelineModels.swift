//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import MatrixRustSDK
import OrderedCollections
import SwiftUI

enum TimelineViewModelAction {
    case displayEmojiPicker(selectedEmojis: Set<String>, continuation: EmojiPickerScreenContinuation)
    case displayReportContent(itemID: TimelineItemIdentifier, senderID: String)
    case displayCameraPicker
    case displayMediaPicker
    case displayDocumentPicker
    case displayLocationPicker
    case displayNewPollForm
    case displayEditPollForm(eventID: String, poll: Poll)
    case displayMediaUploadPreviewScreen(mediaURLs: [URL])
    case displaySenderDetails(userID: String)
    case displayMessageForwarding(forwardingPayload: MessageForwardingPayload)
    case displayMediaPreview(TimelineMediaPreviewViewModel)
    case displayLocation(StaticLocationData)
    case displayLiveLocation(sender: TimelineItemSender, initialLiveLocationShare: LiveLocationShare)
    case displayResolveSendFailure(failure: TimelineItemSendFailure.VerifiedUser, resolver: VerifiedUserSendFailureResolver) // AGENT-PLATFORM: § 5.87, was `sendHandle`
    case displayThread(itemID: TimelineItemIdentifier)
    case composer(action: TimelineComposerAction)
    case hasScrolled(direction: ScrollDirection)
    case viewInRoomTimeline(eventID: String, threadRootEventID: String?)
    case displayRoom(roomID: String, via: [String])
    case displayMediaDetails(item: EventBasedMessageTimelineItemProtocol)
    case presentCallScreen(isVoiceCall: Bool)
    // AGENT-PLATFORM (Brief 0066 step 6): a draft was published into
    // `roomID` — the generation sheet closes on it.
    case interactivePostPublished(roomID: String)
    // AGENT-PLATFORM (decision 150): the AI consent notice's button. An action,
    // not a URL: no link in a message can produce it.
    case displayAIConsentSettings
    // AGENT-PLATFORM (§ 5.55): change a published post from its thread.
    case editInteractivePost(eventID: String, post: SpiralAppPost, title: String)
}

enum TimelineViewPollAction {
    case sendResponse(pollStartID: String, answerIDs: [String])
    case end(pollStartID: String)
    case edit(pollStartID: String, poll: Poll)
}

enum TimelineAudioPlayerAction {
    case playPause(itemID: TimelineItemIdentifier)
    case seek(itemID: TimelineItemIdentifier, progress: Double)
    case changePlaybackSpeed(itemID: TimelineItemIdentifier)
}

enum TimelineViewAction {
    case itemAppeared(itemID: TimelineItemIdentifier)
    case itemDisappeared(itemID: TimelineItemIdentifier)
    
    case mediaTapped(itemID: TimelineItemIdentifier)
    case galleryItemTapped(GalleryItemID)
    case itemSendInfoTapped(itemID: TimelineItemIdentifier)
    // AGENT-PLATFORM (Brief 0066 step 6): the owner publishes a generated
    // draft — pack, hash, encrypt, upload, send `com.spiral.app` — here,
    // in this room, as themselves. Forwarding takes it anywhere else.
    case publishInteractiveDraft(itemID: TimelineItemIdentifier)
    /// A live post's thread, choosing a new post over updating it.
    case publishInteractiveDraftAsNew(itemID: TimelineItemIdentifier)
    case toggleReaction(key: String, itemID: TimelineItemIdentifier)
    case sendReadReceiptIfNeeded(TimelineItemIdentifier)
    case paginateBackwards
    case paginateForwards
    case scrollToBottom
    case scrollToFirstItemForCurrentDate
    case scrollToReadMarker
    case markAllAsRead
    
    case displayTimelineItemMenu(itemID: TimelineItemIdentifier)
    case handleTimelineItemMenuAction(itemID: TimelineItemIdentifier, action: TimelineItemMenuAction)
    /// The user has confirmed the removal of an item, optionally giving a reason.
    case redactConfirmed(itemID: TimelineItemIdentifier, reason: String?)
    
    /// Add or remove an item from the active multi-selection.
    case toggleMessageSelection(itemID: TimelineItemIdentifier)
    case clearMessageSelection
    /// Forward the selected messages, in timeline order.
    case forwardMessageSelection
    
    case tappedOnSenderDetails(sender: TimelineItemSender)
    case displayReactionSummary(itemID: TimelineItemIdentifier, key: String)
    case displayEmojiPicker(itemID: TimelineItemIdentifier)
    case displayThread(itemID: TimelineItemIdentifier)
    
    case handlePasteOrDrop(providers: [NSItemProvider])
    case handlePollAction(TimelineViewPollAction)
    case handleAudioPlayerAction(TimelineAudioPlayerAction)
    
    case stopLiveLocationSharing(TimelineItemIdentifier)
    
    /// Focus the timeline onto the specified event ID (switching to a detached timeline if needed).
    case focusOnEventID(String)
    /// Switch back to a live timeline (from a detached one).
    case focusLive
    /// The timeline scrolled to reveal the focussed item.
    case scrolledToFocussedItem
    /// A person scrolled the focussed item off screen.
    case scrolledAwayFromFocussedItem
    /// The table view has loaded the first items for a new timeline.
    case hasSwitchedTimeline
    /// AGENT-PLATFORM (Brief 0083, question 363): the table has settled where the chat opens.
    case hasSettledOpening(isAwayFromEnd: Bool)
    
    case hasScrolled(direction: ScrollDirection)
    
    case displayPredecessorRoom
    case joinActiveCall(isVoiceCall: Bool)
    case openAIConsentSettings // AGENT-PLATFORM (decision 150)
    /// AGENT-PLATFORM (1.0.3 A3): a starter under the assistant's welcome, sent as the person's own message.
    case sendWelcomeStarter(SpiralWelcomeStarter)
}

enum TimelineComposerAction {
    case setMode(mode: ComposerMode)
    case setText(plainText: String, htmlText: String?)
    case setFocus
    case removeFocus
    case clear
}

struct TimelineViewState: BindableState {
    let timelineKind: TimelineKind
    /// The gallery attachments the timeline includes, or `nil` when it isn't filtered.
    let allowedGalleryItemTypes: [TimelineAllowedGalleryItemType]?
    var roomID: String
    var members: [String: RoomMemberState] = [:] {
        didSet { membersRevision.value += 1 } // AGENT-PLATFORM (Brief 0083, question 359)
    }
    let membersRevision = TimelineMembersRevision()
    let rowMotion = TimelineRowMotion() // AGENT-PLATFORM (Brief 0083, question 359)
    var typingMembers: [String] = []
    var headerTyping: RoomHeaderView.Typing { // AGENT-PLATFORM (Brief 0083, question 359)
        .init(members: typingMembers, isDM: isDM)
    }
    
    var showLoading = false
    var showReadReceipts = false
    var isDM = false
    var timelineState: TimelineState // check the doc before changing this
    
    var ownUserID: String
    var canCurrentUserSendMessage = false
    var canCurrentUserRedactOthers = false
    var canCurrentUserRedactSelf = false
    var canCurrentUserPin = false
    var canCurrentUserKick = false
    var canCurrentUserBan = false
    
    var hideTimelineMedia: Bool
    
    var isViewSourceEnabled: Bool
    var areThreadsEnabled: Bool
    var linkPreviewsEnabled: Bool
    var jumpToReadMarkerEnabled: Bool
    
    var messageSelection = TimelineMessageSelectionState()
    
    let hasPredecessor: Bool
    
    /// The `pinnedEventIDs` are used only to determine if an item is already pinned or not.
    /// It's updated from the room info, so it's faster than using the timeline
    var pinnedEventIDs: Set<String> = []
    
    /// AGENT-PLATFORM (Brief 0066): who owns the Interactive Posts' web views.
    ///
    /// Held here rather than by the rows because rows are recycled table cells
    /// — see `SpiralAppHostRegistry`. Optional so previews and mocks, which
    /// have no session to run an app against, simply draw the quiet card.
    var spiralAppHosts: SpiralAppHostRegistry?

    /// A closure providing the associated audio player state for an item in the timeline.
    var audioPlayerStateProvider: (@MainActor (_ itemId: TimelineItemIdentifier) -> AudioPlayerState?)?
    
    /// A closure that updates the associated pill context
    var pillContextUpdater: (@MainActor (PillContext) -> Void)?
    
    /// A closure that returns the associated room name give its id
    var roomNameForIDResolver: (@MainActor (String) -> String?)?
    
    /// The people of a room, as `members.basic.read` answers them — nil
    /// for this timeline's room. A draft previews with the people of the
    /// room it is FOR, not the thread's.
    var spiralMembersResolver: (@MainActor (String?) async -> [String: Any])?
    
    /// AGENT-PLATFORM (decision 38): a person's name from their profile, for a
    /// notice naming someone who is not in this room. Nil in previews and mocks.
    var spiralDisplayNameResolver: (@MainActor (String) async -> String?)?

    /// AGENT-PLATFORM (decision 150): whether the reader allowed third-party
    /// AI — nil when unknown (no platform, a failed read). Nil in previews.
    var spiralAIConsentResolver: (@MainActor () async -> Bool?)?
    
    /// AGENT-PLATFORM (1.0.3 A3): what the assistant's welcome offers under its hello.
    var spiralWelcomeExtras = SpiralWelcomeExtras.none
    
    /// The published post this thread's drafts update, read off the newest
    /// `com.spiral.live_post` marker in it (§ 5.55). Nil anywhere else.
    var spiralLivePost: SpiralLivePost?
    
    /// Set when the thread was opened from the catalogue in another room:
    /// its drafts publish THERE (§ 5.56).
    var spiralPublishRoom: SpiralPublishRoom?
    
    /// The live post a draft here updates — none when the thread was opened
    /// to publish into a room other than the live post's.
    var spiralUpdatableLivePost: SpiralLivePost? {
        guard let live = spiralLivePost else { return nil }
        if let room = spiralPublishRoom, room.id != live.roomID { return nil }
        return live
    }
    
    /// A closure that returns the associated room name give its alias
    var roomNameForAliasResolver: (@MainActor (String) -> String?)?
    
    var emojiProvider: EmojiProviderProtocol
    
    var linkMetadataProvider: LinkMetadataProviderProtocol?
    
    var mapTilerConfiguration: MapTilerConfiguration
    
    var stoppedLiveLocationIDs: Set<TimelineItemIdentifier> = []
    
    var bindings: TimelineViewStateBindings
}

struct TimelineViewStateBindings {
    var isScrolledToBottom = true
    
    /// Whether the read marker (NEW banner) is currently visible in the timeline viewport.
    /// Used to hide the jump-to-unread button once the user has scrolled to the read marker.
    var isReadMarkerVisible = false
    
    /// Whether a new row from someone else has arrived while the user is scrolled away from the
    /// bottom of a live timeline. Drives the presence dot on the scroll-to-bottom button and resets
    /// when the user returns to the bottom.
    var hasNewMessagesAtBottom = false
    
    /// The timestamp of the topmost visible item, used to drive the floating date badge while scrolling.
    var floatingDate: Date?
    
    /// The state of wether reactions listed on the timeline are expanded/collapsed.
    /// Key is itemID, value is the collapsed state.
    var reactionsCollapsed: [TimelineItemIdentifier: Bool]
    
    /// AGENT-PLATFORM (decision 371): the long call summaries the reader has opened.
    var expandedCallSummaries = Set<TimelineItemIdentifier>()
    
    var alertInfo: AlertInfo<TimelineAlertInfoType>?
    
    var debugInfo: TimelineItemDebugInfo?
    /// AGENT-PLATFORM (Brief 0066 step 6): a draft's module, shown from the menu.
    var draftCode: InteractiveDraftCode?
    
    var actionMenuInfo: TimelineItemActionMenuInfo?
    
    var reactionSummaryInfo: ReactionSummaryInfo?
    
    var readReceiptsSummaryInfo: ReadReceiptSummaryInfo?
    
    var manageMemberViewModel: ManageRoomMemberSheetViewModel?
    
    var redactConfirmationInfo: TimelineRedactConfirmationInfo?
    
    var showTranslation = false
    var textToBeTranslated: String?
}

/// The state of the multi-selection of messages.
struct TimelineMessageSelectionState: Equatable {
    static let limit = 10
    
    /// Stays on when every message is unselected, it only ends when closed or once the messages are forwarded.
    var isActive = false
    var selectedEventIDs: Set<String> = []
    
    var count: Int {
        selectedEventIDs.count
    }
    
    var isAtLimit: Bool {
        count >= Self.limit
    }
    
    func contains(_ eventID: String?) -> Bool {
        guard let eventID else { return false }
        return selectedEventIDs.contains(eventID)
    }
    
    mutating func end() {
        isActive = false
        selectedEventIDs.removeAll()
    }
}

struct TimelineItemActionMenuInfo: Equatable, Identifiable {
    static func == (lhs: TimelineItemActionMenuInfo, rhs: TimelineItemActionMenuInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    let item: EventBasedTimelineItemProtocol
    
    var id: TimelineItemIdentifier {
        item.id
    }
}

struct ReactionSummaryInfo: Identifiable {
    let reactions: [AggregatedReaction]
    let selectedKey: String
    
    var id: String {
        selectedKey
    }
}

extension TimelineViewState {
    /// Whether the message's menu offers "Seen by".
    func hasReaders(_ timelineItem: RoomTimelineItemProtocol) -> Bool {
        showReadReceipts && !timelineState.readProgress.readers(of: timelineItem.id.uniqueID).isEmpty
    }
}

struct ReadReceiptSummaryInfo: Identifiable {
    let orderedReceipts: [ReadReceipt]
    let id: TimelineItemIdentifier
}

/// The item that the user has asked to remove and must confirm, optionally giving a reason.
struct TimelineRedactConfirmationInfo: Identifiable {
    let id: TimelineItemIdentifier
}

enum TimelineAlertInfoType: Hashable {
    case audioRecodingPermissionError
    case pollEndConfirmation(String)
    case sendingFailed(reason: String?, itemID: TimelineItemIdentifier, target: SendTarget?)
    case encryptionAuthenticity(String)
    case encryptionForwarder(String)
    case inviteAgain
    case unableToInvite
    case unknown
}

struct RoomMemberState: Equatable {
    let displayName: String?
    let avatarURL: URL?
    let status: UserStatus
}

/// Used as the state for the TimelineView, to avoid having the context continuously refresh the list of items on each small change.
/// Is also nice to have this as a wrapper for any state that is directly connected to the timeline.
struct TimelineState {
    var isLive = true
    var paginationState = TimelinePaginationState.initial
    /// AGENT-PLATFORM (1.0.3 B14): the last back pagination failed. The SDK's state goes back to idle, so this is how a
    /// screen tells a failure from a page still to load.
    var hasBackPaginationFailed = false
    
    /// The room is in the process of loading items from a new timeline (switching to/from a detached timeline).
    var isSwitchingTimelines = false
    
    /// AGENT-PLATFORM (Brief 0083, question 363): where the room's live timeline opens. Nothing counts as read until it's settled.
    enum Opening: Equatable {
        /// No rows yet.
        case undecided
        /// The unread starts above the loaded rows. The table shows nothing until they're in, so the end never flashes by.
        case loadingRows
        /// At this row, unless it's on screen from the end.
        case atRow(TimelineItemIdentifier.UniqueID)
        /// Left to the person.
        case settled
        /// You left before it settled. Nothing more loads, and nothing counts as read.
        case abandoned
    }
    
    var opening = Opening.settled
    
    struct FocussedEvent: Equatable {
        enum Appearance {
            /// The event should be shown using an animated scroll.
            case animated
            /// The event should be shown immediately, without any animation.
            case immediate
            /// The event has already been shown.
            case hasAppeared
        }
        
        /// The ID of the event.
        let eventID: String
        /// How the event should be shown, or whether it has already appeared.
        var appearance: Appearance
    }
    
    /// A focussed event that was navigated to via a permalink.
    var focussedEvent: FocussedEvent?
    
    /// These can be removed when we have full swiftUI and moved as @State values in the view
    var scrollToBottomPublisher = PassthroughSubject<Void, Never>()
    var scrollToFirstItemForDatePublisher = PassthroughSubject<Void, Never>()
    var scrollToReadMarkerPublisher = PassthroughSubject<TimelineItemIdentifier.UniqueID, Never>()
    
    var itemsDictionary = OrderedDictionary<TimelineItemIdentifier.UniqueID, RoomTimelineItemViewState>() {
        didSet { buildID += 1 } // AGENT-PLATFORM (Brief 0083, question 359)
    }
    
    /// Which build of ``itemsDictionary`` this is, so the table can tell without comparing the rows on every update of the state.
    private(set) var buildID = 0
    
    var uniqueIDs: [TimelineItemIdentifier.UniqueID] {
        itemsDictionary.keys.elements
    }
    
    var itemViewStates: [RoomTimelineItemViewState] {
        itemsDictionary.values.elements
    }
    
    /// The unique ID of the read marker (NEW banner) in the timeline, if present.
    /// Recomputed by ``recomputeReadMarkerUniqueID()`` whenever ``itemsDictionary`` changes.
    private(set) var readMarkerUniqueID: TimelineItemIdentifier.UniqueID?
    
    /// The user's `m.fully_read` event ID, pushed from `RoomInfo`. Used as a fallback
    /// signal when ``readMarkerUniqueID`` is nil because the marker event isn't paginated
    /// into the loaded timeline window.
    var fullyReadEventID: String?
    /// AGENT-PLATFORM (Brief 0083, question 364): `m.fully_read` is on an event that's among the rows but isn't one, such as a
    /// reaction. It's not above them, so nothing need wait for a back-pagination to bring it in.
    var isFullyReadWithoutRow = false
    
    /// AGENT-PLATFORM (Brief 0083, question 357): how far the room has read.
    var readProgress = TimelineReadProgress()
    /// The own messages that show two ticks, worked out once per update and not per row.
    var readOwnItemIDs = Set<TimelineItemIdentifier.UniqueID>()
    
    /// Recomputes ``readMarkerUniqueID`` from ``itemsDictionary``. Call after assigning a new
    /// value to ``itemsDictionary``.
    mutating func recomputeReadMarkerUniqueID() {
        readMarkerUniqueID = itemsDictionary.first { _, viewState in
            if case .readMarker = viewState.type {
                return true
            }
            return false
        }?.key
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): whether the read marker lies above the loaded rows, so it's for a back-pagination
    /// to bring it in. If the event is loaded and no virtual item was inserted, the user is caught up: there's no marker to find.
    var isReadMarkerAboveLoadedRows: Bool {
        guard let fullyReadEventID, !isFullyReadWithoutRow else { return false }
        return !itemsDictionary.isEmpty && !hasLoadedItem(with: fullyReadEventID)
    }
    
    func hasLoadedItem(with eventID: String) -> Bool {
        itemViewStates.contains { viewState in
            // AGENT-PLATFORM (Brief 0083, question 359): a folded row is loaded too.
            if case .group(let group) = viewState.type {
                return group.itemIDs.contains { $0.eventID == eventID }
            }
            return viewState.identifier.eventID == eventID
        }
    }
}

enum ScrollDirection: Equatable {
    case top
    case bottom
}

extension TimelineViewState {
    /// Multi-selection is offered everywhere but the media timelines.
    var canSelectMessages: Bool {
        switch timelineKind {
        case .live, .detached, .thread, .pinned: true
        case .media: false
        }
    }
    
    /// The user is at the bottom of a live timeline (no jump-to-bottom button needed).
    var isAtBottomAndLive: Bool {
        bindings.isScrolledToBottom && timelineState.isLive
    }
    
    /// Whether the scroll-to-bottom button should be shown: the user is scrolled away from the
    /// bottom of a live timeline.
    var shouldShowScrollToBottomButton: Bool {
        !isAtBottomAndLive
    }
    
    /// Whether the jump-to-read-marker button should be shown.
    ///
    /// Primary path: the SDK has materialised a virtual `ReadMarker` item in the
    /// loaded timeline window. Show while it isn't visible in the viewport.
    ///
    /// Fallback path: the marker event is older than the loaded window, so no virtual item exists.
    var shouldShowJumpToReadMarker: Bool {
        guard jumpToReadMarkerEnabled else { return false }
        if timelineState.readMarkerUniqueID != nil {
            return !bindings.isReadMarkerVisible
        }
        return timelineState.isReadMarkerAboveLoadedRows
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): whether the scroll-to-bottom button's long press offers "Mark as read". The
    /// dot is for everyone, this isn't.
    var offersMarkAsReadOnScrollToBottom: Bool {
        jumpToReadMarkerEnabled && bindings.hasNewMessagesAtBottom
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): a member for a row to draw. The row isn't observing this state,
    /// so reading `members` directly would keep what it found when it was built; the view asking this redraws when they change.
    func member(_ userID: String) -> RoomMemberState? {
        _ = membersRevision.value
        return members[userID]
    }
    
    /// The string shown as the message preview.
    ///
    /// This converts the formatted body to a plain string to remove formatting
    /// and render with a consistent font size. This conversion is done to avoid
    /// showing markdown characters in the preview for messages with formatting.
    func buildMessagePreview(formattedBody: AttributedString?, plainBody: String) -> String {
        guard let formattedBody,
              let attributedString = try? NSMutableAttributedString(formattedBody, including: \.elementX) else {
            return plainBody
        }
        
        let range = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttributes(in: range) { attributes, range, _ in
            if let userID = attributes[.MatrixUserID] as? String {
                if let displayName = member(userID)?.displayName {
                    attributedString.replaceCharacters(in: range, with: "@\(displayName)")
                } else {
                    attributedString.replaceCharacters(in: range, with: userID)
                }
            }
            
            if attributes[.MatrixAllUsersMention] as? Bool == true {
                attributedString.replaceCharacters(in: range, with: PillUtilities.atRoom)
            }
            
            if let roomAlias = attributes[.MatrixRoomAlias] as? String {
                let roomName = roomNameForAliasResolver?(roomAlias)
                attributedString.replaceCharacters(in: range, with: PillUtilities.roomPillDisplayText(roomName: roomName, rawRoomText: roomAlias))
            }
            
            if let roomID = attributes[.MatrixRoomID] as? String {
                let roomName = roomNameForIDResolver?(roomID)
                attributedString.replaceCharacters(in: range, with: PillUtilities.roomPillDisplayText(roomName: roomName, rawRoomText: roomID))
            }
            
            if let eventOnRoomID = attributes[.MatrixEventOnRoomID] as? EventOnRoomIDAttribute.Value {
                let roomID = eventOnRoomID.roomID
                let roomName = roomNameForIDResolver?(roomID)
                attributedString.replaceCharacters(in: range, with: PillUtilities.eventPillDisplayText(roomName: roomName, rawRoomText: roomID))
            }
            
            if let eventOnRoomAlias = attributes[.MatrixEventOnRoomAlias] as? EventOnRoomAliasAttribute.Value {
                let roomAlias = eventOnRoomAlias.alias
                let roomName = roomNameForAliasResolver?(roomAlias)
                attributedString.replaceCharacters(in: range, with: PillUtilities.eventPillDisplayText(roomName: roomName, rawRoomText: eventOnRoomAlias.alias))
            }
        }
        
        return attributedString.string
    }
}
