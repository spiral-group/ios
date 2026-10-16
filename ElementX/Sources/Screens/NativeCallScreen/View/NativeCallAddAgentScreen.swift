//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0063): `11 · Add an agent` — the quick
// "Translate me" card and the compose-what-it-does toggles. Attach is one
// write: the agent joins already doing what was picked, or NEUTRAL when
// nothing was (operator decision — a silently-enabled summary was the
// Brief 0064 defect). Decision 180 adds Conversation and a real
// Translation with the Agent Center's language picker.

import Compound
import SwiftUI

struct NativeCallAddAgentScreen: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let candidate: NativeAgentCenterCandidate

    @State private var form: NativeCallAddAgentForm

    @Environment(\.dismiss) private var dismiss

    init(context: NativeCallScreenViewModel.Context, candidate: NativeAgentCenterCandidate) {
        _context = ObservedObject(wrappedValue: context)
        self.candidate = candidate
        _form = State(initialValue: NativeCallAddAgentForm(catalog: context.viewState.agents.panel.catalog))
    }

    /// The agent's catalog — read without a session (decision 180), so it is
    /// there before the first attach. Empty only when the read failed or the
    /// agent offers none; the translation row says so.
    private var catalog: [VoiceControlsCatalogLanguage] {
        context.viewState.agents.panel.catalog
    }

    /// The device-locale language when the catalog offers it — the quick
    /// card speaks it.
    private var seedLanguage: String? {
        VoiceTranslationBooths.localeSeed(catalog: catalog)
    }

    var body: some View {
        Form {
            identitySection

            if let seedLanguage {
                quickSection(seedLanguage)
            }

            pickSection
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenNativeCallAgentCenterAvailableSection)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(UntranslatedL10n.screenNativeCallAddAgentAdd, action: add)
                    .fontWeight(.semibold)
                    .disabled(context.viewState.isAgentActionInFlight || !form.canAdd)
            }
        }
        .disabled(context.viewState.isAgentActionInFlight)
    }

    /// Who you are about to add. The screen used to name nobody at all —
    /// you arrived from a list and configured an agent the screen never
    /// identified. Same avatar and same name the Agent Center shows once
    /// the agent has joined, so the two screens agree.
    private var identitySection: some View {
        Section {
            ListRow(kind: .custom {
                HStack(spacing: 12) {
                    NativeCallLetterAvatar(userID: candidate.mxid,
                                           profile: context.viewState.memberProfiles[candidate.mxid],
                                           fallbackName: candidate.displayName,
                                           size: 40,
                                           mediaProvider: context.mediaProvider,
                                           avatarURL: candidate.avatarURL)

                    Text(candidate.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            })
        }
    }

    /// The blue quick action: one tap, the owner's own voice translated
    /// for everyone else (`owner_only` booth, simultaneous style).
    private func quickSection(_ language: String) -> some View {
        Section {
            // A plain row, not a `ListRow`: `ListRow` hard-sets its own
            // white row background, which buried the design's blue card.
            Button {
                context.send(viewAction: .attachAgentTranslateMe(agentID: candidate.id, language: language))
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.2), in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(UntranslatedL10n.screenNativeCallAddAgentTranslateMe)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(UntranslatedL10n.screenNativeCallAddAgentTranslateMeDetail)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()
                }
                .contentShape(.rect)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.compound.iconAccentPrimary)
        } footer: {
            Text(UntranslatedL10n.screenNativeCallAddAgentNote)
        }
    }

    private var pickSection: some View {
        Section {
            // Decision 180 — the Agent Center's Conversation switch, chosen
            // before the agent joins. The subtitle never truncates there
            // either: "everyone hears it" is the point of the row.
            toggleRow(icon: "bubble.left.and.bubble.right",
                      title: UntranslatedL10n.screenNativeCallAgentCenterConversation,
                      subtitle: UntranslatedL10n.screenNativeCallAgentCenterConversationOn,
                      subtitleLineLimit: nil,
                      isOn: Binding(get: { form.conversation }, set: { form.setConversation($0) }))

            if catalog.isEmpty {
                // No catalog means no language an attach could carry, so no
                // live toggle (audit T2: ON used to attach without translation).
                toggleRow(icon: "globe",
                          title: UntranslatedL10n.screenNativeCallAgentCenterTranslation,
                          subtitle: UntranslatedL10n.screenNativeCallAddAgentTranslationUnavailable,
                          isOn: .constant(false))
                    .disabled(true)
            } else {
                toggleRow(icon: "globe",
                          title: UntranslatedL10n.screenNativeCallAgentCenterTranslation,
                          subtitle: UntranslatedL10n.screenNativeCallAddAgentTranslationDetail(NativeCallTranslationCopy.languageNames(form.languages, catalog: catalog)),
                          isOn: Binding(get: { form.translation }, set: { form.setTranslation($0) }))

                if form.translation {
                    // The Agent Center editor's own picker.
                    NativeCallValueRow(title: UntranslatedL10n.screenNativeCallTranslationInto,
                                       value: NativeCallTranslationCopy.languageNames(form.languages, catalog: catalog)) {
                        NativeCallLanguagePickerScreen(catalog: catalog,
                                                       selected: form.languages,
                                                       allowsMultipleSelection: false) { languages in
                            form.languages = languages
                        }
                    }
                }
            }

            toggleRow(icon: "record.circle",
                      title: UntranslatedL10n.screenNativeCallAddAgentRecord,
                      subtitle: UntranslatedL10n.screenNativeCallAddAgentRecordDetail,
                      isOn: $form.recording)

            toggleRow(icon: "text.alignleft",
                      title: UntranslatedL10n.screenNativeCallAddAgentSummary,
                      subtitle: UntranslatedL10n.screenNativeCallAddAgentSummaryDetail,
                      isOn: $form.summary)
        } header: {
            Text(UntranslatedL10n.screenNativeCallAddAgentPickSection)
        } footer: {
            // Brief 0067: the disclosure the widget's add panel carried —
            // consent is posted, and audio meets an AI model.
            Text(UntranslatedL10n.screenNativeCallAddAgentConsentNote)
                .compoundListSectionFooter()
        }
        .compoundListSectionHeader()
    }

    private func toggleRow(icon: String,
                           title: String,
                           subtitle: String,
                           subtitleLineLimit: Int? = 1,
                           isOn: Binding<Bool>) -> some View {
        ListRow(kind: .custom {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                }

                Spacer()

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .accessibilityLabel(title)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        })
    }

    /// The Add write: everything picked, in one attach.
    private func add() {
        context.send(viewAction: .attachAgentConfigured(agentID: candidate.id, params: form.params))
        dismiss()
    }
}

// MARK: - Previews

struct NativeCallAddAgentScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = NativeCallAgentCenterSheet_Previews.makeViewModel(sessions: [],
                                                                             candidates: [candidate])
    static let candidate = NativeAgentCenterCandidate(id: "agent-1",
                                                      mxid: "@assistant-alice:spiral.md",
                                                      displayName: "Alice's Assistant",
                                                      avatarURL: nil,
                                                      isRoomMember: true)

    static var previews: some View {
        ElementNavigationStack {
            NativeCallAddAgentScreen(context: viewModel.context, candidate: candidate)
        }
        .previewDisplayName("Add an agent")
    }
}
