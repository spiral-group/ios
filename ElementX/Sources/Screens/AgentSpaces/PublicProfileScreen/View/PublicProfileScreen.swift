//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreen.swift`.
//
// Visitor-side "Contact agent" entry point per
// `docs/project/DESIGNS/agent-platform-screens.md`
// § PublicProfileScreen. Renders the target user's public
// agents with persona previews + per-row "Contact agent"
// buttons; coordinator hands the tap off to the existing
// chat-flow DM resolution path.

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

struct PublicProfileScreen: View {
    @Bindable var context: PublicProfileScreenViewModel.Context

    var body: some View {
        Form {
            switch context.viewState.detailState {
            case .loading:
                loadingSections
            case .loaded(let profile):
                Section {
                    header(profile: profile)
                }
                if profile.publicAgents.isEmpty {
                    emptyAgentsSection
                } else {
                    agentsSection {
                        ForEach(profile.publicAgents) { agent in
                            agentRow(agent)
                        }
                    }
                }
            case .notFound:
                notFoundSection
            case .selfLookup:
                selfLookupSection
            case .failed(let reason):
                failedSection(reason: reason)
            }
        }
        .spiralGroupedList() // Brief 0083 (P4-D): iOS's grouped cards and plain grey glyphs (decision 337).
        .navigationTitle(UntranslatedL10n.screenPublicProfileTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .feedSyncStatus(context.viewState.syncStatus) // AGENT-PLATFORM: platform sync (decision 289)
    }

    // MARK: - Sections

    // AGENT-PLATFORM (Brief 0083, question 359): the header and an agent's card as placeholders, after a short delay
    // (decision 330). How many agents the person has is the read's to say.
    @ViewBuilder
    private var loadingSections: some View {
        Section {
            SpiralPreloader(label: L10n.commonLoading) {
                header(profile: UserProfileView(mxid: context.viewState.targetMXID,
                                                displayName: String(repeating: "0", count: 10),
                                                publicAgents: []))
            }
        }
        
        agentsSection {
            SpiralPreloader(label: L10n.commonLoading) {
                agentRow(Self.placeholderAgent)
            }
            .accessibilityHidden(true) // The header reads "Loading…" for the screen.
        }
    }
    
    private static let placeholderAgent = PublicAgentSummary(id: "placeholder",
                                                             matrixUserID: "@" + String(repeating: "0", count: 24),
                                                             displayName: String(repeating: "0", count: 16),
                                                             tone: String(repeating: "0", count: 26),
                                                             greeting: String(repeating: "0", count: 30),
                                                             visitorGreeting: String(repeating: "0", count: 34),
                                                             createdAt: .distantPast)

    // Canon F7 (variant A): a real avatar header, with an initial-avatar (no avatar URL on the wire yet;
    // `LoadableAvatarImage` renders the canonical initial fallback). Brief 0083 (P4-D): the agent card's profile
    // layout, as an agent's screen and Settings draw their header.
    private func header(profile: UserProfileView) -> some View {
        SpiralAgentCard(layout: .profile,
                        name: profile.displayName,
                        subtitle: profile.mxid) {
            LoadableAvatarImage(url: nil,
                                name: profile.displayName,
                                contentID: profile.mxid,
                                avatarSize: .user(on: .memberDetails),
                                mediaProvider: context.mediaProvider)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        } accessory: {
            EmptyView()
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var emptyAgentsSection: some View {
        Section {
            // Under the person's header: one part of the screen, not the whole of it.
            SpiralEmptyState(symbol: .sparkles,
                             title: UntranslatedL10n.screenPublicProfileEmptyTitle,
                             message: UntranslatedL10n.screenPublicProfileEmptySubtitle,
                             size: .compact)
                .listRowBackground(Color.clear)
        }
    }

    private func agentsSection(@ViewBuilder rows: () -> some View) -> some View {
        Section {
            rows()
        } header: {
            Text(UntranslatedL10n.screenPublicProfileAgentsSectionTitle)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenPublicProfileAgentsSectionFooter)
                .compoundListSectionFooter()
        }
    }

    /// Brief 0083 (P4-D): Spiral's agent card, the avatar and name over what the agent says, then Contact agent.
    private func agentRow(_ agent: PublicAgentSummary) -> some View {
        let name = agent.displayName ?? Self.fallbackName(for: agent.matrixUserID)
        return ListRow(kind: .custom {
            SpiralAgentCard(name: name,
                            details: agent.matrixUserID) {
                LoadableAvatarImage(url: nil,
                                    name: name,
                                    contentID: agent.matrixUserID,
                                    avatarSize: .custom(SpiralAvatarSize.medium),
                                    mediaProvider: context.mediaProvider)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            } actions: {
                VStack(alignment: .leading, spacing: CompoundDesignTokens.space3X) {
                    persona(agent)

                    Button {
                        context.send(viewAction: .contactAgent(matrixUserID: agent.matrixUserID))
                    } label: {
                        // As the agent's screen draws its buttons: the title only, the card's full width (329).
                        Text(UntranslatedL10n.screenPublicProfileActionContactAgent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.compound(.primary, size: .medium))
                    .accessibilityLabel(UntranslatedL10n.a11yScreenPublicProfileActionContactAgent(agent.matrixUserID))
                }
            }
        })
    }

    @ViewBuilder
    private func persona(_ agent: PublicAgentSummary) -> some View {
        if let tone = agent.tone, !tone.isEmpty {
            Text(tone)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        }

        if let greeting = agent.greeting, !greeting.isEmpty {
            Text(greeting)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
        }

        if let visitor = agent.visitorGreeting, !visitor.isEmpty {
            // Canon F9: italics aren't a Compound typography variant.
            Text(visitor)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var notFoundSection: some View {
        Section {
            SpiralEmptyState(symbol: .personCropCircleBadgeXmark,
                             title: UntranslatedL10n.screenPublicProfileNotFoundTitle,
                             message: UntranslatedL10n.screenPublicProfileNotFoundSubtitle(context.viewState.targetMXID))
                .listRowBackground(Color.clear)
        }
    }

    private var selfLookupSection: some View {
        Section {
            SpiralEmptyState(symbol: .personCropCircle,
                             title: UntranslatedL10n.screenPublicProfileSelfTitle,
                             message: UntranslatedL10n.screenPublicProfileSelfSubtitle)
                .listRowBackground(Color.clear)
        }
    }

    private func failedSection(reason: String) -> some View {
        AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenPublicProfileLoadFailed) {
            context.send(viewAction: .retry)
        }
        .accessibilityHint(reason)
    }

    /// Derive a human label from `@localpart:server` when the
    /// persona didn't supply one. Matches the backend's
    /// `derive_display_name` behaviour (capitalise localpart).
    static func fallbackName(for mxid: String) -> String {
        let localpart = mxid.dropFirst() // drop leading `@`
            .prefix { $0 != ":" }
        var chars = String(localpart).makeIterator()
        guard let first = chars.next() else { return mxid }
        return String(first).uppercased() + String(IteratorSequence(chars))
    }
}

// MARK: - Previews

struct PublicProfileScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let sampleProfile = UserProfileView(mxid: "@alice:spiral.md",
                                               displayName: "Alice",
                                               publicAgents: [
                                                   PublicAgentSummary(id: "agent-1",
                                                                      matrixUserID: "@assistant-alice:spiral.md",
                                                                      displayName: "Alice's assistant",
                                                                      tone: "warm, concise, professional",
                                                                      greeting: "Hi! I'm Alice's assistant.",
                                                                      visitorGreeting: "Alice is offline — I'll pass your message along when she's back.",
                                                                      createdAt: Date().addingTimeInterval(-86400 * 14))
                                               ])

    static let emptyProfile = UserProfileView(mxid: "@charlie:spiral.md",
                                              displayName: "Charlie",
                                              publicAgents: [])

    // Held here: the screen's context does not keep its view model alive, and the snapshot waits on it.
    static let loadingViewModel = makeViewModel(state: .loading)
    static let loadedViewModel = makeViewModel(state: .loaded(sampleProfile))
    static let emptyViewModel = makeViewModel(state: .loaded(emptyProfile))
    static let notFoundViewModel = makeViewModel(state: .notFound)
    static let selfLookupViewModel = makeViewModel(state: .selfLookup)
    static let failedViewModel = makeViewModel(state: .failed(reason: "transport error"))

    static var previews: some View {
        ElementNavigationStack { screen(loadingViewModel, waitsForLoading: true) }
            .environment(\.spiralPreloaderDelay, .zero)
            .previewDisplayName("Loading")

        ElementNavigationStack { screen(loadedViewModel) }
            .previewDisplayName("Loaded")

        ElementNavigationStack { screen(emptyViewModel) }
            .previewDisplayName("Loaded — no public agents")

        ElementNavigationStack { screen(notFoundViewModel) }
            .previewDisplayName("Not found")

        ElementNavigationStack { screen(selfLookupViewModel) }
            .previewDisplayName("Self lookup")

        ElementNavigationStack { screen(failedViewModel) }
            .previewDisplayName("Failed")
    }

    /// The snapshot waits for the store's read, except while loading.
    static func screen(_ viewModel: PublicProfileScreenViewModel, waitsForLoading: Bool = false) -> some View {
        PublicProfileScreen(context: viewModel.context)
            .snapshotPreferences(expect: viewModel.context.observe(\.viewState.detailState).map {
                if case .loading = $0 { waitsForLoading } else { !waitsForLoading }
            })
    }

    /// The store reads what `state` names.
    static func makeViewModel(state: PublicProfileState) -> PublicProfileScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.fetchUserProfileMxidClosure = { _ in
            switch state {
            case .loaded(let profile):
                return .success(profile)
            case .notFound:
                return .failure(.notFound)
            case .failed:
                return .failure(.serverError(status: 500))
            case .loading, .selfLookup:
                try? await Task.sleep(for: .seconds(60))
                return .failure(.serverError(status: 0))
            }
        }
        return PublicProfileScreenViewModel(targetMXID: "@alice:spiral.md",
                                            currentUserMXID: state == .selfLookup ? "@alice:spiral.md" : "@viewer:spiral.md",
                                            store: AgentsStore(service: service))
    }
}
