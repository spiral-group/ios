//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (§ 5.63): the catalogue on one screen.
//
// Chips for the sections, ONE live template at a time in a carousel with the
// edges of its neighbours showing, its name and one action under it, and
// the newest of «Yours» below with «All» for the rest. Twelve templates in
// a column were four thousand points of scrolling with «Yours» at the end;
// the system dialog that offered publish-or-change floated wherever iOS put
// it. Now nothing floats and nothing is far.
//

import Compound
import SwiftUI

struct InteractivePostCatalogScreen: View {
    @Bindable var context: InteractivePostCatalogScreenViewModel.Context

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // AGENT-PLATFORM (decision 129): without an agent, browse and Publish only.
                if context.viewState.assistant == .available {
                    describeNew
                }
                chips
                carousel
                dots
                current
                if context.viewState.assistant == .available {
                    yours
                }
            }
            .padding(.bottom, 16)
        }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .navigationTitle(UntranslatedL10n.screenInteractiveCatalogTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.actionCancel) { context.send(viewAction: .cancel) }
                    .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.cancel)
            }
        }
    }

    // MARK: - Describe a new one

    /// The invitation, first and in colour: the agent builds a post from a
    /// sentence, and that is the thing to show is easy (operator, 2026-09-25).
    /// On the primary action colour with the on-solid ink, as a solid
    /// Compound surface — no bespoke gradient.
    private var describeNew: some View {
        Button { context.send(viewAction: .startNew) } label: {
            HStack(spacing: 12) {
                CompoundIcon(\.edit, size: .medium, relativeTo: .compound.bodyLG)
                    .foregroundStyle(.compound.iconOnSolidPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.compound.bgCanvasDefault.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(UntranslatedL10n.screenInteractiveCatalogNew)
                        .font(.compound.bodyLGSemibold)
                        .foregroundColor(.compound.textOnSolidPrimary)
                    Text(UntranslatedL10n.screenInteractiveCatalogNewDescription)
                        .font(.compound.bodySM)
                        .foregroundColor(.compound.textOnSolidPrimary.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                CompoundIcon(\.chevronRight, size: .small, relativeTo: .compound.bodyLG)
                    .foregroundStyle(.compound.iconOnSolidPrimary.opacity(0.7))
            }
            .padding(14)
            .background(Color.compound.bgActionPrimaryRest)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.describeNew)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Sections

    /// The same chips the room list filters with.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                InteractivePostCatalogChip(title: UntranslatedL10n.screenInteractiveCatalogAll,
                                           isOn: context.section == nil) {
                    context.send(viewAction: .selectSection(nil))
                }
                ForEach(context.viewState.catalog?.sections ?? []) { section in
                    InteractivePostCatalogChip(title: section.localizedTitle,
                                               isOn: context.section == section.id) {
                        context.send(viewAction: .selectSection(section.id))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Carousel

    /// One card at a time, snapped; its neighbours show at the edges so a
    /// thumb knows there is more. The card shown and its neighbours run
    /// (`InteractivePostCatalogTemplateCell.liveReach`); `LazyHStack` builds a
    /// few more, which stay pictures.
    ///
    /// Rebuilt on every chip tap (`carouselGeneration`), so a section opens on
    /// its first card rather than wherever the last one's offset left it.
    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(context.viewState.cards) { card in
                    cardView(card)
                        .id(card.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $context.currentCardID)
        .id(context.viewState.carouselGeneration)
        .frame(height: InteractivePostCatalogTemplateCell.side)
        .padding(.top, 4)
        .readFrame($carouselFrame)
        // Centre the aligned card; the margin follows the container, not the screen.
        .contentMargins(.horizontal, max(0, (carouselFrame.width - InteractivePostCatalogTemplateCell.side) / 2), for: .scrollContent)
    }
    
    @State private var carouselFrame = CGRect.zero

    @ViewBuilder
    private func cardView(_ card: InteractivePostCatalogCard) -> some View {
        switch card {
        case .template(let template):
            InteractivePostCatalogTemplateCell(template: template,
                                               artifact: context.viewState.artifacts[template.id],
                                               viewerID: context.viewState.ownUserID,
                                               loadMembers: context.viewState.loadMembers,
                                               distance: context.viewState.distance(of: card))
        case .describeNew:
            Button { context.send(viewAction: .startNew) } label: {
                VStack(spacing: 12) {
                    CompoundIcon(\.plus, size: .custom(44), relativeTo: .compound.headingLG)
                        .foregroundStyle(.compound.iconAccentPrimary)
                    Text(UntranslatedL10n.screenInteractiveCatalogNew)
                        .font(.compound.bodyLGSemibold)
                        .foregroundColor(.compound.textPrimary)
                    Text(UntranslatedL10n.screenInteractiveCatalogNewDescription)
                        .font(.compound.bodySM)
                        .foregroundColor(.compound.textSecondary)
                }
                .frame(width: InteractivePostCatalogTemplateCell.side, height: InteractivePostCatalogTemplateCell.side)
                .background(Color.compound.bgSubtleSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private var dots: some View {
        let cards = context.viewState.cards
        let currentID = context.viewState.currentCard?.id
        return HStack(spacing: 5) {
            ForEach(cards) { card in
                Circle()
                    .fill(card.id == currentID ? Color.compound.iconAccentPrimary : Color.compound.bgSubtleSecondary)
                    .frame(width: card.id == currentID ? 8 : 6, height: card.id == currentID ? 8 : 6)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    // MARK: - The current card's name and action

    @ViewBuilder
    private var current: some View {
        if let template = context.viewState.currentCard?.template {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(template.localizedTitle)
                        .font(.compound.bodyLGSemibold)
                        .foregroundColor(.compound.textPrimary)
                        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.currentTitle)
                    if let section = context.viewState.sectionTitle(of: template) {
                        Text("· \(section)")
                            .font(.compound.bodyMD)
                            .foregroundColor(.compound.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if template.localizedAsk == nil, context.viewState.assistant == .available {
                        Menu {
                            Button(UntranslatedL10n.screenInteractiveCatalogChangeFirst) {
                                context.send(viewAction: .changeTemplate(template))
                            }
                        } label: {
                            CompoundIcon(\.overflowHorizontal, size: .medium, relativeTo: .compound.bodyLG)
                                .foregroundStyle(.compound.iconSecondary)
                                .frame(width: 44, height: 32)
                        }
                        .accessibilityLabel(UntranslatedL10n.screenInteractiveCatalogMore)
                    }
                }
                Text(template.localizedDescription)
                    .font(.compound.bodyMD)
                    .foregroundColor(.compound.textSecondary)
                    .lineLimit(2)

                if template.localizedAsk != nil, let note = assistantNote {
                    Text(note)
                        .font(.compound.bodySM)
                        .foregroundColor(.compound.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.assistantNote)
                } else if let ask = template.localizedAsk {
                    Button(action: { context.send(viewAction: .changeTemplate(template)) }) {
                        Text(UntranslatedL10n.screenInteractiveCatalogFillIn)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.compound(.primary))
                    .padding(.top, 12)
                    .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.fillIn)
                    Text(UntranslatedL10n.screenInteractiveCatalogPreviewAsks(ask))
                        .font(.compound.bodySM)
                        .foregroundColor(.compound.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                } else {
                    Button(action: { context.send(viewAction: .publishTemplate(template)) }) {
                        Label(UntranslatedL10n.screenRoomInteractivePostPublishIn(context.viewState.roomName), icon: \.send)
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.compound(.primary))
                    .disabled(context.viewState.artifacts[template.id] == nil)
                    .padding(.top, 12)
                    .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.publish)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        } else {
            // «Describe a new one» is its own button; nothing to say under it.
            Color.clear.frame(height: 8)
        }
    }

    /// Under a template that has to be filled in, for someone who can't fill
    /// it in now: why, which is not always "create an agent" (decision 129).
    private var assistantNote: String? {
        switch context.viewState.assistant {
        case .available: nil
        case .none: UntranslatedL10n.screenInteractiveCatalogNeedsAgent
        case .settingUp: UntranslatedL10n.screenInteractiveCatalogAgentSettingUp
        case .unknown: UntranslatedL10n.screenInteractiveCatalogAgentUnknown
        }
    }

    // MARK: - Yours

    private var yours: some View {
        VStack(spacing: 6) {
            HStack {
                Text(UntranslatedL10n.screenInteractiveCatalogMine)
                    .font(.compound.bodySMSemibold)
                    .foregroundColor(.compound.textSecondary)
                Spacer()
                if context.viewState.threads.count > context.viewState.recentThreads.count {
                    Button { context.send(viewAction: .showAllThreads) } label: {
                        HStack(spacing: 2) {
                            Text(UntranslatedL10n.screenInteractiveCatalogAll)
                            CompoundIcon(\.chevronRight, size: .xSmall, relativeTo: .compound.bodyMD)
                        }
                        .font(.compound.bodyMD)
                        .foregroundColor(.compound.textActionPrimary)
                    }
                }
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                if context.viewState.recentThreads.isEmpty {
                    // Empty is a promise, not a shrug: what will be here,
                    // and where it comes from.
                    VStack(spacing: 6) {
                        CompoundIcon(\.extensions, size: .custom(28), relativeTo: .compound.headingMD)
                            .foregroundStyle(.compound.iconTertiary)
                        Text(context.viewState.isLoading ? UntranslatedL10n.screenInteractiveCatalogLoading : UntranslatedL10n.screenInteractiveCatalogEmptyTitle)
                            .font(.compound.bodyMDSemibold)
                            .foregroundColor(.compound.textPrimary)
                        if !context.viewState.isLoading {
                            Text(UntranslatedL10n.screenInteractiveCatalogEmptyHint)
                                .font(.compound.bodySM)
                                .foregroundColor(.compound.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 16)
                }
                ForEach(context.viewState.recentThreads) { thread in
                    InteractivePostThreadRow(thread: thread) { context.send(viewAction: .openThread(thread)) }
                    if thread.id != context.viewState.recentThreads.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .background(Color.compound.bgCanvasDefaultLevel1)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
        .padding(.top, 18)
    }
}

/// A section chip — the room list's filter chip, the same style.
struct InteractivePostCatalogChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            Text(title)
        }
        .toggleStyle(FilterToggleStyle())
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
                    Text(thread.title ?? "«\(thread.madeForRoomName)»")
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// «for «Група» · 44 minutes ago», or the last word when it was no draft.
    static func description(of thread: InteractivePostThreadItem) -> String {
        let when = thread.lastActivity.formatted(.relative(presentation: .named))
        if thread.title != nil {
            return "«\(thread.madeForRoomName)» · \(when)"
        }
        guard let last = thread.lastMessage, !last.isEmpty else { return when }
        return "\(last) · \(when)"
    }
}

/// «Yours › All»: every thread, pushed over the catalogue (§ 5.63).
struct InteractivePostThreadsScreen: View {
    @Bindable var context: InteractivePostCatalogScreenViewModel.Context

    var body: some View {
        Form {
            Section {
                ForEach(context.viewState.threads) { thread in
                    ListRow(label: .default(title: thread.title ?? "«\(thread.madeForRoomName)»",
                                            description: InteractivePostThreadRow.description(of: thread),
                                            icon: \.extensions),
                            kind: .navigationLink { context.send(viewAction: .openThread(thread)) })
                }
            } footer: {
                Text(UntranslatedL10n.screenInteractiveCatalogMineFooter(context.viewState.roomName))
                    .compoundListSectionFooter()
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenInteractiveCatalogMine)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

struct InteractivePostCatalogScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: "https://spiral.md/catalog/", dms: [])

    static var previews: some View {
        ElementNavigationStack {
            InteractivePostCatalogScreen(context: viewModel.context)
        }
        .previewDisplayName("Loading")
    }
}
