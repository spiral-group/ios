//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, question 403): call translation for everyone. Each person picks the language they hear
// the call in; a (speaker × input × language) lane is produced by at most one assistant and anyone may listen to it for
// free. The lanes, their producers and owners, and why a lane stopped come from the agents' state documents (ADR-0094
// A.6), which every device has. The rest comes from the sources this port names, and the call lab answers them in
// memory: the voice catalog (A.8), the participants' languages on their call memberships (A.1), and the chat's
// personal tool (A.5) with the device's listen preference (Appendix C row 14).

import Foundation

/// The personal per-chat tool "Перевод звонков" (ADR-0094 D9, A.5; Appendix C row 14): in calls here I listen in
/// `language`; if nobody translates, my assistant does. The language is concrete — resolved from my language when it
/// is saved and shown as it is — so there is no follow-my-language mode the server can't see.
nonisolated struct NativeCallTranslationTool: Equatable {
    /// "In calls here I listen in `language`".
    var isEnabled = false
    /// A catalog code.
    var language: String
    /// "If nobody translates, my assistant does": the personal `live_translate` Tool is armed. Off, only the device
    /// keeps the listen preference.
    var translatesIfNobodyDoes = false
    /// The armed Tool and its agent, for an edit (`replaces_tool_id`) and its removal.
    var toolID: String?
    var agentID: String?
}

/// What the call learns about its translation beyond the agents' documents.
nonisolated struct NativeCallTranslationFacts: Equatable {
    /// Each participant's published "my language" (A.1), by MXID, as catalog codes.
    var languages: [String: String] = [:]
    /// This chat's tool, nil when not set up.
    var tool: NativeCallTranslationTool?
}

nonisolated enum NativeCallTranslationPortError: Error {
    case unavailable
}

/// The seam the backend contract (ADR-0094) is read and written through, beside the documents. Every method answers
/// on the main actor.
protocol NativeCallTranslationPortProtocol: AnyObject {
    /// The voice catalog (A.8), kept for a day. Nil when it was never read.
    func languages() async -> [VoiceControlsCatalogLanguage]?
    /// The participants' languages from their memberships (A.1). Nil when they couldn't be read: the last stay.
    func participantLanguages(roomID: String) async -> [String: String]?
    /// Publishes "my language" with this person's call membership, so no assistant translates them into their own
    /// language (ADR-0031 LT6). False when it didn't reach the call.
    func publishMyLanguage(_ language: String, roomID: String) async -> Bool
    /// This chat's tool; `.success(nil)` when it isn't set up.
    func tool(roomID: String) async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError>
    /// Stores this chat's tool. False when it wasn't stored.
    func setTool(_ tool: NativeCallTranslationTool, roomID: String) async -> Bool
}

/// Production: the platform for the catalog and the tool, the call's memberships for the languages.
final class NativeCallTranslationPort: NativeCallTranslationPortProtocol {
    private let service: AgentPlatformServiceProtocol
    private let memberships: NativeCallMembershipLanguagesProtocol
    private let catalog: NativeCallLanguageCatalogCache
    private let myLanguageStore: NativeCallMyLanguageStore

    init(service: AgentPlatformServiceProtocol,
         memberships: NativeCallMembershipLanguagesProtocol,
         catalog: NativeCallLanguageCatalogCache = .standard,
         myLanguageStore: NativeCallMyLanguageStore = .standard) {
        self.service = service
        self.memberships = memberships
        self.catalog = catalog
        self.myLanguageStore = myLanguageStore
    }

    func languages() async -> [VoiceControlsCatalogLanguage]? {
        await catalog.load { await service.voiceLanguages() }
    }

    func participantLanguages(roomID: String) async -> [String: String]? {
        await memberships.languages()
    }

    func publishMyLanguage(_ language: String, roomID: String) async -> Bool {
        await memberships.publish(language)
    }

    func tool(roomID: String) async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError> {
        await NativeCallTranslationToolStore(service: service, myLanguageStore: myLanguageStore)
            .read(roomID: roomID, agentID: myLanguageStore.assistant(roomID: roomID))
    }

    func setTool(_ tool: NativeCallTranslationTool, roomID: String) async -> Bool {
        await NativeCallTranslationToolStore(service: service, myLanguageStore: myLanguageStore).write(tool, roomID: roomID)
    }
}

/// The chat's tool on the wire and on the device (A.5, row 14), shared by the call and the chat's Tools.
struct NativeCallTranslationToolStore {
    let service: RoomToolsServiceProtocol
    let myLanguageStore: NativeCallMyLanguageStore

    /// The armed `live_translate` of `agentID` (else of the first own agent in the room) and the device's listen
    /// preference. A failed room read is no answer: it isn't "no tool".
    func read(roomID: String, agentID: String?) async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError> {
        switch await service.fetchRoomTools(roomID: roomID) {
        case .success(let room):
            return .success(Self.tool(room: room, agentID: agentID, listenLanguage: myLanguageStore.listenLanguage(roomID: roomID)))
        case .failure(let error):
            MXLog.warning("Call translation tool: the room's tools couldn't be read: \(error)")
            return .failure(.unavailable)
        }
    }

    static func tool(room: RoomToolsView, agentID: String?, listenLanguage: String?) -> NativeCallTranslationTool? {
        let own = room.agents.filter(\.isMine)
        let agent = own.first { $0.agentID == agentID } ?? own.first
        let armed = agent?.tools.lazy.compactMap { tool -> (id: String?, language: String)? in
            guard case .liveTranslate(let language) = tool.params else { return nil }
            return (tool.toolID, language)
        }.first
        if let armed {
            return NativeCallTranslationTool(isEnabled: true, language: armed.language, translatesIfNobodyDoes: true,
                                             toolID: armed.id, agentID: agent?.agentID)
        }
        guard let listenLanguage else { return nil }
        return NativeCallTranslationTool(isEnabled: true, language: listenLanguage, agentID: agent?.agentID)
    }

    /// Arms, edits or removes the Tool so it says what `tool` says, then keeps the listen preference on the device.
    /// A second arm answered `tool-duplicate` is an edit of the one already there.
    func write(_ tool: NativeCallTranslationTool, roomID: String) async -> Bool {
        guard case .success(let current) = await read(roomID: roomID, agentID: tool.agentID) else { return false }
        let wantsTool = tool.isEnabled && tool.translatesIfNobodyDoes
        let agentID = tool.agentID ?? current?.agentID
        if wantsTool {
            guard let agentID else {
                MXLog.warning("Call translation tool: no own assistant in this chat to arm it for")
                return false
            }
            if current?.translatesIfNobodyDoes != true || current?.language != tool.language {
                guard await arm(language: tool.language, agentID: agentID, roomID: roomID, replacing: current?.toolID) else { return false }
            }
        } else if let toolID = current?.toolID, let agentID {
            if case .failure(let error) = await service.disableTool(agentID: agentID, roomID: roomID, toolID: toolID) {
                MXLog.error("Call translation tool: removing it failed: \(error)")
                return false
            }
        }
        myLanguageStore.setListenLanguage(tool.isEnabled ? tool.language : nil, roomID: roomID)
        return true
    }

    private func arm(language: String, agentID: String, roomID: String, replacing toolID: String?) async -> Bool {
        let result = await service.armTool(agentID: agentID,
                                           roomID: roomID,
                                           params: .liveTranslate(language: language),
                                           trigger: .onVoiceCall(speakerScope: .anyone),
                                           replacesToolID: toolID)
        switch result {
        case .success:
            return true
        case .failure(.refused(.duplicate)) where toolID == nil:
            // Armed elsewhere meanwhile: this is an edit of that one.
            guard case .success(let current) = await read(roomID: roomID, agentID: agentID), let existing = current?.toolID else { return false }
            return await arm(language: language, agentID: agentID, roomID: roomID, replacing: existing)
        case .failure(.replacedGone):
            return await arm(language: language, agentID: agentID, roomID: roomID, replacing: nil)
        case .failure(let error):
            MXLog.error("Call translation tool: arming it failed: \(error)")
            return false
        }
    }
}
