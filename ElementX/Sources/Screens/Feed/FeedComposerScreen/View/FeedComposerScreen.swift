//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082).
//

import Compound
import SpiralTokens
import SwiftUI

struct FeedComposerScreen: View {
    @Bindable var context: FeedComposerScreenViewModel.Context
    @FocusState private var isEditorFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space3X) {
                byline
                editor
                // At accessibility sizes the bar and the keyboard leave the words too little room, so this scrolls with them.
                if dynamicTypeSize.isAccessibilitySize {
                    standingNotice
                    publicNote
                }
            }
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.top, CompoundDesignTokens.space2X)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A tap anywhere on the page goes to the words.
        .onTapGesture { isEditorFocused = true }
        .feedSoftEdges()
        .scrollDismissesKeyboard(.interactively)
        // Brief 0083: the action rides on the keyboard, with what the person should know before they post.
        .backportSafeAreaBar(edge: .bottom, spacing: 0) { actionBar }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .feedBarTitle(UntranslatedL10n.screenFeedComposerTitle)
        .toolbar { toolbar }
        // A swipe would lose the text: Cancel asks what to do with it.
        .interactiveDismissDisabled(!context.text.isEmpty)
        .alert(item: $context.alertInfo)
        // An alert waiting on the sheet shows only after it has closed.
        .sheet(isPresented: $context.isPresentingRules,
               onDismiss: { context.send(viewAction: .rulesSheetDismissed) },
               content: {
                   FeedRulesSheet(isAccepting: context.viewState.isAcceptingRules,
                                  acceptFailed: context.viewState.rulesAcceptFailed,
                                  accept: { context.send(viewAction: .acceptRules) },
                                  decline: { context.send(viewAction: .declineRules) })
               })
        .onChange(of: context.text) { context.send(viewAction: .textChanged) }
        // The keyboard would leave the rules no room.
        .onChange(of: context.isPresentingRules) { _, isPresenting in
            if isPresenting {
                isEditorFocused = false
            }
        }
        .onChange(of: context.viewState.focusEditorRequest) { isEditorFocused = true }
        .onAppear { isEditorFocused = !context.isPresentingRules }
    }

    /// Who is writing, as the opened post will show it.
    private var byline: some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            LoadableAvatarImage(url: context.viewState.ownProfile?.avatarURL,
                                name: context.viewState.ownProfile?.displayName,
                                contentID: context.viewState.ownProfile?.id ?? "",
                                avatarSize: .custom(SpiralAvatarSize.small),
                                mediaProvider: context.mediaProvider)
                .accessibilityHidden(true)
            Text(context.viewState.ownProfile?.displayName ?? context.viewState.ownProfile?.id ?? "")
                .font(.compound.bodyLGSemibold)
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(1)
        }
    }

    /// At the opened post's size: what's typed is what will be read.
    private var editor: some View {
        TextField(UntranslatedL10n.screenFeedComposerPlaceholder,
                  text: $context.text,
                  prompt: Text(UntranslatedL10n.screenFeedComposerPlaceholder).foregroundStyle(SpiralComposerMetrics.placeholder),
                  axis: .vertical)
            .font(.compound.headingSM)
            .foregroundStyle(.compound.textPrimary)
            .lineLimit(6...)
            .focused($isEditorFocused)
            .accessibilityLabel(UntranslatedL10n.screenFeedComposerTitle)
            .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.textField)
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
            if !dynamicTypeSize.isAccessibilitySize {
                standingNotice
            }
            HStack(spacing: CompoundDesignTokens.space3X) {
                notes
                    .frame(maxWidth: .infinity, alignment: .leading)
                // The post shows at once on Latest as sending (decision 289).
                Button(UntranslatedL10n.screenFeedComposerPost) { context.send(viewAction: .post) }
                    .buttonStyle(.compound(.primary, size: .medium))
                    .fixedSize()
                    .disabled(!context.viewState.canPost)
                    .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.post)
            }
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space2X)
        // On the canvas, not clear: the notes are plain text, and the words ran under "Everyone on Spiral can see your post."
        .spiralComposerBar()
        .animation(.easeOut(duration: 0.15), value: context.viewState.counter)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space0_5X) {
            if let counter = context.viewState.counter {
                Text(counter.title)
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(counter.isOver ? .compound.textCriticalPrimary : .compound.textSecondary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.counter)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                publicNote
            }
        }
    }

    private var publicNote: some View {
        Text(UntranslatedL10n.screenFeedComposerPublicNote)
            .font(.compound.bodySM)
            .foregroundStyle(.compound.textSecondary)
    }

    @ViewBuilder
    private var standingNotice: some View {
        if let notice = context.viewState.standingNotice {
            noticeBox(notice, identifier: A11yIdentifiers.feedComposerScreen.standingNotice)
        }
    }

    private func noticeBox(_ text: String, identifier: String) -> some View {
        HStack(alignment: .top, spacing: CompoundDesignTokens.space2X) {
            CompoundIcon(\.info, size: .small, relativeTo: .compound.bodyMD)
                .foregroundStyle(.compound.iconInfoPrimary)
                .accessibilityHidden(true)
            Text(text)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CompoundDesignTokens.space3X)
        .background(.compound.bgInfoSubtle, in: .rect(cornerRadius: SpiralRadius.block))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.actionCancel) { context.send(viewAction: .cancel) }
                .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.cancel)
        }
    }
}

private extension FeedComposerScreenViewState.Counter {
    var isOver: Bool {
        if case .over = self { true } else { false }
    }
}

// MARK: - Previews

struct FeedComposerScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let emptyViewModel = makeViewModel()
    static let draftViewModel = makeViewModel(text: "First frost this morning. The kale is fine.")
    static let linkViewModel = makeViewModel(text: "Notes on https://example.org/garden", standing: newAccount)
    static let dailyCapViewModel = makeViewModel(text: "One more", standing: FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: true,
                                                                                         postsPerDay: 30, postsToday: 30, suspendedUntil: nil))
    static let nearLimitViewModel = makeViewModel(text: String(repeating: "a", count: 4900))
    static let overLimitViewModel = makeViewModel(text: String(repeating: "a", count: 5012))

    static var previews: some View {
        preview(emptyViewModel, name: "Empty")
        preview(draftViewModel, name: "Draft")
        preview(linkViewModel, name: "Link")
        preview(dailyCapViewModel, name: "Daily cap reached")
        preview(nearLimitViewModel, name: "Near the limit")
        preview(overLimitViewModel, name: "Over the limit")
    }

    private static func preview(_ viewModel: FeedComposerScreenViewModel, name: String) -> some View {
        ElementNavigationStack {
            FeedComposerScreen(context: viewModel.context)
        }
        .previewDisplayName(name)
    }

    private static let newAccount = FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: true,
                                                 postsPerDay: 30, postsToday: 1, suspendedUntil: nil)
    private static let trusted = FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: true,
                                              postsPerDay: 200, postsToday: 2, suspendedUntil: nil)

    static func makeViewModel(text: String? = nil, standing: FeedStanding = trusted) -> FeedComposerScreenViewModel {
        let service = FeedServiceMock()
        service.draftReturnValue = text.map { FeedDraft(text: $0, idempotencyKey: UUID()) }
        service.standingReturnValue = .success(standing)
        let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md", displayName: "Mira"))
        let viewModel = FeedComposerScreenViewModel(feedService: service, clientProxy: clientProxy, mediaProvider: MediaProviderMock(.init()))
        // Set at once so the snapshot does not wait on the read.
        viewModel.state.standing = standing
        return viewModel
    }
}
