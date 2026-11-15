//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (decision 289). The sync's state at the top of a feed
// screen ("Updating…" / "No connection", small, in place of a manual refresh)
// and a post on its way at the top of Latest.
//

import Compound
import SpiralTokens
import SwiftUI

/// A small capsule under the navigation bar while the sync stream is not live.
struct FeedSyncStatusBanner: View {
    let status: PlatformSyncStatus?

    var body: some View {
        if let status {
            HStack(spacing: 6) {
                switch status {
                case .updating:
                    ProgressView()
                        .controlSize(.mini)
                    Text(UntranslatedL10n.screenFeedSyncUpdating)
                case .noConnection:
                    CompoundIcon(\.offline, size: .xSmall, relativeTo: .compound.bodySMSemibold)
                        .accessibilityHidden(true)
                    Text(UntranslatedL10n.screenFeedSyncNoConnection)
                }
            }
            .font(.compound.bodySMSemibold)
            .foregroundStyle(.compound.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.compound.bgSubtleSecondary, in: .capsule)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(A11yIdentifiers.feedScreen.syncStatus)
            .transition(.opacity)
        }
    }
}

extension View {
    /// The sync's state above the screen's content, which moves down for it while it shows.
    func feedSyncStatus(_ status: PlatformSyncStatus?) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            FeedSyncStatusBanner(status: status)
                .frame(maxWidth: .infinity)
                .animation(.default, value: status)
        }
    }
}

/// The person's post on its way, in a post's column: "Sending…", or why it failed with Retry and Discard.
struct FeedPendingPostRow: View {
    let pending: FeedPendingPost
    let profile: UserProfile?
    let mediaProvider: MediaProviderProtocol?
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: CompoundDesignTokens.space3X) {
            LoadableAvatarImage(url: profile?.avatarURL,
                                name: profile?.displayName,
                                contentID: profile?.id ?? "",
                                avatarSize: .custom(SpiralAvatarSize.small),
                                mediaProvider: mediaProvider)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
                Text(profile?.displayName ?? profile?.id ?? "")
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(1)
                Text(pending.text)
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                status
                    .padding(.top, CompoundDesignTokens.space1X)
            }
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .accessibilityIdentifier(A11yIdentifiers.feedScreen.pendingPost)
    }

    @ViewBuilder
    private var status: some View {
        switch pending.delivery {
        case .sending:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.commonSending)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UntranslatedL10n.screenFeedPostSendFailed)
                            .font(.compound.bodySMSemibold)
                        Text(FeedComposerScreenViewModel.message(for: error).message)
                            .font(.compound.bodySM)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    CompoundIcon(\.errorSolid, size: .xSmall, relativeTo: .compound.bodySMSemibold)
                }
                .foregroundStyle(.compound.textCriticalPrimary)
                HStack(spacing: 8) {
                    Button(L10n.actionRetry, action: retry)
                        .buttonStyle(.compound(.secondary, size: .small))
                    Button(L10n.actionDiscard, role: .destructive, action: discard)
                        .buttonStyle(.compound(.tertiary, size: .small))
                }
            }
        }
    }
}
