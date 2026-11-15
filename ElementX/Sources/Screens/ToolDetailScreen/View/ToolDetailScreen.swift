//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralComponents
import SwiftUI

struct ToolDetailScreen: View {
    @Bindable var context: ToolDetailScreenViewModel.Context
    
    private var detail: ToolDetail {
        context.viewState.detail
    }
    
    var body: some View {
        Form {
            headerSection
            factsSection
            yourMessagesSection
        }
        .spiralGroupedList()
        .navigationTitle(UntranslatedL10n.screenAgentToolsListTitleUnknown)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var headerSection: some View {
        Section {
            VStack(spacing: CompoundDesignTokens.space2X) {
                CompoundIcon(detail.icon, size: .custom(32), relativeTo: .compound.headingLG)
                    .foregroundStyle(.compound.iconAccentPrimary)
                    .padding(CompoundDesignTokens.space3X)
                    .background(.compound.bgInfoSubtle, in: Circle())
                    .accessibilityHidden(true)
                Text(detail.title)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                if let explanation = detail.explanation {
                    Text(explanation)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
    
    private var factsSection: some View {
        Section {
            ListRow(label: .avatar(title: UntranslatedL10n.screenProfileAgentKindAgent, icon: agentAvatar),
                    details: .title(detail.agentName),
                    kind: .label)
            if let ownerName = detail.ownerName {
                ListRow(label: .default(title: L10n.screenRoomMemberListRoleOwner, icon: \.userProfile),
                        details: .title(ownerName),
                        kind: .label)
            }
            if let when = detail.when {
                ListRow(label: .default(title: UntranslatedL10n.screenToolDetailWhen, icon: \.time),
                        details: .title(when),
                        kind: .label)
            }
        }
    }
    
    private var agentAvatar: some View {
        LoadableAvatarImage(url: detail.agentAvatarURL,
                            name: detail.agentName,
                            contentID: detail.agentMatrixUserID,
                            avatarSize: .custom(28),
                            mediaProvider: context.mediaProvider)
    }
    
    private var yourMessagesSection: some View {
        Section {
            if let yourMessages = detail.yourMessages {
                ListRow(label: .default(title: UntranslatedL10n.screenToolDetailYourMessages, icon: \.chat),
                        details: .title(yourMessages),
                        kind: .label)
            }
        } footer: {
            Text(UntranslatedL10n.screenToolDetailFooter)
                .compoundListSectionFooter()
        }
    }
}

// MARK: - Previews

struct ToolDetailScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let processedViewModel = makeViewModel(kind: "translate", trigger: "on_message", language: "en", applies: .yes)
    static let notProcessedViewModel = makeViewModel(kind: "summarize", trigger: "on_message", language: nil, applies: .no)
    static let unknownViewModel = makeViewModel(kind: "simplify", trigger: "on_message", language: nil, applies: .unknown)
    static let callViewModel = makeViewModel(kind: "call_summary", trigger: "on_voice_call", language: nil, applies: .notApplicable)
    
    static var previews: some View {
        ElementNavigationStack {
            ToolDetailScreen(context: processedViewModel.context)
        }
        .previewDisplayName("Processed")
        
        ElementNavigationStack {
            ToolDetailScreen(context: notProcessedViewModel.context)
        }
        .previewDisplayName("Not processed")
        
        ElementNavigationStack {
            ToolDetailScreen(context: unknownViewModel.context)
        }
        .previewDisplayName("Couldn't check")
        
        ElementNavigationStack {
            ToolDetailScreen(context: callViewModel.context)
        }
        .previewDisplayName("Call tool")
    }
    
    private static func makeViewModel(kind: String, trigger: String, language: String?, applies: ToolAppliesToViewer) -> ToolDetailScreenViewModel {
        let tool = RoomToolView(toolID: nil, toolKind: kind, triggerKind: trigger, targetLanguage: language,
                                params: nil, trigger: nil, safeSliceSalt: "t1", appliesToViewer: applies)
        let agent = RoomToolAgentEntry(agentID: "a2", matrixUserID: "@bohdan-agent:example.com", displayName: "Bohdan's Agent",
                                       ownerUserID: "@bohdan:example.com", isMine: false, tools: [tool])
        return ToolDetailScreenViewModel(detail: ToolDetail(tool: tool, agent: agent, agentAvatarURL: nil, ownerName: "Bohdan"),
                                         mediaProvider: nil)
    }
}
