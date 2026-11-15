//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decisions 266, 287). The feed's section of
// the notification settings screen: likes, comments and replies, each "From
// everyone" or "Off".
//

import Compound
import SwiftUI

struct FeedNotificationSettingsSection: View {
    let context: FeedNotificationSettingsViewModel.Context

    var body: some View {
        switch context.viewState.settingsState {
        case .unavailable:
            EmptyView()
        case .loading:
            section {
                ForEach(FeedPushKind.allCases, id: \.self) { kind in
                    ListRow(label: .plain(title: kind.title), details: .isWaiting(true), kind: .label)
                }
            }
        case .failed:
            section {
                ListRow(label: .plain(title: UntranslatedL10n.screenFeedNotificationSettingsLoadFailed),
                        kind: .label)
                ListRow(label: .plain(title: L10n.actionRetry),
                        kind: .button { context.send(viewAction: .retry) })
            }
        case .loaded(let settings):
            section {
                ForEach(FeedPushKind.allCases, id: \.self) { kind in
                    row(kind, audience: settings[kind])
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ kind: FeedPushKind, audience: FeedPushAudience) -> some View {
        switch audience {
        case .everyone, .off:
            ListRow(label: .plain(title: kind.title),
                    kind: .picker(selection: Binding(get: { audience },
                                                     set: { context.send(viewAction: .set(kind, $0)) }),
                                  items: [(UntranslatedL10n.screenFeedNotificationSettingsEveryone, FeedPushAudience.everyone),
                                          (UntranslatedL10n.screenFeedNotificationSettingsOff, FeedPushAudience.off)]))
                .disabled(context.viewState.isSaving)
                .accessibilityIdentifier(kind.accessibilityIdentifier)
        case .other:
            // A choice newer than this build: shown, not offered (decision 96).
            ListRow(label: .plain(title: kind.title),
                    details: .title(UntranslatedL10n.screenFeedNotificationSettingsUpdateRequired),
                    kind: .label)
                .accessibilityIdentifier(kind.accessibilityIdentifier)
        }
    }

    private func section(@ViewBuilder rows: () -> some View) -> some View {
        Section {
            rows()
        } header: {
            Text(UntranslatedL10n.screenFeedNotificationSettingsTitle)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenFeedNotificationSettingsFooter)
                .compoundListSectionFooter()
        }
    }
}

private extension FeedPushKind {
    var title: String {
        switch self {
        case .likes: UntranslatedL10n.screenFeedNotificationSettingsLikes
        case .comments: UntranslatedL10n.screenFeedNotificationSettingsComments
        case .replies: UntranslatedL10n.screenFeedNotificationSettingsReplies
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .likes: A11yIdentifiers.feedNotificationSettings.likes
        case .comments: A11yIdentifiers.feedNotificationSettings.comments
        case .replies: A11yIdentifiers.feedNotificationSettings.replies
        }
    }
}

// MARK: - Previews

struct FeedNotificationSettingsSection_Previews: PreviewProvider, TestablePreview {
    static let everyoneViewModel = makeViewModel(.success(FeedNotificationSettings(likes: .everyone, comments: .everyone, replies: .everyone)))
    static let mixedViewModel = makeViewModel(.success(FeedNotificationSettings(likes: .off, comments: .everyone, replies: .off)))
    static let newerValueViewModel = makeViewModel(.success(FeedNotificationSettings(likes: .other("following"), comments: .everyone, replies: .off)))
    static let savingViewModel = makeViewModel(.success(FeedNotificationSettings(likes: .everyone, comments: .everyone, replies: .everyone)), isSaving: true)
    static let failedViewModel = makeViewModel(.failure(.transport))

    static var previews: some View {
        preview(everyoneViewModel, name: "Everyone")
        preview(mixedViewModel, name: "Mixed")
        preview(newerValueViewModel, name: "Newer value")
        preview(savingViewModel, name: "Saving")
        preview(failedViewModel, name: "Failed")
        preview(everyoneViewModel, name: "Everyone AX5")
            .dynamicTypeSize(.accessibility5)
    }

    private static func preview(_ viewModel: FeedNotificationSettingsViewModel, name: String) -> some View {
        Form {
            FeedNotificationSettingsSection(context: viewModel.context)
        }
        .compoundList()
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.settingsState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName(name)
    }

    static func makeViewModel(_ result: Result<FeedNotificationSettings, FeedError>, isSaving: Bool = false) -> FeedNotificationSettingsViewModel {
        let service = FeedServiceMock()
        service.notificationSettingsReturnValue = result
        let viewModel = FeedNotificationSettingsViewModel(feedService: service, userIndicatorController: UserIndicatorControllerMock())
        viewModel.state.isSaving = isSaving
        return viewModel
    }
}
