//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, step 6): the owner publishes a generated
// Interactive Post from a draft the agent wrote into their DM thread.
//

import Foundation
import MatrixRustSDK

extension TimelineViewModel {
    // AGENT-PLATFORM (Brief 0066 step 6): publish a generated draft as a
    // post, in this room, as the owner.
    //
    // Pack the agent's manifest TEXT and source exactly as they came, and
    // refuse if the digest is not the agent's: a post published under a
    // digest other clients would reject is worse than no post. The bytes
    // are encrypted with a fresh attachment key and uploaded; the post
    // carries the `EncryptedFile`, which is what lets it be forwarded into
    // any room — receivers decrypt with the key IN the event, not the
    // room's — and what the SDK does for every photo in an encrypted room.
    func publishInteractiveDraft(itemID: TimelineItemIdentifier, asNew: Bool = false) async {
        guard let item = timelineController.timelineItems.firstUsingStableID(itemID) as? InteractiveDraftRoomTimelineItem else {
            return
        }
        let draft = item.draft

        guard let packed = draft.packed, draft.artifact != nil else {
            MXLog.error("[SpiralApp] draft \(draft.version) of \(draft.title) does not pack to its own digest")
            userIndicatorController.submitIndicator(.init(id: "spiral-draft-digest",
                                                          type: .toast,
                                                          title: UntranslatedL10n.screenRoomInteractiveDraftBadDigest))
            return
        }

        userIndicatorController.submitIndicator(.init(id: "spiral-draft-publish",
                                                      type: .modal(progress: .indeterminate, interactiveDismissDisabled: false, allowsInteraction: false),
                                                      title: UntranslatedL10n.screenRoomInteractiveDraftPublishing))
        defer { userIndicatorController.retractIndicatorWithId("spiral-draft-publish") }

        guard case .success(let upload) = await userSession.clientProxy.uploadEncryptedMedia(packed) else {
            userIndicatorController.submitIndicator(.init(id: "spiral-draft-upload", type: .toast, title: L10n.errorUnknown))
            return
        }

        // The runtime the post asks for is the manifest's: `1.1` when it
        // imports a name the runtime gained later, so an older app shows
        // its card with «update the app» instead of a blank row (§ 5.75).
        let manifest = SpiralAppManifest(json: Data(draft.manifestJSON.utf8))
        let post = InteractivePostContent(body: draft.title,
                                          appId: manifest?.appID ?? "generated",
                                          runtime: manifest?.runtime ?? "1",
                                          title: draft.title,
                                          aspect: draft.aspect,
                                          stateChannel: "matrix",
                                          sha256: draft.sha256,
                                          url: nil,
                                          fileJson: upload.fileJson)

        guard let content = try? contentWithoutRelationFromMessage(message: .init(msgType: .interactivePost(content: post),
                                                                                  body: draft.title,
                                                                                  isEdited: false,
                                                                                  mentions: nil)) else {
            MXLog.error("[SpiralApp] could not build the published post's content")
            return
        }

        // Into the room the request named (the modal flow), else into this
        // one. The target is resolved here rather than remembered: a room
        // the owner has since left is a failure, not a post somewhere else.
        // A thread with a LIVE post updates that post instead (§ 5.55).
        let live = asNew ? nil : state.spiralUpdatableLivePost
        let destination: JoinedRoomProxyProtocol
        let destinationID = live?.roomID ?? state.spiralPublishRoom?.id ?? draft.targetRoomID ?? roomProxy.id
        if destinationID == roomProxy.id {
            destination = roomProxy
        } else {
            guard case .joined(let target) = await userSession.clientProxy.roomForIdentifier(destinationID) else {
                MXLog.error("[SpiralApp] the draft's target room \(destinationID) is not one this user is in")
                userIndicatorController.submitIndicator(.init(id: "spiral-draft-target", type: .toast, title: L10n.errorUnknown))
                return
            }
            destination = target
        }
        let roomName = live?.roomName ?? userSession.clientProxy.roomSummaryForIdentifier(destinationID)?.name ?? destinationID

        if let live {
            // In place: the same event, so every vote and point already cast
            // is still its own, and the room shows «edited» as for a text.
            switch await destination.timeline.edit(.eventID(live.eventID), newContent: .roomMessage(content: content)) {
            case .success:
                MXLog.info("[SpiralApp] updated \(live.eventID) to draft v\(draft.version) — \(draft.sha256.prefix(12))")
                await noteInThread(live, action: "updated",
                                   body: UntranslatedL10n.screenRoomInteractivePostMarkerUpdated(draft.title, roomName))
                userIndicatorController.submitIndicator(.init(id: "spiral-post-updated", type: .toast, title: UntranslatedL10n.screenRoomInteractivePostUpdated))
                actionsSubject.send(.interactivePostPublished(roomID: destinationID))
            case .failure(let error):
                MXLog.error("[SpiralApp] updating the post failed: \(error)")
                userIndicatorController.submitIndicator(.init(id: "spiral-draft-send", type: .toast, title: L10n.errorUnknown))
            }
            return
        }

        // A new post goes out raw, for its event id: the thread is told which
        // post it now edits, and a timeline send does not say.
        guard let raw = SpiralAppPublisher.rawPostContent(post) else {
            MXLog.error("[SpiralApp] could not build the published post's raw content")
            return
        }
        // § 5.87: a refusal for a verified user's devices or identity asks
        // the user through the resolve sheet, then sends again.
        let sent = await RawSendResolution.send(roomProxy: destination,
                                                present: { failure, resolver in
                                                    // «Publishing…» takes no taps, and would sit over the sheet.
                                                    userIndicatorController.retractIndicatorWithId("spiral-draft-publish")
                                                    actionsSubject.send(.displayResolveSendFailure(failure: failure, resolver: resolver))
                                                },
                                                attempt: { await destination.sendSpiralRawEventReturningEventID(type: "m.room.message", content: raw) })
        switch sent {
        case .success(let eventID):
            MXLog.info("[SpiralApp] published draft v\(draft.version) of \(draft.title) — \(draft.sha256.prefix(12)) into \(destinationID) as \(eventID)")
            await noteInThread(SpiralLivePost(roomID: destinationID, eventID: eventID, roomName: roomName),
                               action: "published",
                               body: UntranslatedL10n.screenRoomInteractivePostMarkerPublished(roomName))
            userIndicatorController.submitIndicator(.init(id: "spiral-draft-published", type: .toast, title: UntranslatedL10n.screenRoomInteractiveDraftPublished))
            actionsSubject.send(.interactivePostPublished(roomID: destinationID))
            // Into this very timeline: the post lands at the bottom, as a sent
            // message does (§ 5.84). From a thread, or into another room, the
            // room's own flow scrolls when it is shown.
            if destinationID == roomProxy.id, case .thread = timelineController.timelineKind {
                // The thread's own bottom is not where the post went.
            } else if destinationID == roomProxy.id {
                context.send(viewAction: .scrollToBottom)
            }
        case .failure(.verifiedUser):
            break // The user said «not now» on the resolve sheet.
        case .failure(let error):
            MXLog.error("[SpiralApp] publishing the draft failed: \(error)")
            userIndicatorController.submitIndicator(.init(id: "spiral-draft-send", type: .toast, title: L10n.errorUnknown))
        }
    }

    /// «📌 …» into this thread, carrying which post it now edits.
    private func noteInThread(_ live: SpiralLivePost, action: String, body: String) async {
        guard case .thread(let rootEventID) = timelineController.timelineKind,
              let marker = live.markerContent(action: action, body: body, threadRootEventID: rootEventID) else {
            return
        }
        if case .failure(let error) = await roomProxy.sendSpiralRawEventReturningEventID(type: "m.room.message", content: marker) {
            MXLog.error("[SpiralApp] could not note the live post in the thread: \(error)")
        }
    }

    // MARK: - People and the live post

    /// The catalogue opened this thread from another room, and its drafts
    /// publish there (§ 5.56).
    func setSpiralPublishRoom(_ room: SpiralPublishRoom?) {
        state.spiralPublishRoom = room
    }

    /// The people of a room as `members.basic.read` answers them, for a
    /// draft that previews with the room it is FOR (nil: this room).
    func installSpiralMembersResolver() {
        state.spiralMembersResolver = { [weak self] roomID in
            guard let self else { return ["members": []] }
            let room: JoinedRoomProxyProtocol
            if let roomID, roomID != roomProxy.id {
                guard case .joined(let target) = await userSession.clientProxy.roomForIdentifier(roomID) else {
                    return ["members": []]
                }
                room = target
            } else {
                room = roomProxy
            }
            return await SpiralAppPostSession.membersPayload(room.members() ?? [], mediaProvider: userSession.mediaProvider)
        }
    }

    /// A person's name from their profile, for a notice naming someone outside
    /// this room (decision 38's relayed note). Remembered for the timeline: a
    /// recycled row asks again each time it appears.
    func installSpiralDisplayNameResolver() {
        let names = SpiralDisplayNames()
        state.spiralDisplayNameResolver = { [weak self] userID in
            if let name = names.byUserID[userID] { return name }
            guard let self, case .success(let profile) = await userSession.clientProxy.profile(for: userID),
                  let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            names.byUserID[userID] = name
            return name
        }
    }

    /// Whether the reader allowed third-party AI, for the notice that asks them
    /// to (decision 150). Read each time: they may just have changed it.
    func installSpiralAIConsentResolver() {
        state.spiralAIConsentResolver = { [weak self] in
            guard let service = self?.userSession.agentPlatformService,
                  case .success(let consent) = await service.fetchAIConsent() else {
                return nil
            }
            return consent.isGranted && !consent.needsDecision
        }
    }

    /// A generation thread whose post is out there updates it instead of
    /// posting another (§ 5.55).
    func updateSpiralLivePost(_ items: [RoomTimelineItemProtocol]) {
        guard timelineController.timelineKind.isThread else { return }
        let live = newestSpiralLivePost(in: items)
        if state.spiralLivePost != live {
            state.spiralLivePost = live
        }
    }

    /// The newest `com.spiral.live_post` note in this timeline. Only our own
    /// texts that start like one are asked for their raw JSON — the rest of
    /// a thread never pays for the lookup — and a local echo has none yet,
    /// so a note counts once the server has it.
    private func newestSpiralLivePost(in items: [RoomTimelineItemProtocol]) -> SpiralLivePost? {
        for item in items.reversed() {
            guard let text = item as? TextRoomTimelineItem,
                  text.isOutgoing,
                  text.body.hasPrefix(SpiralLivePost.bodyPrefix),
                  let json = timelineController.debugInfo(for: item.id).originalJSON,
                  let live = SpiralLivePost(eventJSON: json) else {
                continue
            }
            return live
        }
        return nil
    }
}

/// The names `installSpiralDisplayNameResolver` has read, by user ID.
private final class SpiralDisplayNames {
    var byUserID: [String: String] = [:]
}
