//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

// AGENT-PLATFORM (Brief 0083, question 387): the call's "Assistants" sheet (D2), at half height over the call (D4).
// Brief 0085 (question 403): your assistant is four round buttons — Translation · Notes · Recording · Talk — and with
// none in the call, one tap on a button brings it for that job.
//
// L5 (the operator's pick C1): the sheet is a continuation of the call screen. Same structure and detents — half height,
// pulled to full by the person, a pushed page keeps the height — in the call's own glass: Liquid Glass through the
// system's sheet from iOS 26, the regular material before it, as the dock falls back. Every page has the call's header
// (avatar, title, one status line, glass ✕; a glass ‹ when pushed). Someone else's assistants are one row at the
// bottom, "In the call · N more", leading to their list and their read-only pages: the old tabs are gone.
//
// Loading (operator, 2026-11-10): every slot has its final size from the first frame. Until the platform first answers
// the header, the buttons and a row stand as placeholders; while a join check is out, the slot it decides holds a
// placeholder; nothing shows a state that flips a moment later.
//
// Everything said about an agent comes from `NativeCallAgentPresentation` (`context.viewState.agents`); the sheet never
// reads the REST snapshot or the raw claims.

enum NativeCallAssistantsRoute: Hashable {
    /// Scenario 9.3 (L5 3.3): which own assistant comes, for this job.
    case chooser(NativeCallAssistantJob)
    /// Scenario 8.2 (L5 5.1): the language of the person next to you, for the pocket interpreter.
    case neighbourLanguage
    /// L1 (L5 2.3): the language you hear the call in, which your assistant translates into; in the private call, the
    /// pocket interpreter's own side (S1).
    case myLanguage
    /// Question 409: the same language as «Я говорю», from the capsule's «Змінити» or the 文A menu while someone's
    /// assistant translates you; a pick closes the sheet, and the capsule confirms it.
    case spokenLanguage
    /// L5 4.2: everyone else's assistants.
    case inTheCall
    /// L5 4.3: someone else's assistant, read-only.
    case foreign(mxid: String)
}

/// What the sheet's root shows, from the platform's answers (question 401, remarks 2, 5).
struct NativeCallAssistantsLayout: Equatable {
    enum Content: Equatable {
        /// The platform has not answered yet: placeholders at the final size, no verdicts (audit A6-2).
        case placeholders
        /// The platform never answered: the unavailable notice alone.
        case nothing
        case ready
    }

    let content: Content
    let showsUnavailableCard: Bool

    init(panel: NativeCallAgentPresentation.Panel) {
        let isGloballyUnavailable = if case .unavailable = panel.lastError, panel.lastErrorScope == .global { true } else { false }
        guard panel.isAvailable else {
            // A read about to start is a read in flight; only an answered failure is "unavailable".
            let hasFailed = !panel.isLoading && panel.lastError != nil
            content = hasFailed ? .nothing : .placeholders
            showsUnavailableCard = hasFailed
            return
        }
        content = .ready
        showsUnavailableCard = isGloballyUnavailable
    }
}

struct NativeCallAgentCenterSheet: View {
    // The sheet is its own presentation root: without `@ObservedObject` the Combine context never invalidates it.
    @ObservedObject var context: NativeCallScreenViewModel.Context

    @State private var path: [NativeCallAssistantsRoute] = []
    @State private var detent = PresentationDetent.nativeCallAssistants
    @State private var isConsentExplainerPresented = false

    private var agents: NativeCallAgentPresentation {
        context.viewState.agents
    }

    var body: some View {
        // swiftlint:disable:next prefer_element_navigation_stack - pushes go by path: a session's pages close when it ends
        NavigationStack(path: $path) {
            NativeCallOwnAssistantPage(context: context, path: $path) { isConsentExplainerPresented = true }
                .navigationDestination(for: NativeCallAssistantsRoute.self, destination: destination)
                .navigationDestination(item: $context.agentLimitPage) { page in
                    // L5 2.4: the limit page in the call's glass, as every page of this sheet.
                    AgentUsageScreen(context: page.viewModel.context,
                                     presentation: .callSheet(onBack: { context.agentLimitPage = nil }, onClose: close))
                }
        }
        // Remarks 6 and 14, L8: the height is the person's — the root's own height by default, measured once per text
        // size and never taller than half, full when they drag it up — and neither a pushed page nor a change of
        // content moves it.
        .presentationDetents([.nativeCallAssistants, .large], selection: $detent)
        .modifier(NativeCallSheetGlassBackground())
        // A page asked for from outside the sheet: "In the call" from the pill; scenarios 9.3 and 8.2 from the 文A menu
        // or the capsule.
        .onChange(of: context.agentCenterPage, initial: true) { _, page in
            guard let page else { return }
            if path.last != page { path = [page] }
            context.agentCenterPage = nil
        }
        .onChange(of: context.assistantPickerJob, initial: true) { _, job in
            if let job, path.last != .chooser(job) { path = [.chooser(job)] }
        }
        .onChange(of: context.isNeighbourLanguagePresented, initial: true) { _, isPresented in
            if isPresented, path.last != .neighbourLanguage { path = [.neighbourLanguage] }
        }
        .onChange(of: path) { _, path in
            if !path.contains(where: { if case .chooser = $0 { true } else { false } }) { context.assistantPickerJob = nil }
            if !path.contains(.neighbourLanguage) { context.isNeighbourLanguagePresented = false }
            // A question asked on one page doesn't follow to the next.
            context.assistantConfirmation = nil
        }
        .sheet(item: $context.aiConsentPrompt) { prompt in
            AIConsentPromptScreen(context: prompt.viewModel.context)
        }
        .alert(UntranslatedL10n.screenNativeCallAssistantsReasonConsentRoom, isPresented: $isConsentExplainerPresented) {
            Button(L10n.actionOk) { }
        } message: {
            Text(UntranslatedL10n.screenNativeCallAssistantsConsentRoomExplainer)
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func destination(_ route: NativeCallAssistantsRoute) -> some View {
        switch route {
        case .chooser(let job):
            NativeCallAssistantChooserPage(context: context, job: job, onBack: back)
        case .neighbourLanguage:
            NativeCallLanguagePage(title: UntranslatedL10n.screenNativeCallAssistantsNeighbourLanguage,
                                   status: UntranslatedL10n.screenNativeCallAssistantsPocketDetail,
                                   free: [],
                                   languages: NativeCallLanguagePage.neighbourLanguages(catalog: agents.panel.catalog,
                                                                                        neighbour: context.viewState.neighbourLanguage,
                                                                                        myLanguage: context.viewState.myLanguage),
                                   suggested: NativeCallLanguagePage.suggested(selected: context.viewState.neighbourLanguage,
                                                                               catalog: agents.panel.catalog,
                                                                               excluding: [context.viewState.myLanguage],
                                                                               preferred: SuggestedLanguages.phoneLanguages,
                                                                               keyboards: SuggestedLanguages.keyboardLanguages),
                                   selected: context.viewState.neighbourLanguage.flatMap { $0 == context.viewState.myLanguage ? nil : $0 },
                                   phoneLanguage: nil,
                                   isLoading: agents.panel.catalog.isEmpty,
                                   onBack: back,
                                   onClose: close) { language in
                context.send(viewAction: .setNeighbourLanguage(language))
                back()
            }
        case .myLanguage:
            myLanguagePage
        case .spokenLanguage:
            spokenLanguagePage
        case .inTheCall:
            NativeCallInTheCallPage(context: context, onBack: back) { path.append(.foreign(mxid: $0)) }
        case .foreign(let mxid):
            if let agent = agents.agents.first(where: { $0.mxid == mxid }) {
                NativeCallForeignAgentPage(agent: agent, context: context, onBack: back)
            }
        }
    }

    /// L5 2.3: the languages someone already translates into (free) first, then all of them, yours ticked. Named as the
    /// row that opens it: «Перевод на» between people, «Я говорю» in the private call (S1).
    private var myLanguagePage: some View {
        let translation = context.viewState.translation
        let free = translation.options.filter { !$0.producers.isEmpty }
        let isPrivateCall = context.viewState.isAssistantPage
        return NativeCallLanguagePage(title: isPrivateCall ? UntranslatedL10n.screenNativeCallAssistantsISpeak : UntranslatedL10n.screenNativeCallAssistantsTranslateInto,
                                      status: isPrivateCall ? UntranslatedL10n.screenNativeCallAssistantsISpeakDetail : UntranslatedL10n.screenNativeCallAssistantsTranslateIntoDetail,
                                      free: free.map { option in
                                          (option.language, option.producerOwners.first.map { NativeCallTranslationCopy.firstName($0, context: context) })
                                      },
                                      languages: NativeCallLanguagePage.languages(catalog: agents.panel.catalog,
                                                                                  first: [context.viewState.myLanguage, context.viewState.phoneLanguage].compactMap(\.self),
                                                                                  excluding: free.map(\.language)),
                                      suggested: NativeCallLanguagePage.suggested(selected: context.viewState.myLanguage,
                                                                                  catalog: agents.panel.catalog,
                                                                                  excluding: free.map(\.language),
                                                                                  preferred: SuggestedLanguages.phoneLanguages,
                                                                                  keyboards: SuggestedLanguages.keyboardLanguages),
                                      // A language picked while your translation runs is ticked until «Translate into …».
                                      selected: context.viewState.pickedTranslationLanguage ?? context.viewState.myLanguage,
                                      phoneLanguage: context.viewState.phoneLanguage,
                                      // The catalog is every list's only source (ADR-0094 A.8): placeholders until it is read.
                                      isLoading: NativeCallAssistantsLayout(panel: agents.panel).content == .placeholders || agents.panel.catalog.isEmpty,
                                      onBack: back,
                                      onClose: close) { language in
            context.send(viewAction: .pickTranslationLanguage(language))
            back()
        }
    }

    /// Question 409: the list «Моя мова» is picked in, named as the language you speak; no free section, as what others
    /// translate into says nothing about your voice.
    private var spokenLanguagePage: some View {
        NativeCallLanguagePage(title: UntranslatedL10n.screenNativeCallAssistantsISpeak,
                               status: UntranslatedL10n.screenNativeCallAssistantsISpeakDetail,
                               free: [],
                               languages: NativeCallLanguagePage.languages(catalog: agents.panel.catalog,
                                                                           first: [context.viewState.myLanguage, context.viewState.phoneLanguage].compactMap(\.self)),
                               suggested: NativeCallLanguagePage.suggested(selected: context.viewState.myLanguage,
                                                                           catalog: agents.panel.catalog,
                                                                           preferred: SuggestedLanguages.phoneLanguages,
                                                                           keyboards: SuggestedLanguages.keyboardLanguages),
                               selected: context.viewState.myLanguage,
                               phoneLanguage: context.viewState.phoneLanguage,
                               isLoading: agents.panel.catalog.isEmpty,
                               onBack: back,
                               onClose: close) { language in
            context.send(viewAction: .setMyLanguage(language == context.viewState.phoneLanguage ? nil : language))
            close()
        }
    }

    // MARK: - Helpers

    private func back() {
        if !path.isEmpty { path.removeLast() }
    }

    private func close() {
        context.send(viewAction: .dismissAgentCenter)
    }
}

/// L5: the sheet is the call's glass. From iOS 26 the system's own sheet is Liquid Glass at half height, so it keeps
/// its background; before it, the regular material the dock and the top buttons fall back to.
private struct NativeCallSheetGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content.presentationBackground(.regularMaterial)
        }
    }
}

// MARK: - Previews

struct NativeCallAgentCenterSheet_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        ForEach(NativeCallAssistantsLabState.allCases) { state in
            NativeCallAgentCenterSheet(context: NativeCallAssistantsLabModel.make(state).context)
                .previewDisplayName(state.rawValue)
        }
    }
}
