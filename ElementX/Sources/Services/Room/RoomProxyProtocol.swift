//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Algorithms
import Combine
import Foundation
import MatrixRustSDK

enum RoomProxyError: Error {
    case sdkError(Error)
    
    case invalidURL
    case invalidMedia
    case eventNotFound
    case failedCreatingPinnedTimeline
    case timelineError(TimelineProxyError)
    case liveLocationSessionIsNotActive
    /// AGENT-PLATFORM (Brief 0066 § 5.87): a raw send that encryption refused
    /// because a verified user has unsigned devices or a changed identity —
    /// resolvable as a wedged send-queue item is.
    case verifiedUser(TimelineItemSendFailure.VerifiedUser)
}

/// An enum that describes the relationship between the current user and the room, and contains a reference to the specific implementation of the `RoomProxy`.
enum RoomProxyType {
    case joined(JoinedRoomProxyProtocol)
    case invited(InvitedRoomProxyProtocol)
    case knocked(KnockedRoomProxyProtocol)
    case banned(BannedRoomProxyProtocol)
    case left
}

// sourcery: AutoMockable
protocol RoomProxyProtocol: Sendable {
    var id: String { get }
    var ownUserID: String { get }
}

// sourcery: AutoMockable
protocol InvitedRoomProxyProtocol: RoomProxyProtocol {
    var info: BaseRoomInfoProxyProtocol { get }
    var inviter: RoomMemberProxyProtocol? { get }
    func rejectInvitation() async -> Result<Void, RoomProxyError>
}

// sourcery: AutoMockable
protocol KnockedRoomProxyProtocol: RoomProxyProtocol {
    var info: BaseRoomInfoProxyProtocol { get }
    func cancelKnock() async -> Result<Void, RoomProxyError>
}

// sourcery: AutoMockable
protocol BannedRoomProxyProtocol: RoomProxyProtocol {
    var info: BaseRoomInfoProxyProtocol { get }
    func forgetRoom() async -> Result<Void, RoomProxyError>
}

enum KnockRequestsState {
    case loading
    case loaded([KnockRequestProxyProtocol])
}

// sourcery: AutoMockable
protocol JoinedRoomProxyProtocol: RoomProxyProtocol {
    var infoPublisher: CurrentValuePublisher<RoomInfoProxyProtocol, Never> { get }
    
    var membersPublisher: CurrentValuePublisher<[RoomMemberProxyProtocol], Never> { get }
    
    var typingMembersPublisher: CurrentValuePublisher<[String], Never> { get }
    
    var identityStatusChangesPublisher: CurrentValuePublisher<[IdentityStatusChange], Never> { get }
    
    var knockRequestsStatePublisher: CurrentValuePublisher<KnockRequestsState, Never> { get }
    
    var timeline: TimelineProxyProtocol { get }
    
    var predecessorRoom: PredecessorRoom? { get }
    
    func subscribeForUpdates() async
    
    func subscribeToRoomInfoUpdates()
    
    func timelineFocusedOnEvent(eventID: String, numberOfEvents: UInt16) async -> Result<TimelineProxyProtocol, RoomProxyError>
    
    func threadTimeline(eventID: String) async -> Result<TimelineProxyProtocol, RoomProxyError>
    
    func threadListService() -> RoomThreadListServiceProxyProtocol
    
    func loadOrFetchEventDetails(for eventID: String) async -> Result<TimelineEvent, RoomProxyError>
    
    // MARK: - AGENT-PLATFORM (Brief 0066, ADR-0007): Interactive Posts
    
    /// Every `m.reference` child of `eventID`, as raw decrypted event JSON.
    ///
    /// The authoritative read for a post's state. May return a PARTIAL set
    /// without saying so — see `DESIGNS/spiral-app-runtime.md` §3.15 — so the
    /// caller checks completeness rather than trusting the result.
    func loadSpiralAppRelations(for eventID: String) async -> Result<[String], RoomProxyError>
    
    /// Observe events of `types` as they reach this room, below the timeline's
    /// filter and above decryption.
    ///
    /// The caller MUST retain the returned handle: dropping it unsubscribes.
    /// Retaining it also pins this room's events in memory, so subscribe when
    /// a room opens and release on close.
    ///
    /// Takes the listener rather than a closure because that is what survives
    /// mock generation — `subscribeToCallDeclineEvents` is the same shape.
    /// Build one with `SDKListener.onMainActor { … }`.
    func subscribeToSpiralEvents(types: [String],
                                 listener: SpiralEventListener) async -> Result<TaskHandle, RoomProxyError>
    
    /// Send an event of a custom type, bypassing the timeline's send path.
    ///
    /// Interactive Post actions go out this way because routing them through
    /// the timeline would create a local echo for an event the timeline is
    /// deliberately not allowed to show.
    func sendSpiralRawEvent(type: String, content: String) async -> Result<Void, RoomProxyError>
    /// `sendSpiralRawEvent`, returning the event id — for a caller that
    /// starts a thread on what it sent.
    ///
    /// Both fail with `.verifiedUser` when encryption refused a verified
    /// user's devices or identity (§ 5.87); see `RawSendResolution`.
    func sendSpiralRawEventReturningEventID(type: String, content: String) async -> Result<String, RoomProxyError>
    /// AGENT-PLATFORM (§ 5.87): the answers to a refused raw send: share with these unsigned devices
    /// after all, or stop holding these users to their old identity. The
    /// queue's `…AndResend` without the resend.
    func ignoreDeviceTrust(devices: [String: [String]]) async -> Result<Void, RoomProxyError>
    func withdrawVerification(userIDs: [String]) async -> Result<Void, RoomProxyError>
    
    func messageFilteredTimeline(focus: TimelineFocus,
                                 allowedMessageTypes: [TimelineAllowedMessageType],
                                 presentation: TimelineKind.MediaPresentation) async -> Result<TimelineProxyProtocol, RoomProxyError>
    
    func pinnedEventsTimeline() async -> Result<TimelineProxyProtocol, RoomProxyError>
    
    func enableEncryption() async -> Result<Void, RoomProxyError>
    
    func reportContent(_ eventID: String, reason: String?) async -> Result<Void, RoomProxyError>
    
    func reportRoom(reason: String) async -> Result<Void, RoomProxyError>
    
    func leaveRoom() async -> Result<Void, RoomProxyError>
    
    func updateMembers() async
    
    func getMember(userID: String) async -> Result<RoomMemberProxyProtocol, RoomProxyError>
    
    func invite(userID: String) async -> Result<Void, RoomProxyError>
    
    func setName(_ name: String) async -> Result<Void, RoomProxyError>
    
    func setTopic(_ topic: String) async -> Result<Void, RoomProxyError>
    
    func removeAvatar() async -> Result<Void, RoomProxyError>
    
    func uploadAvatar(media: MediaInfo) async -> Result<Void, RoomProxyError>
    
    func markAsRead(receiptType: ReceiptType) async -> Result<Void, RoomProxyError>
    
    /// https://spec.matrix.org/v1.9/client-server-api/#typing-notifications
    @discardableResult func sendTypingNotification(isTyping: Bool) async -> Result<Void, RoomProxyError>
    
    func ignoreDeviceTrustAndResend(devices: [String: [String]], sendHandle: SendHandleProxy) async -> Result<Void, RoomProxyError>
    
    func withdrawVerificationAndResend(userIDs: [String], sendHandle: SendHandleProxy) async -> Result<Void, RoomProxyError>
    
    // MARK: - Privacy settings
    
    func updateJoinRule(_ rule: JoinRule) async -> Result<Void, RoomProxyError>
    func updateHistoryVisibility(_ visibility: RoomHistoryVisibility) async -> Result<Void, RoomProxyError>
    
    func isVisibleInRoomDirectory() async -> Result<Bool, RoomProxyError>
    func updateRoomDirectoryVisibility(_ visibility: RoomVisibility) async -> Result<Void, RoomProxyError>
    
    // MARK: - Canonical Alias
    
    func updateCanonicalAlias(_ alias: String?, altAliases: [String]) async -> Result<Void, RoomProxyError>
    
    func publishRoomAliasInRoomDirectory(_ alias: String) async -> Result<Bool, RoomProxyError>
    func removeRoomAliasFromRoomDirectory(_ alias: String) async -> Result<Bool, RoomProxyError>
    
    // MARK: - Room Flags
    
    func flagAsUnread(_ isUnread: Bool) async -> Result<Void, RoomProxyError>
    
    func flagAsFavourite(_ isFavourite: Bool) async -> Result<Void, RoomProxyError>
    
    // MARK: - Power Levels
    
    func applyPowerLevelChanges(_ changes: RoomPowerLevelChanges) async -> Result<Void, RoomProxyError>
    func resetPowerLevels() async -> Result<Void, RoomProxyError>
    func updatePowerLevelsForUsers(_ updates: [(userID: String, powerLevel: Int64)]) async -> Result<Void, RoomProxyError>
    
    // MARK: - Moderation
    
    func kickUser(_ userID: String, reason: String?) async -> Result<Void, RoomProxyError>
    /// AGENT-PLATFORM (bug S2): `userID`'s room membership as the local store has it now, the member list fetched
    /// first if it never was; nil when it could not be read or the room has no member event for them.
    func membership(of userID: String) async -> MembershipState?
    func banUser(_ userID: String, reason: String?) async -> Result<Void, RoomProxyError>
    func unbanUser(_ userID: String) async -> Result<Void, RoomProxyError>
    
    // MARK: - Calls
    
    // AGENT-PLATFORM (Brief 0063/0067): the native MatrixRTC session is the
    // only call surface; the Element Call widget driver is gone (ADR-0079).
    func matrixRTCSession() -> Result<MatrixRTCSessionProtocol, RoomProxyError>
    func declineCall(notificationID: String) async -> Result<Void, RoomProxyError>
    func subscribeToCallDeclineEvents(rtcNotificationEventID: String, listener: CallDeclineListener) -> Result<TaskHandle, RoomProxyError>
    
    // MARK: - Permalinks
    
    func matrixToPermalink() async -> Result<URL, RoomProxyError>
    func matrixToEventPermalink(_ eventID: String) async -> Result<URL, RoomProxyError>
    
    // MARK: - Drafts
    
    func saveDraft(_ draft: ComposerDraft, threadRootEventID: String?) async -> Result<Void, RoomProxyError>
    func loadDraft(threadRootEventID: String?) async -> Result<ComposerDraft?, RoomProxyError>
    func clearDraft(threadRootEventID: String?) async -> Result<Void, RoomProxyError>
    
    // MARK: - Live Location
    
    func makeLiveLocationService() async -> RoomLiveLocationServiceProtocol
    
    func startLiveLocationShare(duration: Duration) async -> Result<String, RoomProxyError>
    func sendLiveLocation(geoURI: GeoURI) async -> Result<Void, RoomProxyError>
    func stopLiveLocationShare() async -> Result<Void, RoomProxyError>
}

extension JoinedRoomProxyProtocol {
    var details: RoomDetails {
        let historySharingState: RoomHistorySharingState? = if infoPublisher.value.isEncrypted {
            infoPublisher.value.historySharingState
        } else {
            nil
        }
        
        return RoomDetails(id: id,
                           name: infoPublisher.value.displayName,
                           avatar: infoPublisher.value.avatar,
                           canonicalAlias: infoPublisher.value.canonicalAlias,
                           isEncrypted: infoPublisher.value.isEncrypted,
                           isPublic: !(infoPublisher.value.isPrivate ?? false),
                           isDirect: infoPublisher.value.isDirect,
                           historySharingState: historySharingState)
    }
    
    func members() async -> [RoomMemberProxyProtocol]? {
        await updateMembers()
        return membersPublisher.value
    }
    
    /// AGENT-PLATFORM (bug S2): removes `userID` from the room. One already out of it, by an earlier removal or
    /// someone else's, counts as removed: the server refuses to kick a user who is not in the room.
    func removeFromRoom(_ userID: String) async -> Result<Void, RoomProxyError> {
        let result = await kickUser(userID, reason: nil)
        guard case .failure = result, let membership = await membership(of: userID) else { return result }
        switch membership {
        case .join, .invite, .knock:
            return result
        default:
            MXLog.info("\(userID) is already out of \(id); the removal stands")
            return .success(())
        }
    }
    
    /// This is a horrible workaround for not having any server names available when using tombstone links with v12 room IDs.
    func knownServerNames(maxCount: Int) -> any Sequence<String> {
        membersPublisher.value
            .prefix(1000) // No need to go crazy here…
            .compactMap { try? serverNameFromUserId(userId: $0.userID) }
            .uniqued()
            .prefix(maxCount)
    }
}
