//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents
import SwiftUI

struct ModerationAndSafetySettingsScreen: View {
    @Bindable var context: ModerationAndSafetySettingsScreenViewModel.Context
    
    var body: some View {
        Form {
            aiConsentSection // AGENT-PLATFORM (decision 187)
            sharePresenceSection
            invitesSection
            timelineMediaSection
            blockedUsersSection
        }
        .spiralGroupedList() // AGENT-PLATFORM (Brief 0083): Spiral's grouped list, was `compoundList()`.
        .navigationTitle(UntranslatedL10n.screenSettingsPrivacyTitle) // AGENT-PLATFORM (decision 187)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // AGENT-PLATFORM (decision 187): the AI consent row comes first, in a section of
    // its own — decision 150's «Open Settings» lands here. Brief 0083, question 359:
    // it stands from the first frame; the read fills its switch.
    @ViewBuilder
    private var aiConsentSection: some View {
        if context.viewState.aiConsent != .unavailable {
            Section {
                aiConsentRow
            }
        }
    }
    
    private var sharePresenceSection: some View {
        Section {
            // AGENT-PLATFORM (Brief 0072, ADR-0084): the toggle is the account's
            // presence privacy too — say what it hides, and that it is mutual.
            ListRow(label: .plain(title: L10n.screenAdvancedSettingsSharePresence,
                                  description: UntranslatedL10n.screenAdvancedSettingsSharePresenceAccountDescription),
                    kind: .toggle($context.sharePresence))
        } header: {
            Text(L10n.screenModerationAndSafetySharePresenceHeading)
                .compoundListSectionHeader()
        }
    }
    
    // AGENT-PLATFORM (Brief 0078 phase 2): withdraw or give consent to third-party AI.
    @ViewBuilder
    private var aiConsentRow: some View {
        if context.viewState.aiConsent == .failed {
            // AGENT-PLATFORM (decision 150): the read failed — say so and offer a retry, never hide the choice.
            ListRow(label: .plain(title: UntranslatedL10n.screenAdvancedSettingsAiConsentTitle,
                                  description: L10n.commonSomethingWentWrongMessage),
                    details: .title(L10n.actionRetry, isWaiting: context.viewState.isWaitingAIConsent),
                    kind: .button {
                        context.send(viewAction: .retryAIConsent)
                    })
                    .disabled(context.viewState.isWaitingAIConsent)
                    .accessibilityIdentifier(A11yIdentifiers.advancedSettingsScreen.aiConsentRetry)
        } else if let granted = context.viewState.aiConsent.isGranted {
            let binding = Binding(get: {
                granted
            }, set: { newValue in
                context.send(viewAction: .updateAIConsent(newValue))
            })
            
            ListRow(label: .plain(title: UntranslatedL10n.screenAdvancedSettingsAiConsentTitle,
                                  description: UntranslatedL10n.screenAdvancedSettingsAiConsentDescription),
                    details: context.viewState.isWaitingAIConsent ? .isWaiting(true) : nil,
                    kind: .toggle(binding))
                .disabled(context.viewState.isWaitingAIConsent)
                // Not `.disabled`, which would dim a row that only waits for this opening's read.
                .allowsHitTesting(context.viewState.aiConsent.takesTaps)
                .accessibilityIdentifier(A11yIdentifiers.advancedSettingsScreen.aiConsent) // AGENT-PLATFORM (decision 148)
        } else {
            // AGENT-PLATFORM (Brief 0083, question 359): not known yet, so neither on nor off. `ListRow` has no slot for it.
            ListRow(kind: .custom {
                HStack(spacing: 0) {
                    ListRowLabel<EmptyView>.plain(title: UntranslatedL10n.screenAdvancedSettingsAiConsentTitle,
                                                  description: UntranslatedL10n.screenAdvancedSettingsAiConsentDescription)
                    Spacer()
                    SpiralPreloader(label: L10n.commonLoading) {
                        SpiralPlaceholderToggle()
                    }
                }
                .padding(.trailing, ListRowPadding.horizontal)
            })
        }
    }
    
    @ViewBuilder
    private var invitesSection: some View {
        let binding = Binding(get: {
            context.viewState.hideInviteAvatars
        }, set: { newValue in
            context.send(viewAction: .updateHideInviteAvatars(newValue))
        })
        
        Section {
            ListRow(label: .plain(title: L10n.screenAdvancedSettingsHideInviteAvatarsToggleTitle),
                    details: context.viewState.isWaitingHideInviteAvatars ? .isWaiting(true) : nil,
                    kind: .toggle(binding))
                .disabled(context.viewState.isWaitingHideInviteAvatars)
        } header: {
            Text(L10n.screenModerationAndSafetyInvitesHeading)
                .compoundListSectionHeader()
        }
    }
    
    @ViewBuilder
    private var timelineMediaSection: some View {
        let binding = Binding(get: {
            context.viewState.timelineMediaVisibility
        }, set: { newValue in
            context.send(viewAction: .updateTimelineMediaVisibility(newValue))
        })
        
        Section {
            ListRow(label: .plain(title: L10n.screenAdvancedSettingsShowMediaTimelineTitle),
                    details: .isWaiting(context.viewState.isWaitingTimelineMediaVisibility),
                    kind: .inlinePicker(selection: binding,
                                        items: TimelineMediaVisibility.items))
                .disabled(context.viewState.isWaitingTimelineMediaVisibility)
        } header: {
            Text(L10n.screenAdvancedSettingsShowMediaTimelineTitle)
                .compoundListSectionHeader()
        } footer: {
            Text(L10n.screenAdvancedSettingsShowMediaTimelineSubtitle)
                .compoundListSectionFooter()
        }
    }
    
    @ViewBuilder
    private var blockedUsersSection: some View {
        if context.viewState.showBlockedUsers {
            Section {
                ListRow(label: .default(title: L10n.commonBlockedUsers,
                                        icon: \.block),
                        kind: .navigationLink {
                            context.send(viewAction: .blockedUsers)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.advancedSettingsScreen.blockedUsers) // AGENT-PLATFORM (decision 187)
            }
        }
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083, lane settings): gated.
struct ModerationAndSafetySettingsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel(aiConsent: .success(AIConsent(isGranted: true, currentVersion: "2026-10-10", decidedVersion: "2026-10-10")))
    static let loadFailedViewModel = makeViewModel(aiConsent: .failure(.serverError(status: 500))) // AGENT-PLATFORM (decision 150)
    static let loadingViewModel = makeViewModel(aiConsent: nil) // AGENT-PLATFORM (decision 187)
    
    static var previews: some View {
        ElementNavigationStack {
            ModerationAndSafetySettingsScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.aiConsent).map(\.takesTaps))
        .previewDisplayName("Default")
        
        ElementNavigationStack {
            ModerationAndSafetySettingsScreen(context: loadFailedViewModel.context)
        }
        .snapshotPreferences(expect: loadFailedViewModel.context.observe(\.viewState.aiConsent).map { $0 == .failed })
        .previewDisplayName("AI consent not loaded")
        
        ElementNavigationStack {
            ModerationAndSafetySettingsScreen(context: loadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("AI consent loading")
    }
    
    // AGENT-PLATFORM (Brief 0078 phase 2): the AI consent row needs a platform service.
    // A `nil` consent is a read that never answers: the screen while consent loads.
    static func makeViewModel(aiConsent: Result<AIConsent, AgentPlatformError>?) -> ModerationAndSafetySettingsScreenViewModel {
        let service = AgentPlatformServiceMock()
        if let aiConsent {
            service.fetchAIConsentReturnValue = aiConsent
        } else {
            service.fetchAIConsentClosure = {
                try? await Task.sleep(for: .seconds(3600))
                return .failure(.serverError(status: 500))
            }
        }
        let userSession = UserSessionMock(.init())
        userSession.agentsStore = AgentsStore(service: service)
        return ModerationAndSafetySettingsScreenViewModel(userSession: userSession,
                                                          userIndicatorController: UserIndicatorControllerMock())
    }
}

private extension TimelineMediaVisibility {
    static var items: [(title: String, tag: TimelineMediaVisibility)] {
        [(title: L10n.screenAdvancedSettingsShowMediaTimelineAlwaysHide, tag: .never),
         (title: L10n.screenAdvancedSettingsShowMediaTimelinePrivateRooms, tag: .privateOnly),
         (title: L10n.screenAdvancedSettingsShowMediaTimelineAlwaysShow, tag: .always)]
    }
}
