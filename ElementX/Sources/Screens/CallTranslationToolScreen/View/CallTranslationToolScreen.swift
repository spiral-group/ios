//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, question 403, model point 9, scenario 5.1; backend ADR-0094 D9, A.5, Appendix C row
// 14): the chat's personal tool "Call translation" — in calls here I listen in a language; if nobody translates, my
// assistant does. "If nobody translates" on arms the personal `live_translate` Tool with the language shown; off removes
// it, and only this device keeps the listening language. Every change is stored at once, as a chat tool's switch is.

import Compound
import SpiralTokens
import SwiftUI

struct CallTranslationToolScreen: View {
    @Bindable var context: CallTranslationToolScreenViewModelType.Context

    private var tool: NativeCallTranslationTool {
        context.viewState.tool
    }

    private var isInteractive: Bool {
        !context.viewState.isLoading && !context.viewState.isLoadFailed
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: CompoundDesignTokens.space3X) {
                    Image(systemName: "translate")
                        .font(.compound.headingLG)
                        .foregroundStyle(Color.compound.iconOnSolidPrimary)
                        .frame(width: 56, height: 56)
                        .background(Color.compound.bgAccentRest, in: RoundedRectangle(cornerRadius: SpiralRadius.block, style: .continuous))
                        .accessibilityHidden(true)
                    Text(tool.isEnabled
                        ? UntranslatedL10n.screenNativeCallTranslationToolSummary(NativeCallTranslationCopy.languageName(tool.language))
                        : UntranslatedL10n.screenNativeCallTranslationToolSummaryOff)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .multilineTextAlignment(.center)
                        .spiralLoadingSlot(context.viewState.isLoading, label: L10n.commonLoading)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenNativeCallTranslationToolEnabled),
                        details: .isWaiting(context.viewState.isSaving),
                        kind: .toggle(Binding(get: { tool.isEnabled },
                                              set: { context.send(viewAction: .setEnabled($0)) })))
                    .disabled(!isInteractive)
                // The language is always concrete and named, never a hidden "follow my language" (row 14).
                ListRow(label: .plain(title: UntranslatedL10n.screenNativeCallTranslationToolLanguage),
                        details: .title(NativeCallTranslationCopy.languageTitle(tool.language)),
                        kind: .navigationLink {
                            context.isLanguagePresented = true
                        })
                    .disabled(!isInteractive || !tool.isEnabled || context.viewState.catalog.isEmpty)
                ListRow(label: .plain(title: UntranslatedL10n.screenNativeCallTranslationToolFallback,
                                      description: UntranslatedL10n.screenNativeCallTranslationToolFallbackDetail),
                        kind: .toggle(Binding(get: { tool.translatesIfNobodyDoes },
                                              set: { context.send(viewAction: .setTranslatesIfNobodyDoes($0)) })))
                    .disabled(!isInteractive || !tool.isEnabled)
            } footer: {
                Text(footer)
                    .compoundListSectionFooter()
            }
            .spiralLoadingSlot(context.viewState.isLoading, label: L10n.commonLoading)

            if context.viewState.isLoadFailed {
                Section {
                    ListRow(label: .action(title: L10n.actionRetry, icon: \.restart),
                            kind: .button { context.send(viewAction: .retry) })
                }
            }
        }
        .spiralGroupedList()
        .navigationTitle(UntranslatedL10n.screenNativeCallTranslationToolTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let agent = context.viewState.agentDisplayName {
                ToolbarItem(placement: .principal) {
                    ToolScreenTitle(title: UntranslatedL10n.screenNativeCallTranslationToolTitle, subtitle: agent)
                }
            }
        }
        .navigationDestination(isPresented: $context.isLanguagePresented) {
            CallTranslationLanguageList(title: UntranslatedL10n.screenNativeCallTranslationToolLanguage,
                                        languages: CallTranslationLanguageList.languages(catalog: context.viewState.catalog),
                                        selected: tool.language == context.viewState.myLanguage ? nil : tool.language,
                                        defaultLanguage: context.viewState.myLanguage,
                                        defaultTitle: UntranslatedL10n.screenNativeCallTranslateMyLanguage) { picked in
                context.send(viewAction: .setLanguage(picked))
            }
        }
    }

    private var footer: String {
        if context.viewState.isLoadFailed { return UntranslatedL10n.screenNativeCallAssistantsUnavailable }
        if context.viewState.isSaveFailed { return UntranslatedL10n.screenNativeCallTranslationToolNotSaved }
        // One honest line: what it does for you, and that the chat sees it.
        return UntranslatedL10n.screenNativeCallTranslationToolFooterShared
    }
}

// MARK: - Previews

struct CallTranslationToolScreen_Previews: PreviewProvider, TestablePreview {
    static let offViewModel = makeViewModel(tool: nil)
    static let onViewModel = makeViewModel(tool: .init(isEnabled: true, language: "uk", translatesIfNobodyDoes: true, toolID: "t1", agentID: "a1"))
    static let listenOnlyViewModel = makeViewModel(tool: .init(isEnabled: true, language: "pt-BR"))

    static var previews: some View {
        ElementNavigationStack {
            CallTranslationToolScreen(context: offViewModel.context)
        }
        .previewDisplayName("Off")
        .snapshotPreferences(expect: offViewModel.context.observe(\.viewState.isLoading).map { !$0 })

        ElementNavigationStack {
            CallTranslationToolScreen(context: onViewModel.context)
        }
        .previewDisplayName("On, translates if nobody does")
        .snapshotPreferences(expect: onViewModel.context.observe(\.viewState.isLoading).map { !$0 })

        ElementNavigationStack {
            CallTranslationToolScreen(context: listenOnlyViewModel.context)
        }
        .previewDisplayName("Listen only")
        .snapshotPreferences(expect: listenOnlyViewModel.context.observe(\.viewState.isLoading).map { !$0 })
    }

    private static func makeViewModel(tool: NativeCallTranslationTool?) -> CallTranslationToolScreenViewModel {
        CallTranslationToolScreenViewModel(service: PreviewService(tool: tool),
                                           myLanguageStore: NativeCallMyLanguageStore(defaults: UserDefaults(suiteName: "CallTranslationToolPreview") ?? .standard) { "uk_UA" },
                                           cachedCatalog: PreviewService.catalog,
                                           agentDisplayName: "Alice Sample · assistant")
    }

    private final class PreviewService: CallTranslationToolServiceProtocol {
        static let catalog: [VoiceControlsCatalogLanguage] = [.init(code: "en", label: "English"),
                                                              .init(code: "uk", label: "Ukrainian"),
                                                              .init(code: "pt-BR", label: "Portuguese (Brazil)")]
        var tool: NativeCallTranslationTool?

        init(tool: NativeCallTranslationTool?) {
            self.tool = tool
        }

        func languages() async -> [VoiceControlsCatalogLanguage]? {
            Self.catalog
        }

        func translationTool() async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError> {
            .success(tool)
        }

        func storeTranslationTool(_ tool: NativeCallTranslationTool) async -> Bool {
            self.tool = tool.isEnabled ? tool : nil
            return true
        }
    }
}
