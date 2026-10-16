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
import SwiftUI

struct PublicProfileScreen: View {
    @Bindable var context: PublicProfileScreenViewModel.Context

    var body: some View {
        Form {
            switch context.viewState.detailState {
            case .loading:
                skeletonSection
            case .loaded(let profile):
                headerSection(profile: profile)
                if profile.publicAgents.isEmpty {
                    emptyAgentsSection
                } else {
                    agentsSection(profile.publicAgents)
                }
            case .notFound:
                notFoundSection
            case .selfLookup:
                selfLookupSection
            case .failed(let reason):
                failedSection(reason: reason)
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenPublicProfileTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .refreshable { context.send(viewAction: .refresh) }
        .onAppear { context.send(viewAction: .appeared) }
    }

    // MARK: - Sections

    // Canon §3 (operator ruling, CODEBASE/14): fast/rare data → a delayed
    // spinner, never a skeleton (it only flickers).
    private var skeletonSection: some View {
        Section {
            ListRow(kind: .custom {
                DelayedProgressView()
                    .frame(minHeight: 80)
            })
        }
        .listRowBackground(Color.clear)
    }

    // Canon F7 (variant A): a real avatar header — the member-details
    // anatomy with an initial-avatar (no avatar URL on the wire yet;
    // `LoadableAvatarImage` renders the canonical initial fallback).
    private func headerSection(profile: UserProfileView) -> some View {
        Section {
            VStack(spacing: 8) {
                LoadableAvatarImage(url: nil,
                                    name: profile.displayName,
                                    contentID: profile.mxid,
                                    avatarSize: .user(on: .memberDetails),
                                    mediaProvider: context.mediaProvider)
                VStack(spacing: 4) {
                    Text(profile.displayName)
                        .font(.compound.headingMDBold)
                        .foregroundStyle(.compound.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(profile.mxid)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private var emptyAgentsSection: some View {
        Section {
            VStack(spacing: 16) {
                Text(UntranslatedL10n.screenPublicProfileEmptyTitle)
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                Text(UntranslatedL10n.screenPublicProfileEmptySubtitle)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private func agentsSection(_ agents: [PublicAgentSummary]) -> some View {
        Section {
            ForEach(agents) { agent in
                agentRow(agent)
            }
        } header: {
            Text(UntranslatedL10n.screenPublicProfileAgentsSectionTitle)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenPublicProfileAgentsSectionFooter)
                .compoundListSectionFooter()
        }
    }

    private func agentRow(_ agent: PublicAgentSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(agent.displayName ?? Self.fallbackName(for: agent.matrixUserID))
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textPrimary)
                Text(agent.matrixUserID)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }

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

            Button {
                context.send(viewAction: .contactAgent(matrixUserID: agent.matrixUserID))
            } label: {
                Label(UntranslatedL10n.screenPublicProfileActionContactAgent,
                      icon: \.send)
            }
            .buttonStyle(.compound(.primary, size: .medium))
            .accessibilityLabel(UntranslatedL10n.a11yScreenPublicProfileActionContactAgent(agent.matrixUserID))
        }
        .padding(.vertical, 8)
    }

    private var notFoundSection: some View {
        Section {
            VStack(spacing: 16) {
                BigIcon(icon: \.userProfile, style: .alertSolid)
                Text(UntranslatedL10n.screenPublicProfileNotFoundTitle)
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                Text(UntranslatedL10n.screenPublicProfileNotFoundSubtitle(context.viewState.targetMXID))
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .listRowBackground(Color.clear)
        }
    }

    private var selfLookupSection: some View {
        Section {
            VStack(spacing: 16) {
                BigIcon(icon: \.userProfile)
                Text(UntranslatedL10n.screenPublicProfileSelfTitle)
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                Text(UntranslatedL10n.screenPublicProfileSelfSubtitle)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .listRowBackground(Color.clear)
        }
    }

    private func failedSection(reason: String) -> some View {
        AgentSpacesRetryErrorSection {
            context.send(viewAction: .refresh)
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

struct PublicProfileScreen_Previews: PreviewProvider, TestablePreview {
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

    static var previews: some View {
        ElementNavigationStack { screen(state: .loading) }
            .previewDisplayName("Loading")

        ElementNavigationStack { screen(state: .loaded(sampleProfile)) }
            .previewDisplayName("Loaded")

        ElementNavigationStack { screen(state: .loaded(emptyProfile)) }
            .previewDisplayName("Loaded — no public agents")

        ElementNavigationStack { screen(state: .notFound) }
            .previewDisplayName("Not found")

        ElementNavigationStack { screen(state: .selfLookup) }
            .previewDisplayName("Self lookup")

        ElementNavigationStack { screen(state: .failed(reason: "transport error")) }
            .previewDisplayName("Failed")
    }

    static func screen(state: PublicProfileState) -> some View {
        let service = AgentPlatformServiceMock()
        // Block the live fetch so .onAppear can't overwrite the
        // preview's seeded state with a real result.
        service.fetchUserProfileMxidClosure = { _ in
            try? await Task.sleep(for: .seconds(60))
            return .failure(.serverError(status: 0))
        }
        let viewModel = PublicProfileScreenViewModel(targetMXID: "@alice:spiral.md",
                                                     currentUserMXID: "@viewer:spiral.md",
                                                     agentPlatformService: service,
                                                     initialState: state)
        return PublicProfileScreen(context: viewModel.context)
    }
}
