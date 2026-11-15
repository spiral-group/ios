//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (§ 5.56, questions 373, 412): Yours, behind the catalogue's
// «Yours». Making your own is harder than choosing, so it lives here rather
// than ahead of the catalogue: describe a new one, or go back to any thread
// you made one in.
//

import Compound
import SFSafeSymbols
import SpiralComponents
import SwiftUI

/// Yours as the catalogue's stack pushes it.
struct InteractivePostCatalogYoursScreen: View {
    let context: InteractivePostCatalogScreenViewModel.Context

    var body: some View {
        InteractivePostCatalogYoursView(context: context)
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .navigationTitle(UntranslatedL10n.screenInteractiveCatalogMine)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { context.send(viewAction: .screenAppeared(.yours)) }
            .onDisappear { context.send(viewAction: .screenDisappeared(.yours)) }
    }
}

struct InteractivePostCatalogYoursView: View {
    let context: InteractivePostCatalogScreenViewModel.Context

    var body: some View {
        switch context.viewState.threadsLoad {
        case .failed, .needsNewerApp:
            failure
        case .loading where context.viewState.threads.isEmpty:
            list { placeholders }
        case .loaded where context.viewState.threads.isEmpty:
            empty
        case .loading, .loaded:
            list { threads }
        }
    }

    private func list(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                describeNew
                content()
            }
            .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
            .padding(.vertical, 12)
        }
    }

    private var describeNew: some View {
        Button { context.send(viewAction: .startNew(description: nil)) } label: {
            Label(UntranslatedL10n.screenInteractiveCatalogNew, icon: \.edit)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.compound(.secondary))
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.describeNew)
    }

    private var placeholders: some View {
        SpiralPreloader(label: L10n.commonLoading) {
            SpiralCard {
                SpiralPlaceholderRows(count: 4, leading: .icon)
            }
        }
    }

    @ViewBuilder
    private var threads: some View {
        let threads = context.viewState.threads
        SpiralCard {
            ForEach(threads) { thread in
                InteractivePostThreadRow(thread: thread) { context.send(viewAction: .openThread(thread)) }
                if thread.id != threads.last?.id {
                    SpiralCardSeparator(leadingInset: 46)
                }
            }
        }
        Text(UntranslatedL10n.screenInteractiveCatalogMineFooter(context.viewState.roomName))
            .font(.compound.bodySM)
            .foregroundStyle(.compound.textSecondary)
    }

    private var empty: some View {
        SpiralEmptyState(symbol: .puzzlepieceExtension,
                         title: UntranslatedL10n.screenInteractiveCatalogEmptyTitle,
                         message: UntranslatedL10n.screenInteractiveCatalogEmptyHint)
            .centredInScrollView()
            .safeAreaInset(edge: .bottom) { describeNewAtTheBottom }
    }

    /// The pill stays: a list that couldn't be read is no reason to lose the
    /// one way to make a new one.
    private var failure: some View {
        SpiralEmptyState(symbol: .exclamationmarkCircle,
                         title: UntranslatedL10n.screenInteractiveCatalogMineError,
                         action: .init(L10n.actionRetry) { context.send(viewAction: .retryThreads) })
            .centredInScrollView()
            .safeAreaInset(edge: .bottom) { describeNewAtTheBottom }
    }

    /// At the bottom, where a thumb is, with nothing above it to reach past.
    private var describeNewAtTheBottom: some View {
        describeNew
            .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
            .padding(.bottom, 12)
    }
}

/// One of your threads, as a row: title, where and when, a chevron.
struct InteractivePostThreadRow: View {
    let thread: InteractivePostThreadItem
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                CompoundIcon(\.extensions, size: .medium, relativeTo: .compound.bodyLG)
                    .foregroundStyle(.compound.iconSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title ?? UntranslatedL10n.screenInteractiveCatalogRoomNameQuoted(thread.madeForRoomName))
                        .font(.compound.bodyLG)
                        .foregroundColor(.compound.textPrimary)
                        .lineLimit(1)
                    Text(Self.description(of: thread))
                        .font(.compound.bodySM)
                        .foregroundColor(.compound.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                CompoundIcon(\.chevronRight, size: .xSmall, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconQuaternary)
                    .flipsForRightToLeftLayoutDirection(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.spiralCardRow)
    }

    /// «for «Група» · 44 minutes ago», or the last word when it was no draft.
    static func description(of thread: InteractivePostThreadItem) -> String {
        let when = thread.lastActivity.formatted(.relative(presentation: .named))
        if thread.title != nil {
            return "\(UntranslatedL10n.screenInteractiveCatalogRoomNameQuoted(thread.madeForRoomName)) · \(when)"
        }
        guard let last = thread.lastMessage, !last.isEmpty else { return when }
        return "\(last) · \(when)"
    }
}

// MARK: - Previews

struct InteractivePostCatalogYoursScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    private static let fixture = InteractivePostCatalogPreviewFixture.self

    static let yours = fixture.viewModel(threads: fixture.threads)
    static let empty = fixture.viewModel()
    static let loading = fixture.viewModel(threadsLoad: .loading)
    static let failed = fixture.viewModel(threadsLoad: .failed)

    static var previews: some View {
        screen(yours, "Yours")
        screen(empty, "Yours empty")
        screen(loading, "Yours loading")
        screen(failed, "Yours failure")
    }

    private static func screen(_ viewModel: InteractivePostCatalogScreenViewModel, _ name: String) -> some View {
        ElementNavigationStack {
            InteractivePostCatalogYoursScreen(context: viewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName(name)
    }
}
