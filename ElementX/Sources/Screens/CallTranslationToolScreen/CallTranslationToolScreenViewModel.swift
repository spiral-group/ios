//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

typealias CallTranslationToolScreenViewModelType = StateStoreViewModelV2<CallTranslationToolScreenViewState, CallTranslationToolScreenViewAction>

class CallTranslationToolScreenViewModel: CallTranslationToolScreenViewModelType {
    private let service: CallTranslationToolServiceProtocol
    private let myLanguageStore: NativeCallMyLanguageStore
    /// What the last read said is stored; nil when the chat has no tool.
    private var stored: NativeCallTranslationTool?

    init(service: CallTranslationToolServiceProtocol,
         myLanguageStore: NativeCallMyLanguageStore = .standard,
         cachedCatalog: [VoiceControlsCatalogLanguage] = NativeCallLanguageCatalogCache.standard.languages ?? [],
         agentDisplayName: String? = nil) {
        self.service = service
        self.myLanguageStore = myLanguageStore
        let myLanguage = myLanguageStore.resolved(catalog: cachedCatalog.map(\.code)) ?? myLanguageStore.displayLanguage
        super.init(initialViewState: CallTranslationToolScreenViewState(agentDisplayName: agentDisplayName,
                                                                        tool: NativeCallTranslationTool(language: myLanguage),
                                                                        catalog: cachedCatalog,
                                                                        myLanguage: myLanguage))
        Task { await load() }
    }

    // MARK: - Public

    override func process(viewAction: CallTranslationToolScreenViewAction) {
        switch viewAction {
        case .setEnabled(let isEnabled):
            save { tool in
                tool.isEnabled = isEnabled
                // A first switch-on keeps the promise of the tool's name: the assistant translates if nobody does.
                if isEnabled, stored == nil { tool.translatesIfNobodyDoes = true }
            }
        case .setTranslatesIfNobodyDoes(let isOn):
            save { $0.translatesIfNobodyDoes = isOn }
        case .setLanguage(let language):
            let code = language ?? state.myLanguage
            save { $0.language = code }
        case .retry:
            Task { await load() }
        }
    }

    // MARK: - Private

    private func load() async {
        state.isLoading = true
        state.isLoadFailed = false
        if let catalog = await service.languages(), !catalog.isEmpty {
            state.catalog = catalog
            state.myLanguage = myLanguageStore.resolved(catalog: catalog.map(\.code)) ?? myLanguageStore.displayLanguage
        }
        switch await service.translationTool() {
        case .success(let tool):
            stored = tool
            state.tool = tool ?? NativeCallTranslationTool(language: state.myLanguage)
        case .failure:
            // Couldn't read is no answer: nothing is offered to change, and the screen says so.
            state.isLoadFailed = true
        }
        state.isLoading = false
    }

    /// Every change is stored at once, as a chat tool's switch is; a refused one is put back.
    private func save(_ change: (inout NativeCallTranslationTool) -> Void) {
        guard !state.isLoading, !state.isLoadFailed, !state.isSaving else { return }
        let previous = state.tool
        var draft = previous
        change(&draft)
        guard draft != previous else { return }
        state.tool = draft
        state.isSaving = true
        state.isSaveFailed = false
        Task {
            let isStored = await service.storeTranslationTool(draft)
            if isStored, case .success(let tool) = await service.translationTool() {
                stored = tool
                state.tool = tool ?? NativeCallTranslationTool(language: draft.language)
            } else if !isStored {
                state.tool = previous
                state.isSaveFailed = true
            }
            state.isSaving = false
        }
    }
}

/// The chat's Tools: the platform, for one assistant in one chat.
final class CallTranslationToolService: CallTranslationToolServiceProtocol {
    private let roomID: String
    private let agentID: String
    private let service: AgentPlatformServiceProtocol
    private let catalog: NativeCallLanguageCatalogCache
    private let store: NativeCallTranslationToolStore

    init(roomID: String,
         agentID: String,
         service: AgentPlatformServiceProtocol,
         catalog: NativeCallLanguageCatalogCache = .standard,
         myLanguageStore: NativeCallMyLanguageStore = .standard) {
        self.roomID = roomID
        self.agentID = agentID
        self.service = service
        self.catalog = catalog
        store = NativeCallTranslationToolStore(service: service, myLanguageStore: myLanguageStore)
    }

    func languages() async -> [VoiceControlsCatalogLanguage]? {
        await catalog.load { await service.voiceLanguages() }
    }

    func translationTool() async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError> {
        await store.read(roomID: roomID, agentID: agentID)
    }

    func storeTranslationTool(_ tool: NativeCallTranslationTool) async -> Bool {
        var tool = tool
        tool.agentID = agentID
        return await store.write(tool, roomID: roomID)
    }
}
