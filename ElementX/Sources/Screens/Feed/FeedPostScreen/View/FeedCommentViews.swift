//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A post's flat comments and the field
// that sends one (lane I3). Each row is one VoiceOver element whose custom
// actions are Reply, Delete, Report, the author and the row's links.
//

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

struct FeedCommentsSection: View {
    let context: FeedPostScreenViewModel.Context

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UntranslatedL10n.screenFeedCommentsTitle)
                .font(.compound.headingSMSemibold)
                .foregroundStyle(.compound.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, CompoundDesignTokens.space4X)
                .padding(.top, CompoundDesignTokens.space4X)
                .padding(.bottom, CompoundDesignTokens.space1X)

            if let post = context.viewState.post, !post.commentsEnabled, post.viewer.isAuthor {
                // The author's own view: they still see and delete what was said.
                note(UntranslatedL10n.screenFeedCommentsOffAuthor)
                    .accessibilityIdentifier(A11yIdentifiers.feedScreen.commentsOff)
            }

            switch context.viewState.commentsState {
            case .loading:
                // Decision 330: comments as placeholders, after a short delay.
                SpiralPreloader(label: L10n.commonLoading) {
                    SpiralPlaceholderRows(count: 2, leading: .avatar(Avatars.Size.user(on: .timeline).value))
                }
            case .off:
                note(UntranslatedL10n.screenFeedCommentsOff)
                    .accessibilityIdentifier(A11yIdentifiers.feedScreen.commentsOff)
            case .notAvailable:
                note(UntranslatedL10n.screenFeedCommentsNotAvailable)
            case .failed:
                VStack(alignment: .leading, spacing: 8) {
                    Text(UntranslatedL10n.screenFeedCommentsLoadFailed)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                    Button(L10n.actionRetry) { context.send(viewAction: .retryComments) }
                        .buttonStyle(.compound(.secondary, size: .small))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            case .loaded:
                if context.viewState.hasNoComments {
                    note(UntranslatedL10n.screenFeedCommentsEmpty)
                }
                let items = context.viewState.visibleComments
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    FeedCommentRow(item: item,
                                   isSetIn: index > 0 && item.comment.replyTo?.id == items[index - 1].id,
                                   isRevealed: context.viewState.revealedCommentIDs.contains(item.id),
                                   canReply: context.viewState.canComment && item.canReply,
                                   isFocused: item.id == context.viewState.focusedCommentID,
                                   mediaProvider: context.mediaProvider) { action in
                        switch action {
                        case .reply: context.send(viewAction: .reply(commentID: item.id))
                        case .delete: context.send(viewAction: .deleteComment(commentID: item.id))
                        case .reveal: context.send(viewAction: .revealComment(commentID: item.id))
                        case .openAuthor: context.send(viewAction: .openCommentAuthor(commentID: item.id))
                        case .report: context.send(viewAction: .reportComment(commentID: item.id))
                        case .retry, .discard: break
                        }
                    }
                }
                if let sentinel = context.viewState.commentsSentinel {
                    sentinelView(sentinel)
                }
                ForEach(context.viewState.pendingComments) { item in
                    FeedCommentRow(item: item,
                                   isRevealed: true,
                                   canReply: false,
                                   mediaProvider: context.mediaProvider) { action in
                        guard let key = item.pendingKey else { return }
                        switch action {
                        case .retry: context.send(viewAction: .retryComment(key))
                        case .discard: context.send(viewAction: .discardComment(key))
                        case .reply, .delete, .reveal, .openAuthor, .report: break
                        }
                    }
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.compound.bodyMD)
            .foregroundStyle(.compound.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
    }

    @ViewBuilder
    private func sentinelView(_ state: LoadMoreState) -> some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        case .failed:
            Button(UntranslatedL10n.screenAgentActivityLoadMoreFailed) { context.send(viewAction: .loadMoreComments) }
                .buttonStyle(.compound(.tertiary, size: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        case .idle, .exhausted:
            Button(UntranslatedL10n.screenFeedCommentsLoadMore) { context.send(viewAction: .loadMoreComments) }
                .buttonStyle(.compound(.tertiary, size: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }
}

enum FeedCommentRowAction {
    case reply
    case delete
    case reveal
    case openAuthor
    /// Lane I3 on B4.
    case report
    /// The person's comment on its way that failed (decision 289).
    case retry
    case discard
}

struct FeedCommentRow: View {
    let item: FeedCommentItem
    /// A reply right under what it answers is set in, and needs no "Replying to".
    var isSetIn = false
    let isRevealed: Bool
    let canReply: Bool
    /// Lane I5: the comment an Activity entry opened the post at, marked.
    var isFocused = false
    let mediaProvider: MediaProviderProtocol?
    let action: (FeedCommentRowAction) -> Void

    @Environment(\.openURL) private var openURL

    private var comment: FeedComment {
        item.comment
    }

    var body: some View {
        if item.isPending {
            row
                .accessibilityIdentifier(A11yIdentifiers.feedScreen.pendingComment)
        } else if item.isAvailable {
            row
        } else {
            FeedNoticeBox(text: UntranslatedL10n.screenFeedCommentNotAvailable)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityIdentifier(A11yIdentifiers.feedScreen.commentRow)
        }
    }

    /// Brief 0083: a comment as a note under the post: a short byline, the words, then Reply. No bubble.
    private var row: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
            byline
                .padding(.vertical, -CompoundDesignTokens.space2X)
            if let reply = comment.replyTo, !isSetIn {
                Text(UntranslatedL10n.screenFeedCommentReplyingTo(reply.author.displayName))
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }
            if let label = item.authorLabel {
                Text(label)
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.textSecondary)
            }
            text
            Group {
                if let delivery = item.delivery {
                    deliveryStatus(delivery)
                } else if canReply {
                    Button(UntranslatedL10n.screenFeedCommentReply) { action(.reply) }
                        .font(.compound.bodySMSemibold)
                        .foregroundStyle(.compound.textSecondary)
                        .buttonStyle(FeedCommentActionButtonStyle())
                }
            }
            // The line's 44 pt target reaches into the space around it, so it sits as close as a caption.
            .padding(.vertical, -CompoundDesignTokens.space1_5X)
        }
        .padding(.vertical, isFocused ? CompoundDesignTokens.space2X : 0)
        .padding(.horizontal, isFocused ? CompoundDesignTokens.space3X : 0)
        .overlay {
            // Lane I5: the comment an Activity entry opened the post at, outlined in the accent.
            if isFocused {
                RoundedRectangle(cornerRadius: SpiralRadius.block, style: .continuous)
                    .stroke(.compound.iconAccentPrimary, lineWidth: 1.5)
            }
        }
        .padding(.leading, isSetIn ? CompoundDesignTokens.space8X : 0)
        .padding(.top, CompoundDesignTokens.space4X)
        .padding(.horizontal, isFocused ? CompoundDesignTokens.space1X : CompoundDesignTokens.space4X)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel(isRevealed: isRevealed))
        .accessibilityActions { accessibilityActions }
        .accessibilityIdentifier(A11yIdentifiers.feedScreen.commentRow)
    }

    /// The avatar, the name and the time on one line, Delete and Report behind "…" at its end.
    private var byline: some View {
        HStack(spacing: CompoundDesignTokens.space2X) {
            Button { action(.openAuthor) } label: {
                HStack(spacing: CompoundDesignTokens.space2X) {
                    LoadableAvatarImage(url: comment.author.avatarURL,
                                        name: comment.author.displayName,
                                        contentID: comment.author.userID,
                                        avatarSize: .custom(SpiralAvatarSize.xSmall),
                                        mediaProvider: mediaProvider)
                    Text(comment.author.displayName)
                        .font(.compound.bodyMDSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)
                    if comment.author.isOfficial {
                        FeedOfficialSeal()
                    }
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if !item.isPending {
                FeedShortTime(date: comment.createdAt)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
            Spacer(minLength: 0)
            menu
        }
    }

    @ViewBuilder
    private var menu: some View {
        if comment.canDelete || item.canReport {
            Menu {
                if item.canReport {
                    Button { action(.report) } label: {
                        Label(UntranslatedL10n.screenFeedCommentReport, icon: \.chatProblem)
                    }
                    .accessibilityIdentifier(A11yIdentifiers.feedScreen.reportComment)
                }
                if comment.canDelete {
                    Button(role: .destructive) { action(.delete) } label: {
                        Label(UntranslatedL10n.screenFeedCommentDelete, icon: \.delete)
                    }
                }
            } label: {
                CompoundIcon(\.overflowHorizontal, size: .small, relativeTo: .compound.bodySM)
                    .foregroundStyle(.compound.iconSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .accessibilityLabel(UntranslatedL10n.screenProfileActionMore)
            }
            .padding(.trailing, -CompoundDesignTokens.space3X)
        }
    }

    @ViewBuilder
    private var text: some View {
        if comment.isSensitive, !isRevealed {
            // Decision 265: one "Show" over the text, as for a post.
            HStack(spacing: CompoundDesignTokens.space3X) {
                Text(UntranslatedL10n.screenFeedSensitiveTitle)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                Button(UntranslatedL10n.screenFeedSensitiveShow) { action(.reveal) }
                    .buttonStyle(.compound(.tertiary, size: .small))
            }
        } else if let text = item.text {
            Text(text)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textPrimary)
                .tint(.compound.textLinkExternal)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(item.delivery == .sending ? 0.6 : 1)
        }
    }

    @ViewBuilder
    private func deliveryStatus(_ delivery: FeedDelivery) -> some View {
        switch delivery {
        case .sending:
            Text(L10n.commonSending)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
                .frame(minHeight: 44)
        case .failed:
            HStack(spacing: CompoundDesignTokens.space4X) {
                Text(UntranslatedL10n.screenFeedCommentSendFailed)
                    .foregroundStyle(.compound.textCriticalPrimary)
                Button(L10n.actionRetry) { action(.retry) }
                    .foregroundStyle(.compound.textSecondary)
                Button(L10n.actionDiscard, role: .destructive) { action(.discard) }
                    .foregroundStyle(.compound.textSecondary)
            }
            .font(.compound.bodySMSemibold)
            .buttonStyle(FeedCommentActionButtonStyle())
        }
    }

    @ViewBuilder
    private var accessibilityActions: some View {
        if case .failed = item.delivery {
            Button(L10n.actionRetry) { action(.retry) }
            Button(L10n.actionDiscard) { action(.discard) }
        }
        if comment.isSensitive, !isRevealed {
            Button(UntranslatedL10n.screenFeedSensitiveShow) { action(.reveal) }
        }
        if canReply {
            Button(UntranslatedL10n.screenFeedCommentReply) { action(.reply) }
        }
        if comment.canDelete {
            Button(UntranslatedL10n.screenFeedCommentDelete) { action(.delete) }
        }
        if item.canReport {
            Button(UntranslatedL10n.screenFeedCommentReport) { action(.report) }
        }
        Button(UntranslatedL10n.a11yFeedOpenAuthor(comment.author.displayName)) { action(.openAuthor) }
        if !comment.isSensitive || isRevealed {
            ForEach(item.links, id: \.self) { url in
                Button(UntranslatedL10n.a11yFeedOpenLink(url.host() ?? url.absoluteString)) { openURL(url) }
            }
        }
    }
}

/// A comment's action as grey text in a 44 pt target (Brief 0083).
private struct FeedCommentActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minHeight: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// The field at the bottom of a post that takes comments. It is the room's composer field (Brief 0083): the reply
/// above the text, send inside the field's trailing end, on the room's composer bar.
struct FeedCommentComposer: View {
    @Bindable var context: FeedPostScreenViewModel.Context
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
            if let notice = context.viewState.commentCapNotice {
                Text(notice)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }
            TextField(UntranslatedL10n.screenFeedCommentPlaceholder,
                      text: $context.commentText,
                      prompt: Text(UntranslatedL10n.screenFeedCommentPlaceholder).foregroundStyle(SpiralComposerMetrics.placeholder),
                      axis: .vertical)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(1...5)
                .focused(isFocused)
                .accessibilityIdentifier(A11yIdentifiers.feedScreen.commentField)
                .messageComposerStyle(header: replyHeader, trailing: sendButton)
            if let counter = context.viewState.commentCounter {
                Text(counter)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }
        }
        .padding(.horizontal, CompoundDesignTokens.space3X)
        .padding(.top, CompoundDesignTokens.space2X)
        .padding(.bottom, CompoundDesignTokens.space3X)
        .spiralComposerBar(scrollsUnder: true) // With Liquid Glass the comments run under the field, as a room's timeline does.
    }

    @ViewBuilder
    private var replyHeader: some View {
        if let reply = context.viewState.replyingTo {
            SpiralComposerHeader(closeLabel: UntranslatedL10n.a11yFeedCancelReply,
                                 close: { context.send(viewAction: .cancelReply) },
                                 content: {
                                     Text(UntranslatedL10n.screenFeedCommentReplyingTo(reply.comment.author.displayName))
                                         .font(.compound.bodySMSemibold)
                                         .foregroundStyle(.compound.textSecondary)
                                 })
        }
    }

    private var sendButton: some View {
        SendButton { context.send(viewAction: .sendComment) }
            .disabled(!context.viewState.canSendComment)
            .accessibilityLabel(UntranslatedL10n.a11yFeedSendComment)
            .accessibilityIdentifier(A11yIdentifiers.feedScreen.sendComment)
    }
}
