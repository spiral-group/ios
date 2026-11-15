//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, backend ADR-0094 D9, A.5, Appendix C row 14): the chat's personal tool "Перевод звонков"
// — in calls here I listen in a language; if nobody translates, my assistant does. Reached from the chat's Tools like
// every Tool, and from the call. The language is concrete: resolved from "my language" when saved, and shown.

import Foundation

/// Where the screen reads and stores the tool, bound to one chat (and, from the chat's Tools, one assistant).
@MainActor
protocol CallTranslationToolServiceProtocol: AnyObject {
    /// The voice catalog (ADR-0094 A.8). Nil when it was never read.
    func languages() async -> [VoiceControlsCatalogLanguage]?
    /// `.success(nil)` when the chat has no such tool.
    func translationTool() async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError>
    /// False when it wasn't stored.
    func storeTranslationTool(_ tool: NativeCallTranslationTool) async -> Bool
}

struct CallTranslationToolScreenViewState: BindableState {
    /// The assistant it is for, under the title; nil in the call.
    var agentDisplayName: String?
    /// The first read is out: rows hold their place, nothing can be changed yet.
    var isLoading = true
    /// The first read failed: nothing is known to change.
    var isLoadFailed = false
    var tool: NativeCallTranslationTool
    var catalog: [VoiceControlsCatalogLanguage] = []
    /// "My language", a catalog code: what the tool's language starts as.
    var myLanguage: String
    var isSaving = false
    /// The last change wasn't stored and was put back.
    var isSaveFailed = false
    var bindings = CallTranslationToolScreenViewStateBindings()
}

struct CallTranslationToolScreenViewStateBindings {
    var isLanguagePresented = false
}

enum CallTranslationToolScreenViewAction {
    case setEnabled(Bool)
    case setTranslatesIfNobodyDoes(Bool)
    /// Nil: "my language", stored as its concrete code.
    case setLanguage(String?)
    case retry
}
