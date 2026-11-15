//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0078, ADR-0019 Principle 5): a person erases what
// their assistant remembers about one contact, from that contact's profile.
//

import SwiftUI

/// What `DELETE /me/memory` removed about one contact across every agent the
/// person owns. Kept whole for the log; the person reads one sentence.
nonisolated struct ContactErasure: Equatable, CustomStringConvertible {
    let memoryEntries: Int
    let relationships: Int
    let transcriptLines: Int
    let outreachTargets: Int
    let approvals: Int
    let keyRelayRows: Int
    let verifications: Int
    /// Entries kept with the contact's MXID taken out of them.
    let actionLogEntriesScrubbed: Int
    let sessionControlsScrubbed: Int
    let inviteRedemptionsScrubbed: Int
    /// Room tools the contact was taken out of, and of those the ones turned off.
    let toolScopesRewritten: Int
    let toolsTurnedOff: Int

    static let nothing = ContactErasure(memoryEntries: 0, relationships: 0, transcriptLines: 0, outreachTargets: 0,
                                        approvals: 0, keyRelayRows: 0, verifications: 0, actionLogEntriesScrubbed: 0,
                                        sessionControlsScrubbed: 0, inviteRedemptionsScrubbed: 0,
                                        toolScopesRewritten: 0, toolsTurnedOff: 0)

    /// Whether anything about the contact was found, scrubs included.
    var erasedAnything: Bool {
        [memoryEntries, relationships, transcriptLines, outreachTargets, approvals, keyRelayRows, verifications,
         actionLogEntriesScrubbed, sessionControlsScrubbed, inviteRedemptionsScrubbed, toolScopesRewritten, toolsTurnedOff]
            .contains { $0 > 0 }
    }

    /// Counts only — never who the contact was.
    var description: String {
        "memory \(memoryEntries), relationships \(relationships), transcript lines \(transcriptLines), "
            + "outreach \(outreachTargets), approvals \(approvals), key relay \(keyRelayRows), verifications \(verifications), "
            + "scrubbed: action log \(actionLogEntriesScrubbed), controls \(sessionControlsScrubbed), "
            + "invites \(inviteRedemptionsScrubbed), tool scopes \(toolScopesRewritten), tools off \(toolsTurnedOff)"
    }
}

/// Erases a contact from every agent the person owns (`DELETE /me/memory`,
/// hard delete, audited): what they asked to be remembered, the agents'
/// relationship with them, outreach and approvals about them, their lines in
/// the person's call transcripts, and their place in room tools. Their chats
/// stay. Says what happened in one sentence.
struct AssistantMemoryEraser {
    enum Outcome: Equatable {
        case erased
        case nothingSaved
        /// The backend refused the contact (`400`): malformed, or the person
        /// or one of their own agents, which the profile never offers. One
        /// problem type covers both, so the message must be true for both.
        case refused
        case failed
    }

    let agentPlatformService: AgentPlatformServiceProtocol
    let userIndicatorController: UserIndicatorControllerProtocol

    /// Whether a profile offers the erase: anyone's but the person's own and
    /// their own agents'. An agent's profile waits until whose it is is known
    /// rather than guess.
    static func offersErase(onProfileOf userID: String, ownership: AgentOwnership) -> Bool {
        guard SpiralAppPostSession.isAgent(userID) else { return true }
        return ownership == .someoneElses
    }

    /// The destructive confirmation, which says exactly what goes.
    func confirmation<T: Hashable>(id: T, contactName: String, onErase: @escaping () -> Void) -> AlertInfo<T> {
        AlertInfo(id: id,
                  title: UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryAlertTitle(contactName),
                  message: UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryAlertMessage(contactName),
                  primaryButton: .init(title: UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryAlertAction, role: .destructive, action: onErase),
                  secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
    }

    @discardableResult
    func erase(contactMXID: String, contactName: String) async -> Outcome {
        let outcome: Outcome
        switch await agentPlatformService.eraseAssistantMemory(aboutContact: contactMXID) {
        case .success(let erasure):
            MXLog.info("Erased a contact from the assistants: \(erasure)")
            // Memory is one count of twelve: a contact with no notes can still
            // have had transcript lines or a place in a room tool.
            outcome = erasure.erasedAnything ? .erased : .nothingSaved
        case .failure(.validation(let detail)):
            MXLog.error("The backend refused erasing this contact: \(detail)")
            outcome = .refused
        case .failure(let error):
            MXLog.error("Erasing a contact from the assistants failed: \(error)")
            outcome = .failed
        }

        let title = switch outcome {
        case .erased: UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryDone(contactName)
        case .nothingSaved: UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryNothing(contactName)
        case .refused: UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryRefused
        case .failed: UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemoryFailed
        }
        userIndicatorController.submitIndicator(.init(title: title, icon: outcome == .erased || outcome == .nothingSaved ? \.checkCircle : nil))
        return outcome
    }
}
