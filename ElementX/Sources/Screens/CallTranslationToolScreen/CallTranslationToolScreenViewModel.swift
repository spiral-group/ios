//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

typealias CallTranslationToolScreenViewModelType = StateStoreViewModelV2<CallTranslationToolScreenViewState, CallTranslationToolScreenViewAction>

class CallTranslationToolScreenViewModel: CallTranslationToolScreenViewModelType {
    private let service: CallTranslationToolServiceProtocol
    private let myLanguageStore: NativeCallMyLanguageStore
    /// What is stored, as the last read or write left it; nil when the chat has no tool.
    private var stored: NativeCallTranslationTool?
    /// The tool was switched on on this screen: only that first switch-on chooses «translate if nobody does».
    private var hasSwitchedOn = false
    /// A change was made while a save was under way: what is shown then is stored right after it.
    private var hasChangeWaiting = false

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
            // A first switch-on keeps the promise of the tool's name: the assistant translates if nobody does. Once
            // only: switched on again before its save lands, the person's own choice since stays.
            let isFirstSwitchOn = isEnabled && stored == nil && !hasSwitchedOn
            hasSwitchedOn = hasSwitchedOn || isEnabled
            save { tool in
                tool.isEnabled = isEnabled
                if isFirstSwitchOn { tool.translatesIfNobodyDoes = true }
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

    /// Every change is stored at once, as a chat tool's switch is; a refused one is put back. One made while a save is
    /// under way shows at once and is stored right after it: it used to be dropped, and its switch snapped back.
    private func save(_ change: (inout NativeCallTranslationTool) -> Void) {
        guard !state.isLoading, !state.isLoadFailed else { return }
        let previous = state.tool
        var draft = previous
        change(&draft)
        guard draft != previous else { return }
        state.tool = draft
        state.isSaveFailed = false
        if state.isSaving {
            hasChangeWaiting = true
        } else {
            store(draft, puttingBack: previous)
        }
    }
    
    /// Stores the tool as shown when a change waits on the save that just landed; false when none does.
    private func storeWaitingChange(after draft: NativeCallTranslationTool) -> Bool {
        guard hasChangeWaiting else { return false }
        hasChangeWaiting = false
        store(state.tool, puttingBack: draft)
        return true
    }

    /// The whole tool is written each time, so the one shown last is the one that counts.
    private func store(_ draft: NativeCallTranslationTool, puttingBack previous: NativeCallTranslationTool) {
        state.isSaving = true
        Task {
            guard await service.storeTranslationTool(draft) else {
                // Refused: what was shown before it comes back, and a change waiting on it goes with it. With nothing
                // stored yet, the next switch-on is the first again.
                hasChangeWaiting = false
                if stored == nil {
                    hasSwitchedOn = false
                }
                state.tool = previous
                state.isSaveFailed = true
                state.isSaving = false
                return
            }
            stored = draft.isEnabled ? draft : stored
            guard !storeWaitingChange(after: draft) else { return }
            let read = await service.translationTool()
            // A change made during the read wins over it: the read would put the switch back.
            guard !storeWaitingChange(after: draft) else { return }
            if case .success(let tool) = read {
                stored = tool
                state.tool = tool ?? NativeCallTranslationTool(language: draft.language)
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
