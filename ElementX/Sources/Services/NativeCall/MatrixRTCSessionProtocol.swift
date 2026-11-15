//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Foundation

// AGENT-PLATFORM (Brief 0063): app-owned view of the Rust MatrixRTC session.
// Nothing above this layer imports MatrixRustSDK.

enum MatrixRTCSessionError: Error {
    case roomInvalid
    case sdkError(Error)
}

enum NativeCallMedia: Equatable {
    case audio
    case video
}

enum NativeCallScope: Equatable {
    /// A 1:1 with a human.
    case direct
    /// A 1:1 with one's own assistant (operator report 2026-09-11: it rang
    /// until the no-answer timeout although the agent had joined within
    /// seconds). The agent IS the peer here: its presence answers the ring,
    /// its departure ends the call, and it is the stage, not a capsule.
    /// Nothing about the agent's ROLE — translator today, a conversational
    /// assistant later (backend `OwnerAssistant`) — lives in this value;
    /// that is the agent's own state document.
    case assistant
    case group

    /// Direct and assistant calls share the 1:1 shape: one peer, a ring
    /// that a presence answers, a hang-up when that peer goes.
    var isOneToOne: Bool {
        self != .group
    }
}

/// What a freshly started call tells the room (MSC4075).
enum NativeCallNotification: Equatable {
    /// Every member's phone rings.
    case ring
    /// A silent banner; nobody's phone rings.
    case notification
}

struct NativeCallConfiguration: Equatable {
    /// Above this many joined humans a fresh call notifies instead of
    /// ringing (ADR-0079 D3). Formerly the native-eligibility cap; every room
    /// is native now, so this is the only thing the figure still guards.
    static let ringMemberLimit = 8
    
    let media: NativeCallMedia
    let scope: NativeCallScope
    /// What starting a NEW call in this room sends. Joining an ongoing call
    /// sends nothing, whatever this says.
    let freshCallNotification: NativeCallNotification
    
    init(media: NativeCallMedia, scope: NativeCallScope, freshCallNotification: NativeCallNotification = .ring) {
        self.media = media
        self.scope = scope
        self.freshCallNotification = freshCallNotification
    }
    
    /// `members` are the room's loaded members (empty, or partial, while
    /// they load).
    init(media: NativeCallMedia, roomInfo: RoomInfoProxyProtocol, members: [RoomMemberProxyProtocol], ownUserID: String) {
        self.media = media
        scope = Self.scope(isDM: roomInfo.isDM,
                           joinedMembersCount: roomInfo.joinedMembersCount,
                           activeServiceMembersCount: roomInfo.activeServiceMembersCount,
                           otherMemberIDs: Self.otherMemberIDs(members: members,
                                                               ownUserID: ownUserID,
                                                               heroIDs: roomInfo.heroes.map(\.userId),
                                                               joinedMembersCount: roomInfo.joinedMembersCount),
                           ownUserID: ownUserID)
        freshCallNotification = Self.freshCallNotification(isDM: roomInfo.isDM,
                                                           isSpace: roomInfo.isSpace,
                                                           isPrivate: roomInfo.isPrivate,
                                                           joinedMembersCount: roomInfo.joinedMembersCount - roomInfo.activeServiceMembersCount)
    }
    
    /// Who else is in the room, for the scope: the joined members other than
    /// me once the room's members are loaded. The heroes are only the
    /// fallback — a naming hint the server sends while the room has no name
    /// or alias, which the SDK keeps without its service members — so a
    /// renamed DM, or a named one after a fresh login, has none.
    static func otherMemberIDs(members: [RoomMemberProxyProtocol],
                               ownUserID: String,
                               heroIDs: [String],
                               joinedMembersCount: Int) -> [String] {
        guard membersAreLoaded(members, joinedMembersCount: joinedMembersCount) else { return heroIDs }
        return members.filter { $0.membership == .join && $0.userID != ownUserID }.map(\.userID)
    }

    /// Whether `members` are the room's, not a part of them: `updateMembers()`
    /// publishes the store's members first (`membersNoSync`), which under
    /// lazy member loading can be just me, then the full list. Loaded is
    /// as many joined members as the room counts.
    nonisolated static func membersAreLoaded(_ members: [RoomMemberProxyProtocol], joinedMembersCount: Int) -> Bool {
        !members.isEmpty && members.count(where: { $0.membership == .join }) >= joinedMembersCount
    }

    /// A room proxy fresh from `roomForIdentifier` — answering a call,
    /// calling from a profile — loads its members in a task of its own, and
    /// without them a renamed DM's scope falls back to heroes it does not
    /// have. Waits until they are loaded (`membersAreLoaded` — a partial
    /// first list does not end the wait), at most `timeout`, and only for a
    /// DM: a room whose members are loaded, or a group, calls at once.
    static func awaitFirstMembers(of roomProxy: JoinedRoomProxyProtocol,
                                  timeout: DispatchQueue.SchedulerTimeType.Stride = .seconds(1)) async {
        let joinedMembersCount = roomProxy.infoPublisher.value.joinedMembersCount
        guard roomProxy.infoPublisher.value.isDM,
              !membersAreLoaded(roomProxy.membersPublisher.value, joinedMembersCount: joinedMembersCount) else { return }
        var iterator = roomProxy.membersPublisher
            .first { membersAreLoaded($0, joinedMembersCount: joinedMembersCount) }
            .timeout(timeout, scheduler: DispatchQueue.main)
            .values
            .makeAsyncIterator()
        // A cancelled caller ends the wait too; only a real timeout is logged.
        if await iterator.next(isolation: #isolation) == nil, !Task.isCancelled {
            MXLog.info("""
            Calling in \(roomProxy.id) before its members loaded: waited \(Double(timeout.magnitude) / 1_000_000_000) s, \
            members \(roomProxy.membersPublisher.value.count), heroes \(roomProxy.infoPublisher.value.heroes.count)
            """)
        }
    }

    /// Who a call takes for an agent — the one rule the scope and the
    /// in-call derivation share: one of this server's agents
    /// (`SpiralAgentRoomGrants.isLocalAgent`; ADR-0082's application-service
    /// namespaces are exclusive, so an `@assistant-…` of another server is
    /// a person).
    nonisolated static func isAgent(_ userID: String, ownUserID: String) -> Bool {
        SpiralAgentRoomGrants.isLocalAgent(userID, ownUserID: ownUserID)
    }

    /// A DM is a call with its other member. When everyone else who joined
    /// is an agent, the call is with the assistant. A DM with a human whose
    /// agent also sits in the room stays `.direct`: there, the agent only
    /// attaches.
    ///
    /// AGENT-PLATFORM: an agent is known two ways. The member hints say it
    /// (service members, the same joined-minus-service arithmetic the ring
    /// limit uses) — but since backend `02043c5e` (2026-10-08) an agent is a
    /// service member only beside two people, so a DM with one's own
    /// assistant has no hints and is named after the agent rather than
    /// «Empty Room». There the other members say it, by `isAgent`. The
    /// heroes fallback can name someone only invited, so the joined count
    /// still has to fit: an assistant that has not joined yet is nobody to
    /// answer.
    static func scope(isDM: Bool,
                      joinedMembersCount: Int,
                      activeServiceMembersCount: Int,
                      otherMemberIDs: [String],
                      ownUserID: String) -> NativeCallScope {
        guard isDM else { return .group }
        let humansBesidesMe = joinedMembersCount - activeServiceMembersCount - 1
        if activeServiceMembersCount > 0, humansBesidesMe <= 0 {
            return .assistant
        }
        let othersJoined = joinedMembersCount - 1
        let otherAgents = otherMemberIDs.filter { isAgent($0, ownUserID: ownUserID) }.count
        let othersAreAgents = otherAgents == otherMemberIDs.count
        return othersJoined > 0 && othersAreAgents && othersJoined <= otherAgents ? .assistant : .direct
    }

    /// Ring a DM and a small private room; a public room, a space or a
    /// large group gets a silent notification. Starting a call in a public
    /// room must never ring every phone in it.
    static func freshCallNotification(isDM: Bool,
                                      isSpace: Bool,
                                      isPrivate: Bool?,
                                      joinedMembersCount: Int) -> NativeCallNotification {
        guard !isDM else { return .ring }
        return !isSpace && isPrivate == true && joinedMembersCount <= ringMemberLimit ? .ring : .notification
    }
}

/// A device taking part in the call.
nonisolated struct MatrixRTCParticipant: Hashable {
    let userID: String
    let deviceID: String
    /// The identity this participant uses on the SFU.
    let identity: String
    /// "My language" as this membership publishes it (ADR-0094 A.1, `com.matrixagent.language`): opaque, nil when
    /// absent or empty. Only a catalog code is ever published; anything else reads as no language.
    var language: String?
}

/// Credentials for the SFU carrying the call's media.
struct MatrixRTCTransportCredentials {
    let url: URL
    /// Bearer credential for the SFU. Never log or persist it.
    let token: String
    // periphery:ignore - documents the schema, parsed but not consumed yet
    let identity: String
}

/// A media key belonging to a participant.
struct MatrixRTCEncryptionKey: Hashable {
    let participantIdentity: String
    let index: Int32
    let key: Data
}

enum MatrixRTCSessionUpdate {
    case participantsChanged([MatrixRTCParticipant])
    /// Outgoing media must be encrypted with this key from now on.
    case ownEncryptionKeyChanged(MatrixRTCEncryptionKey)
    /// A participant shared the key their media is encrypted with.
    case encryptionKeyReceived(MatrixRTCEncryptionKey)
    case ended
}

// sourcery: AutoMockable
protocol MatrixRTCSessionProtocol: AnyObject {
    /// The identity this client uses on the SFU.
    var ownIdentity: String { get }
    
    var updates: AnyPublisher<MatrixRTCSessionUpdate, Never> { get }
    
    /// Publish our membership and start driving the session. `notification`
    /// is what a FRESH call tells the room; `nil` joins silently.
    /// `language` is "my language" as a catalog code (ADR-0094 A.1); nil publishes none.
    func join(encryptMedia: Bool, notification: NativeCallNotification?, media: NativeCallMedia, language: String?) async -> Result<Void, MatrixRTCSessionError>

    /// Republish our live membership with a new language (ADR-0094 A.1), everything else unchanged. The same value
    /// again is a no-op; fails when not joined.
    func updateLanguage(_ language: String?) async -> Result<Void, MatrixRTCSessionError>

    /// Republish our live membership with a new per-participant media intent.
    func setMedia(_ media: NativeCallMedia) async -> Result<Void, MatrixRTCSessionError>
    
    /// The `m.rtc.notification` event this join sent, if it rang the room.
    /// Callers watch MSC4310 decline events for it to detect a refusal.
    func rtcNotificationEventID() async -> String?
    
    /// Withdraw our membership and stop driving the session.
    ///
    /// Returns a result like every other call here, because a leave that
    /// FAILS and a leave that succeeds have very different consequences: the
    /// membership stands until it expires, and no retry is possible — the SDK
    /// is already `Idle` by then, so a second `leave()` is a no-op.
    func leave() async -> Result<Void, MatrixRTCSessionError>
    
    /// Get credentials for the SFU carrying this session.
    func transportCredentials() async -> Result<MatrixRTCTransportCredentials, MatrixRTCSessionError>
    
    /// The call memberships in the room's state now, this device's own
    /// included. Read from the local store: a leave counts only once it has
    /// synced back. The SDK counts only joined members of the room (bug S2),
    /// and fails while a call member's room membership can't be told yet.
    func memberships() async -> Result<[MatrixRTCParticipant], MatrixRTCSessionError>
}
