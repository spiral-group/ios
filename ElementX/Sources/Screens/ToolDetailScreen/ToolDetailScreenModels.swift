//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359, item 12): someone else's tool, read-only.
//

import Compound
import SwiftUI

/// What a person may see of a tool. Built only from the safe slice (kind, trigger kind, language) and the server's
/// answer for this reader, so no id, params or scope can reach this page, not even from a read that carried them.
struct ToolDetail: Equatable {
    let title: String
    /// What the tool does; `nil` for a kind newer than this build.
    let explanation: String?
    let icon: KeyPath<CompoundIcons, Image>
    let agentName: String
    let agentMatrixUserID: String
    let agentAvatarURL: URL?
    /// `nil` for a company agent, which has no one person as its owner.
    let ownerName: String?
    /// `nil` for a trigger newer than this build: no words rather than wrong ones.
    let when: String?
    let appliesToViewer: ToolAppliesToViewer
    
    /// The "Your messages" value; a call tool has no such row.
    var yourMessages: String? {
        switch appliesToViewer {
        case .yes: UntranslatedL10n.screenToolDetailYourMessagesProcessed
        case .no: UntranslatedL10n.screenToolDetailYourMessagesNotProcessed
        case .unknown: UntranslatedL10n.screenToolDetailYourMessagesUnknown
        case .notApplicable: nil
        }
    }
    
    init(tool: RoomToolView, agent: RoomToolAgentEntry, agentAvatarURL: URL?, ownerName: String?) {
        title = ToolDisplayName.title(forKind: tool.toolKind, language: tool.targetLanguage)
        let kind = AgentToolKind(rawValue: tool.toolKind)
        explanation = kind?.explanation
        icon = ToolDisplayName.icon(forKind: tool.toolKind)
        agentName = agent.displayName
        agentMatrixUserID = agent.matrixUserID
        self.agentAvatarURL = agentAvatarURL
        self.ownerName = ownerName
        when = AgentToolTrigger.when(firing: AgentToolFiring(rawValue: tool.triggerKind))
        appliesToViewer = tool.appliesToViewer
    }
}

struct ToolDetailScreenViewState: BindableState {
    let detail: ToolDetail
}

enum ToolDetailScreenViewAction { }
