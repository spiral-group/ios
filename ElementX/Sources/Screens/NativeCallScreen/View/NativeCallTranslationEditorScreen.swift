//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0062 parity, backend ADR-0075): the two-tier
// translation editor, drawn as `12 · Translation` / `13 · Booths` /
// `14 · Language picker` / `15 · Room default` draw it.
//
// SIMPLE tier (`12`) — one decision: "Translate [who] into [language]"
// (one booth). ADVANCED tier (`13`) — the booth list plus the
// interpreting style, one screen deeper behind "Set up booths". The
// simple tier is a PROJECTION of the booth list, never a second code
// path or wire shape; a config that stopped reducing shows as booths and
// never silently collapses back.
//
// The form hydrates from the server EXACTLY ONCE: doorbell reloads
// must not wipe the languages the owner is in the middle of picking.

import Compound
import SwiftUI

struct NativeCallTranslationEditorScreen: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let sessionID: String

    /// One booth row with a STABLE identity.
    ///
    /// The rows were `ForEach(booths.indices, id: \.self)`, which makes the
    /// index the identity: deleting a booth left SwiftUI holding a row whose
    /// index no longer exists, and its next body evaluation subscripted past
    /// the end and trapped. A pushed language picker capturing that index was
    /// the same trap one screen deeper.
    struct BoothRow: Identifiable, Equatable {
        let id = UUID()
        var booth: VoiceTranslationBooth
    }

    // Form state, hydrated once at init from the snapshot.
    @State private var rows: [BoothRow]
    @State private var style: String
    @State private var isEnabled: Bool
    /// Any edit invalidates a previous promotion: the room rule no longer
    /// matches what is on screen.
    @State private var editedSincePromotion = false

    /// Hydrate EXACTLY ONCE, at init: server booths, or the D6 locale seed
    /// when nothing is configured yet. Re-hydrating on snapshot changes
    /// wiped the languages the owner was in the middle of picking (the
    /// exact web-widget defect this guards against); `onAppear` was too
    /// late for the first render.
    init(context: NativeCallScreenViewModel.Context, sessionID: String) {
        self.context = context
        self.sessionID = sessionID
        let agents = context.viewState.agents
        let translation = agents.control(sessionID: sessionID)?.translation
        let catalog = agents.panel.catalog
        let booths = translation?.booths ?? []
        if booths.isEmpty {
            let seed = VoiceTranslationBooths.localeSeed(catalog: catalog)
            _rows = State(initialValue: seed.map { [BoothRow(booth: .init(speakerScope: VoiceSpeakerScope.anyone.rawValue,
                                                                          speakerMembers: [],
                                                                          targetLanguages: [$0]))] } ?? [])
        } else {
            _rows = State(initialValue: booths.map { BoothRow(booth: $0) })
        }
        // Brief 0066 / ADR-0075 D6 (amended): Live is the default at every
        // tier — the wire, both attach paths and now this editor. Only a
        // session the engine runs as Interpreter hydrates Interpreter.
        _style = State(initialValue: translation?.style == "consecutive" ? "consecutive" : NativeCallTranslationStyleDefault.wire)
        // The main switch says what the engine does, not what a fresh
        // editor hopes: OFF until the user flips it (it used to start ON
        // for an unconfigured session — a switch that lied).
        _isEnabled = State(initialValue: translation?.isOn ?? false)
    }

    @Environment(\.dismiss) private var dismiss

    /// The CAS'd override this editor edits — a CONTROL fact, read from
    /// the presentation's control register, never as a live status.
    private var control: NativeCallAgentPresentation.Control? {
        context.viewState.agents.control(sessionID: sessionID)
    }

    private var catalog: [VoiceControlsCatalogLanguage] {
        context.viewState.agents.panel.catalog
    }

    /// Human call participants the member scopes can name, by their
    /// profile names.
    private var participants: [(userID: String, displayName: String)] {
        context.viewState.participants
            .filter { $0.role == .human }
            .map { ($0.userID, context.viewState.memberProfiles[$0.userID]?.displayName ?? NativeCallFallbackName.make(mxid: $0.userID)) }
    }

    /// The wire value the domain and the controller work with.
    private var booths: [VoiceTranslationBooth] {
        rows.map(\.booth)
    }

    private var reducesToSimple: Bool {
        VoiceTranslationBooths.reducesToSimple(booths)
    }

    private var boothsValid: Bool {
        VoiceTranslationBooths.isValid(booths)
    }

    /// Promotion is reported by the controller, which only records it after
    /// the backend accepted the write. Editing since then makes the label
    /// stale, so a local edit takes precedence.
    private var isSavedAsRoomDefault: Bool {
        !editedSincePromotion && control?.isSavedAsRoomDefault == true
    }

    private var busy: Bool {
        context.viewState.isAgentActionInFlight
    }

    var body: some View {
        Form {
            errorSection

            liveTranslationSection

            if isEnabled {
                whoSection

                boothsEntrySection

                if control?.translation.source == "override" {
                    clearOverrideSection
                }
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenNativeCallAgentCenterTranslation)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // `12`: Apply on the trailing edge; the back chevron is Cancel.
            ToolbarItem(placement: .confirmationAction) {
                Button(UntranslatedL10n.screenNativeCallTranslationApplyShort, action: apply)
                    .fontWeight(.semibold)
                    // Nothing to write: a switch left OFF on a session that is
                    // already off is not an Apply.
                    .disabled(busy || (isEnabled ? !boothsValid : control?.translation.isOn != true))
            }
        }
        .disabled(busy)
    }

    // MARK: - Sections

    @ViewBuilder
    private var errorSection: some View {
        if let errorText = context.viewState.agents.panel.lastError?.localizedDescription {
            Section {
                Text(errorText)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textCriticalPrimary)
            }
        }
    }

    /// `12`'s main row: the engine on/off intent with where the running
    /// config comes from as the quiet line.
    private var liveTranslationSection: some View {
        Section {
            ListRow(kind: .custom {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(UntranslatedL10n.screenNativeCallTranslationMaster)
                            .font(.body)
                            .foregroundStyle(.primary)

                        Text(liveTranslationSubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $isEnabled.animation())
                        .labelsHidden()
                        .accessibilityLabel(UntranslatedL10n.screenNativeCallTranslationMaster)
                        .onChange(of: isEnabled) { markEdited() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            })
        }
    }

    /// WHO IS TRANSLATED — the simple sentence as two value rows when the
    /// config reduces, the booth summary when it does not.
    private var whoSection: some View {
        Section {
            if reducesToSimple {
                NativeCallValueRow(title: UntranslatedL10n.screenNativeCallTranslationTranslate,
                                   value: scopeName(booths.first?.scope ?? .anyone)) {
                    NativeCallTranslationWhoScreen(participants: participants,
                                                   scope: booths.first?.scope ?? .anyone,
                                                   members: booths.first?.speakerMembers ?? []) { scope, members in
                        markEdited()
                        updateFirst { $0 = VoiceTranslationBooth(speakerScope: scope.rawValue,
                                                                 speakerMembers: members,
                                                                 targetLanguages: $0.targetLanguages) }
                    }
                }

                NativeCallValueRow(title: UntranslatedL10n.screenNativeCallTranslationInto,
                                   value: languageNames(booths.first?.targetLanguages ?? [])) {
                    NativeCallLanguagePickerScreen(catalog: catalog,
                                                   selected: booths.first?.targetLanguages ?? [],
                                                   allowsMultipleSelection: style == "consecutive") { languages in
                        markEdited()
                        updateFirst { $0 = VoiceTranslationBooth(speakerScope: $0.speakerScope,
                                                                 speakerMembers: $0.speakerMembers,
                                                                 targetLanguages: languages) }
                    }
                }
            } else {
                NativeCallValueRow(title: UntranslatedL10n.screenNativeCallTranslationBooths,
                                   value: UntranslatedL10n.screenNativeCallTranslationBoothsCount(rows.count)) {
                    boothsScreen
                }
            }
        } header: {
            Text(UntranslatedL10n.screenNativeCallTranslationWho)
        } footer: {
            Text(UntranslatedL10n.screenNativeCallTranslationHintDucked)
        }
        .compoundListSectionHeader()
    }

    /// `12`'s accent row into the advanced tier.
    private var boothsEntrySection: some View {
        Section {
            NavigationLink {
                boothsScreen
            } label: {
                ListRow(kind: .custom {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body)
                            .foregroundStyle(.compound.textActionAccent)
                            .frame(width: 24)

                        Text(UntranslatedL10n.screenNativeCallTranslationSetupBooths)
                            .font(.body)
                            .foregroundStyle(.compound.textActionAccent)

                        Spacer()
                    }
                    .contentShape(.rect)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                })
            }
            .buttonStyle(.plain)
        }
    }

    private var clearOverrideSection: some View {
        Section {
            ListRow(label: .action(title: UntranslatedL10n.screenNativeCallTranslationClearOverride,
                                   icon: \.restart),
                    kind: .button {
                        context.send(viewAction: .clearAgentTranslationOverride(sessionID: sessionID))
                    })
        } footer: {
            Text(UntranslatedL10n.screenNativeCallTranslationFootnote)
        }
    }

    private var boothsScreen: NativeCallTranslationBoothsScreen {
        NativeCallTranslationBoothsScreen(context: context,
                                          sessionID: sessionID,
                                          rows: $rows,
                                          style: $style,
                                          catalog: catalog,
                                          participants: participants,
                                          isSavedAsRoomDefault: isSavedAsRoomDefault,
                                          markEdited: markEdited,
                                          apply: apply)
    }

    // MARK: - Actions

    /// One Apply for the whole form (`12`/`13`): the toggle's OFF intent
    /// disables the engine, everything else writes the booth list.
    private func apply() {
        if isEnabled {
            context.send(viewAction: .applyAgentTranslation(sessionID: sessionID,
                                                            params: .init(booths: booths, style: style)))
        } else if control?.translation.isOn == true {
            context.send(viewAction: .disableAgentTranslation(sessionID: sessionID))
        }
        dismiss()
    }

    /// Mutates the simple tier's single booth.
    private func updateFirst(_ mutate: (inout VoiceTranslationBooth) -> Void) {
        guard !rows.isEmpty else {
            var booth = VoiceTranslationBooth(speakerScope: VoiceSpeakerScope.anyone.rawValue,
                                              speakerMembers: [],
                                              targetLanguages: [])
            mutate(&booth)
            rows = [BoothRow(booth: booth)]
            return
        }
        mutate(&rows[0].booth)
    }

    // MARK: - State

    /// Editing invalidates a previous "saved as room standard" — otherwise
    /// the button stayed latched and the new configuration could never be
    /// promoted.
    private func markEdited() {
        editedSincePromotion = true
    }

    // MARK: - Copy

    private var liveTranslationSubtitle: String {
        control?.translation.source == "room_tool"
            ? UntranslatedL10n.screenNativeCallTranslationMasterRoomRule
            : UntranslatedL10n.screenNativeCallTranslationMasterCallOnly
    }

    private func languageNames(_ codes: [String]) -> String {
        NativeCallTranslationCopy.languageNames(codes, catalog: catalog)
    }

    private func scopeName(_ scope: VoiceSpeakerScope) -> String {
        NativeCallTranslationCopy.scopeName(scope)
    }
}

// MARK: - Booths (13)

/// `13 · Booths`: the interpreting style, the booth cards, add, and the
/// room-default promotion. Shares the root editor's form state — Apply is
/// the same Apply.
struct NativeCallTranslationBoothsScreen: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let sessionID: String
    @Binding var rows: [NativeCallTranslationEditorScreen.BoothRow]
    @Binding var style: String
    let catalog: [VoiceControlsCatalogLanguage]
    let participants: [(userID: String, displayName: String)]
    let isSavedAsRoomDefault: Bool
    let markEdited: () -> Void
    let apply: () -> Void

    @State private var isDefaultDialogPresented = false

    private var control: NativeCallAgentPresentation.Control? {
        context.viewState.agents.control(sessionID: sessionID)
    }

    /// ADR-0075 D4 — the orchestrator NARROWED this session's booth because
    /// the covered speaker brought their own agent. The controller detects
    /// it (a coverage shrink that is not ours); the note below says so.
    /// Without this the note rode the booth SHAPE alone, so an
    /// `everyone_except` booth the owner wrote themselves was reported as
    /// somebody else's displacement.
    private var isDisplacedSession: Bool {
        control?.isDisplaced == true
    }

    var body: some View {
        Form {
            styleSection

            boothSections

            addBoothSection

            if control?.translation.isOn == true, control?.canSaveAsRoomDefault == true {
                saveDefaultSection
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenNativeCallTranslationBooths)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(UntranslatedL10n.screenNativeCallTranslationApplyShort, action: apply)
                    .fontWeight(.semibold)
                    .disabled(context.viewState.isAgentActionInFlight || !VoiceTranslationBooths.isValid(rows.map(\.booth)))
            }
        }
        // `15 · Room default`: promotion is a standing rule for every
        // future call — it asks first.
        .alert(UntranslatedL10n.screenNativeCallTranslationDefaultDialogTitle,
               isPresented: $isDefaultDialogPresented) {
            Button(L10n.actionCancel, role: .cancel) { }
            Button(L10n.actionSave) {
                context.send(viewAction: .saveAgentTranslationAsRoomDefault(sessionID: sessionID))
            }
        } message: {
            Text(UntranslatedL10n.screenNativeCallTranslationDefaultDialogBody(context.viewState.roomName))
        }
    }

    /// HOW THE AGENT INTERPRETS — the two styles as radio rows, the
    /// selected one washed in the accent tint (`13`).
    private var styleSection: some View {
        Section {
            NativeCallRadioRow(title: UntranslatedL10n.screenNativeCallTranslationStyleInterpreter,
                               subtitle: UntranslatedL10n.screenNativeCallTranslationStyleInterpreterDetail,
                               detail: UntranslatedL10n.screenNativeCallTranslationStyleInterpreterLangs,
                               showsSelectedWash: true,
                               isSelected: style == "consecutive") {
                markEdited()
                style = "consecutive"
            }

            NativeCallRadioRow(title: UntranslatedL10n.screenNativeCallTranslationStyleLive,
                               subtitle: UntranslatedL10n.screenNativeCallTranslationStyleLiveDetail,
                               detail: UntranslatedL10n.screenNativeCallTranslationStyleLiveLangs,
                               showsSelectedWash: true,
                               isSelected: style == "simultaneous") {
                markEdited()
                style = "simultaneous"
                // Simultaneous is single-language by CONTRACT, not just by
                // what the picker offers: a booth that carried several
                // languages from a consecutive edit would otherwise submit
                // them all, and every listener would hear two lanes over
                // the same ducked voice. Keep the first.
                rows = rows.map { row in
                    var row = row
                    row.booth = VoiceTranslationBooth(speakerScope: row.booth.speakerScope,
                                                      speakerMembers: row.booth.speakerMembers,
                                                      targetLanguages: Array(row.booth.targetLanguages.prefix(1)))
                    return row
                }
            }
        } header: {
            Text(UntranslatedL10n.screenNativeCallTranslationHowSection)
        }
        .compoundListSectionHeader()
    }

    private var boothSections: some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
            boothSection(id: row.id, isFirst: position == 0)
        }
    }

    @ViewBuilder
    private func boothSection(id: NativeCallTranslationEditorScreen.BoothRow.ID, isFirst: Bool) -> some View {
        // Addressed by identity, never by index: a row removed while its
        // language picker is pushed must resolve to nothing, not to whatever
        // booth slid into that slot.
        if let booth = rows.first(where: { $0.id == id })?.booth {
            Section {
                if booth.scope == .everyoneExcept {
                    // Created by displacement narrowing, never by hand: the
                    // Who row is read-only and wears the AUTO badge.
                    ListRow(kind: .custom {
                        HStack(spacing: 8) {
                            Text(UntranslatedL10n.screenNativeCallTranslationWhoRow)
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(UntranslatedL10n.screenNativeCallTranslationEveryoneExcept(memberNames(booth.speakerMembers)))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(UntranslatedL10n.screenNativeCallTranslationAutoBadge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.compound.textActionAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.compound.iconAccentPrimary.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    })
                } else {
                    NativeCallValueRow(title: UntranslatedL10n.screenNativeCallTranslationWhoRow,
                                       value: whoValue(booth)) {
                        NativeCallTranslationWhoScreen(participants: participants,
                                                       scope: booth.scope ?? .anyone,
                                                       members: booth.speakerMembers) { scope, members in
                            markEdited()
                            update(id) { $0 = VoiceTranslationBooth(speakerScope: scope.rawValue,
                                                                    speakerMembers: members,
                                                                    targetLanguages: $0.targetLanguages) }
                        }
                    }
                }

                NativeCallValueRow(title: UntranslatedL10n.screenNativeCallTranslationInto,
                                   value: NativeCallTranslationCopy.languageNames(booth.targetLanguages, catalog: catalog)) {
                    NativeCallLanguagePickerScreen(catalog: catalog,
                                                   selected: booth.targetLanguages,
                                                   allowsMultipleSelection: style == "consecutive") { languages in
                        markEdited()
                        // Read the CURRENT booth, not the one captured when
                        // this row was built — members edited meanwhile would
                        // be lost.
                        update(id) { $0 = VoiceTranslationBooth(speakerScope: $0.speakerScope,
                                                                speakerMembers: $0.speakerMembers,
                                                                targetLanguages: languages) }
                    }
                }

                if isDisplacedSession, booth.scope == .everyoneExcept, let name = booth.speakerMembers.first {
                    // The displaced note (`13`): why the booth narrowed.
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.compound.iconAccentPrimary)

                        Text(UntranslatedL10n.screenNativeCallTranslationDisplacedNote(memberNames([name])))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if !isFirst || rows.count > 1 {
                    ListRow(kind: .custom {
                        Button(role: .destructive) {
                            markEdited()
                            rows.removeAll { $0.id == id }
                        } label: {
                            Text(UntranslatedL10n.screenNativeCallTranslationRemoveBooth)
                                .font(.body)
                                .foregroundStyle(.compound.textCriticalPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    })
                }
            }
            .listSectionSpacing(10)
        }
    }

    private var addBoothSection: some View {
        Section {
            ListRow(kind: .custom {
                Button {
                    markEdited()
                    // A fresh rule most often names people — start there
                    // rather than with another everyone-booth that would
                    // just conflict.
                    let scope: VoiceSpeakerScope = rows.isEmpty ? .anyone : .specificSenders
                    let seed = VoiceTranslationBooths.localeSeed(catalog: catalog)
                    rows.append(.init(booth: .init(speakerScope: scope.rawValue,
                                                   speakerMembers: [],
                                                   targetLanguages: seed.map { [$0] } ?? [])))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                            .foregroundStyle(.compound.iconAccentPrimary)
                            .frame(width: 24)

                        Text(UntranslatedL10n.screenNativeCallTranslationAddBooth)
                            .font(.body)
                            .foregroundStyle(.compound.textActionAccent)

                        Spacer()
                    }
                    .contentShape(.rect)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            })
        }
        .listSectionSpacing(10)
    }

    private var saveDefaultSection: some View {
        Section {
            ListRow(label: .default(title: isSavedAsRoomDefault
                        ? UntranslatedL10n.screenNativeCallTranslationSavedDefault
                        : UntranslatedL10n.screenNativeCallTranslationSaveDefault,
                systemIcon: .pin),
            kind: .navigationLink {
                isDefaultDialogPresented = true
            })
            .disabled(isSavedAsRoomDefault)
        }
        .listSectionSpacing(14)
    }

    private func update(_ id: NativeCallTranslationEditorScreen.BoothRow.ID, _ mutate: (inout VoiceTranslationBooth) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        mutate(&rows[index].booth)
    }

    private func whoValue(_ booth: VoiceTranslationBooth) -> String {
        booth.scope == .specificSenders
            ? memberNames(booth.speakerMembers)
            : NativeCallTranslationCopy.scopeName(booth.scope ?? .anyone)
    }

    private func memberNames(_ members: [String]) -> String {
        guard !members.isEmpty else { return NativeCallTranslationCopy.scopeName(.specificSenders) }
        return members
            .map { mxid in participants.first { $0.userID == mxid }?.displayName ?? mxid }
            .joined(separator: ", ")
    }
}

// MARK: - Who (13's Who row)

/// The booth's speaker scope: a radio list, with the member checklist
/// unfolding under "Specific people".
struct NativeCallTranslationWhoScreen: View {
    let participants: [(userID: String, displayName: String)]
    @State var scope: VoiceSpeakerScope
    @State var members: [String]
    let onChange: (VoiceSpeakerScope, [String]) -> Void

    var body: some View {
        Form {
            Section {
                ForEach(VoiceSpeakerScope.editable, id: \.rawValue) { option in
                    NativeCallRadioRow(title: NativeCallTranslationCopy.scopeName(option),
                                       isSelected: scope == option) {
                        scope = option
                        onChange(scope, scope == .specificSenders ? members : [])
                    }
                }
            }

            if scope == .specificSenders {
                Section {
                    if participants.isEmpty {
                        Text(UntranslatedL10n.screenNativeCallTranslationNoParticipants)
                            .font(.compound.bodySM)
                            .foregroundStyle(.compound.textSecondary)
                    } else {
                        ForEach(participants, id: \.userID) { participant in
                            let isMember = members.contains(participant.userID)
                            ListRow(label: .plain(title: participant.displayName),
                                    kind: .selection(isSelected: isMember) {
                                        if isMember {
                                            members.removeAll { $0 == participant.userID }
                                        } else {
                                            members.append(participant.userID)
                                            members.sort()
                                        }
                                        onChange(scope, members)
                                    })
                        }
                    }
                }
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenNativeCallTranslationWhoRow)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Language picker (14)

/// A searchable language list (the tenant catalog is ~80 entries —
/// the same reason the web picker got its own scroll + search).
struct NativeCallLanguagePickerScreen: View {
    let catalog: [VoiceControlsCatalogLanguage]
    @State var selected: [String]
    let allowsMultipleSelection: Bool
    let onChange: ([String]) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var visible: [VoiceControlsCatalogLanguage] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return catalog }
        return catalog.filter {
            $0.label.lowercased().contains(trimmed) || $0.code.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(visible, id: \.code) { language in
                    let isSelected = selected.contains(language.code)
                    ListRow(label: .plain(title: language.label),
                            kind: .selection(isSelected: isSelected) {
                                if allowsMultipleSelection {
                                    // Picking several languages must not cost
                                    // a reopen per language — stay on screen.
                                    if isSelected {
                                        selected.removeAll { $0 == language.code }
                                    } else {
                                        selected.append(language.code)
                                    }
                                    onChange(selected)
                                } else {
                                    selected = [language.code]
                                    onChange(selected)
                                    dismiss()
                                }
                            })
                }
            } footer: {
                // `14`'s mode line: what a pick means in this style.
                Text(allowsMultipleSelection
                    ? UntranslatedL10n.screenNativeCallTranslationModeMulti
                    : UntranslatedL10n.screenNativeCallTranslationModeSingle)
            }
        }
        .compoundList()
        .searchable(text: $query, prompt: UntranslatedL10n.screenNativeCallTranslationSearchLanguages)
        .navigationTitle(UntranslatedL10n.screenNativeCallTranslationLanguageTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Value row

/// `12`/`13`'s label → value → chevron row, pushing its editor.
struct NativeCallValueRow<Destination: View>: View {
    let title: String
    let value: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            ListRow(kind: .custom {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(value)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(.rect)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            })
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared copy

/// One vocabulary for scopes and language lists — `12`, `13` and the who
/// screen must never disagree on a word.
enum NativeCallTranslationCopy {
    static func scopeName(_ scope: VoiceSpeakerScope) -> String {
        switch scope {
        case .anyone: UntranslatedL10n.screenNativeCallTranslationScopeEveryone
        case .nonSelfNonOwner: UntranslatedL10n.screenNativeCallTranslationScopeEveryoneExceptMe
        case .ownerOnly: UntranslatedL10n.screenNativeCallTranslationScopeOnlyMe
        case .specificSenders: UntranslatedL10n.screenNativeCallTranslationScopeSpecific
        case .everyoneExcept: UntranslatedL10n.screenNativeCallTranslationScopeEveryone
        }
    }

    static func languageNames(_ codes: [String], catalog: [VoiceControlsCatalogLanguage]) -> String {
        guard !codes.isEmpty else { return UntranslatedL10n.screenNativeCallTranslationChooseLanguage }
        return NativeCallAgentStatusCopy.languageList(codes, catalog: catalog)
    }
}

// MARK: - Previews

struct NativeCallTranslationEditorScreen_Previews: PreviewProvider, TestablePreview {
    static let simpleViewModel = makeViewModel(booths: [.init(speakerScope: VoiceSpeakerScope.anyone.rawValue,
                                                              speakerMembers: [],
                                                              targetLanguages: ["uk"])])

    static var previews: some View {
        ElementNavigationStack {
            NativeCallTranslationEditorScreen(context: simpleViewModel.context, sessionID: "session-1")
        }
        .previewDisplayName("Simple sentence")

        ElementNavigationStack {
            NativeCallTranslationBoothsPreviewHost(viewModel: makeViewModel(booths: []))
        }
        .previewDisplayName("Booths")

        // ADR-0088: the server offers keeping the translation as the room's rule
        // in group calls only.
        ElementNavigationStack {
            NativeCallTranslationBoothsPreviewHost(viewModel: makeViewModel(booths: liveBooths, scope: .group, canSaveAsRoomDefault: true),
                                                   rows: liveBooths.map { .init(booth: $0) })
        }
        .previewDisplayName("Booths in a group call")

        ElementNavigationStack {
            NativeCallTranslationBoothsPreviewHost(viewModel: makeViewModel(booths: liveBooths, scope: .direct, canSaveAsRoomDefault: false),
                                                   rows: liveBooths.map { .init(booth: $0) })
        }
        .previewDisplayName("Booths in a direct call")

        ElementNavigationStack {
            NativeCallLanguagePickerScreen(catalog: catalog, selected: ["uk"], allowsMultipleSelection: false) { _ in }
        }
        .previewDisplayName("Language picker")
    }

    static let catalog: [VoiceControlsCatalogLanguage] = [.init(code: "uk", label: "Ukrainian"),
                                                          .init(code: "en", label: "English"),
                                                          .init(code: "de", label: "German"),
                                                          .init(code: "pl", label: "Polish"),
                                                          .init(code: "es", label: "Spanish"),
                                                          .init(code: "fr", label: "French"),
                                                          .init(code: "it", label: "Italian")]

    static let liveBooths = [VoiceTranslationBooth(speakerScope: VoiceSpeakerScope.anyone.rawValue,
                                                   speakerMembers: [],
                                                   targetLanguages: ["uk"])]

    static func makeViewModel(booths: [VoiceTranslationBooth],
                              scope: NativeCallScope = .direct,
                              canSaveAsRoomDefault: Bool = false) -> NativeCallScreenViewModel {
        let viewModel = NativeCallAgentCenterSheet_Previews.makeViewModel(sessions: [session(booths: booths, canSaveAsRoomDefault: canSaveAsRoomDefault)],
                                                                          candidates: [])
        viewModel.state.scope = scope
        viewModel.state.participants = [NativeCallScreen_Previews.participant("@marta:spiral.md"),
                                        NativeCallScreen_Previews.participant("@yurii:spiral.md")]
        viewModel.state.memberProfiles = ["@marta:spiral.md": .init(displayName: "Marta Illienko"),
                                          "@yurii:spiral.md": .init(displayName: "Yurii Tkach")]
        return viewModel
    }

    static func session(booths: [VoiceTranslationBooth], canSaveAsRoomDefault: Bool = false) -> NativeAgentCenterSession {
        NativeAgentCenterSession(sessionID: "session-1",
                                 agentMxid: "@assistant-alice:spiral.md",
                                 canControl: true,
                                 isEnding: false,
                                 recording: .init(isEnabled: false, revision: 1, delivery: .notArmed, isStopped: false),
                                 summary: .init(isEnabled: false, revision: 1, delivery: .notArmed, isStopped: false),
                                 translation: .init(booths: booths,
                                                    style: "consecutive",
                                                    source: booths.isEmpty ? "off" : "override",
                                                    revision: 2),
                                 conversation: .unknown,
                                 canSaveAsRoomDefault: canSaveAsRoomDefault)
    }
}

/// `13 · Booths` needs bindings — a tiny host owns the form state the
/// pushed screen would normally share with the root editor.
private struct NativeCallTranslationBoothsPreviewHost: View {
    let viewModel: NativeCallScreenViewModel

    @State private var rows: [NativeCallTranslationEditorScreen.BoothRow]
    @State private var style = "consecutive"

    /// One booth keeps the room-default row on screen.
    init(viewModel: NativeCallScreenViewModel,
         rows: [NativeCallTranslationEditorScreen.BoothRow] = [
             .init(booth: .init(speakerScope: VoiceSpeakerScope.nonSelfNonOwner.rawValue,
                                speakerMembers: [],
                                targetLanguages: ["uk"])),
             .init(booth: .init(speakerScope: VoiceSpeakerScope.specificSenders.rawValue,
                                speakerMembers: ["@marta:spiral.md", "@yurii:spiral.md"],
                                targetLanguages: ["en", "de"])),
             .init(booth: .init(speakerScope: VoiceSpeakerScope.everyoneExcept.rawValue,
                                speakerMembers: ["@marta:spiral.md"],
                                targetLanguages: ["uk"]))
         ]) {
        self.viewModel = viewModel
        _rows = State(initialValue: rows)
    }

    var body: some View {
        NativeCallTranslationBoothsScreen(context: viewModel.context,
                                          sessionID: "session-1",
                                          rows: $rows,
                                          style: $style,
                                          catalog: NativeCallTranslationEditorScreen_Previews.catalog,
                                          participants: [("@marta:spiral.md", "Marta Illienko"),
                                                         ("@yurii:spiral.md", "Yurii Tkach")],
                                          isSavedAsRoomDefault: false,
                                          markEdited: { },
                                          apply: { })
    }
}
