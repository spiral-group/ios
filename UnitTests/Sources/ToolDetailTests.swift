//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct ToolDetailTests {
    // MARK: - `applies_to_viewer`
    
    @Test(arguments: [("yes", ToolAppliesToViewer.yes),
                      ("no", .no),
                      ("not_applicable", .notApplicable),
                      ("unknown", .unknown),
                      // Decision 96: a newer value says nothing, and above all not "no".
                      ("sometimes", .unknown),
                      ("", .unknown)])
    func theWireValueMapsAndANewerOneIsUnknown(wire: String, value: ToolAppliesToViewer) {
        #expect(ToolAppliesToViewer(wire: wire) == value)
    }
    
    @Test(arguments: [(ToolAppliesToViewer.yes, UntranslatedL10n.screenToolDetailYourMessagesProcessed as String?),
                      (.no, UntranslatedL10n.screenToolDetailYourMessagesNotProcessed),
                      (.unknown, UntranslatedL10n.screenToolDetailYourMessagesUnknown),
                      (.notApplicable, nil)])
    func yourMessagesSaysWhatTheServerAnswered(applies: ToolAppliesToViewer, line: String?) {
        #expect(detail(tool(applies: applies)).yourMessages == line)
    }
    
    /// A failed read on the server is never shown as a no.
    @Test
    func unknownIsNotTheNoRow() {
        #expect(detail(tool(applies: .unknown)).yourMessages != detail(tool(applies: .no)).yourMessages)
    }
    
    // MARK: - The safe slice
    
    /// Board 3: kind, language, agent, owner, when.
    @Test
    func thePageSaysWhatTheSliceGives() {
        let detail = detail(tool(kind: "translate", trigger: "on_message", language: "en", applies: .yes))
        
        #expect(detail.title == UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: "en")))
        #expect(detail.explanation == AgentToolKind.translate.explanation)
        #expect(detail.agentName == "Bob's agent")
        #expect(detail.ownerName == "Bohdan")
        #expect(detail.when == UntranslatedL10n.screenAgentRoomToolTriggerMessages)
    }
    
    /// Whatever a read carried, the page's value holds nothing an owner's slice alone has.
    @Test
    func noParamsReachThePageEvenFromAReadThatCarriedThem() {
        let secret = "the owner's private instruction"
        let carried = RoomToolView(toolID: "t1", toolKind: "custom", triggerKind: "on_message", targetLanguage: nil,
                                   params: .custom(instruction: secret),
                                   trigger: .onMessage(senderScope: .specificSenders(members: ["@carol:host"])),
                                   safeSliceSalt: "t", appliesToViewer: .yes)
        
        let page = String(describing: detail(carried))
        
        #expect(!page.contains(secret))
        #expect(!page.contains("@carol:host"))
        #expect(!page.contains("t1"))
    }
    
    /// Decision 96: no words rather than wrong ones.
    @Test
    func aNewerKindAndTriggerLeaveTheirRowsOut() {
        let detail = detail(tool(kind: "teleport", trigger: "on_moon", language: nil, applies: .unknown))
        
        #expect(detail.title == UntranslatedL10n.screenAgentToolsListTitleUnknown)
        #expect(detail.explanation == nil)
        #expect(detail.when == nil)
    }
    
    // MARK: - The example
    
    /// The text tools post in the chat, and nothing else on the form may be drawn as a message.
    @Test(arguments: [AgentToolKind.simplify, .correct, .rephrase, .custom, .summarize])
    func aTextToolAnswersInTheChat(kind: AgentToolKind) throws {
        let (message, reply) = try chat(in: example(kind))
        
        #expect(!message.isEmpty)
        #expect(reply?.isEmpty == false)
        #expect(message != reply)
    }
    
    /// The two take any instruction: the sample names the one it shows, and they don't show the same thing.
    @Test
    func theInstructionToolsSayWhatTheirSampleWasAskedFor() throws {
        let rephrase = example(.rephrase)
        let custom = example(.custom)
        
        #expect(rephrase.hint == UntranslatedL10n.screenToolExampleInstructionPolite)
        #expect(custom.hint == UntranslatedL10n.screenToolExampleInstructionTodo)
        #expect(try chat(in: rephrase).reply != chat(in: custom).reply)
    }
    
    @Test
    func aCallSummaryIsTheMessageTheAgentPosts() {
        #expect(example(.callSummary).sample == .callSummary(SpiralCallSummary(text: UntranslatedL10n.screenToolExampleCallSummary,
                                                                               decisionsTitle: UntranslatedL10n.screenToolExampleCallSummaryDecisionsTitle,
                                                                               decisions: [UntranslatedL10n.screenToolExampleCallSummaryDecision],
                                                                               actionItemsTitle: UntranslatedL10n.screenToolExampleCallSummaryActionItemsTitle,
                                                                               actionItems: [UntranslatedL10n.screenToolExampleCallSummaryActionItem])))
    }
    
    @Test
    func aCallRecordingIsAVoiceMessage() {
        #expect(example(.callRecording).sample == .callRecording)
    }
    
    @Test
    func theTranslationSampleIsInTheChosenLanguage() throws {
        Bundle.overrideLocalizations = ["en"]
        defer { Bundle.overrideLocalizations = nil }
        
        let (message, reply) = try chat(in: ToolExample(kind: .translate, language: "ru"))
        
        #expect(message == UntranslatedL10n.screenToolExampleGreeting)
        #expect(reply != message)
        #expect(reply?.contains("как") == true)
    }
    
    /// The person's own language: the sample starts in another, so it still shows a change.
    @Test
    func theSampleIntoThePersonsOwnLanguageStartsInAnother() throws {
        Bundle.overrideLocalizations = ["en"]
        defer { Bundle.overrideLocalizations = nil }
        
        let (message, reply) = try chat(in: ToolExample(kind: .translate, language: "en"))
        
        #expect(reply == UntranslatedL10n.screenToolExampleGreeting)
        #expect(message != reply)
    }
    
    /// The catalogue's codes are the provider's, and two of them aren't the app's folders.
    @Test(arguments: ["zh-Hant", "pt-PT", "zh-Hans", "pt-BR"])
    func aCatalogueCodeFindsTheAppsStrings(code: String) throws {
        let example = ToolExample(kind: .translate, language: code)
        
        #expect(try chat(in: example).reply != nil)
        #expect(example.hint == nil)
    }
    
    /// A language the app has no strings in gets no made-up sentence, and the tool's name is no one's reply.
    @Test
    func aLanguageWithoutASampleNamesTheToolOutsideTheBubble() throws {
        let example = ToolExample(kind: .translate, language: "sw")
        
        #expect(try chat(in: example).reply == nil)
        #expect(example.hint == UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: "sw")))
    }
    
    /// Question 359, item 20: the request stood in the agent's bubble as if it were the translation.
    @Test
    func noLanguageYetAsksForOneOutsideTheBubble() throws {
        let text = ToolExample(kind: .translate, language: "")
        
        #expect(try chat(in: text).reply == nil)
        #expect(text.hint == UntranslatedL10n.screenArmToolLanguageChoose)
    }
    
    // MARK: - Helpers
    
    private func example(_ kind: AgentToolKind) -> ToolExample {
        ToolExample(kind: kind, language: "de")
    }
    
    private func chat(in example: ToolExample) throws -> (message: String, reply: String?) {
        guard case .chat(let message, let reply) = example.sample else {
            throw ExampleError.notAChat
        }
        return (message, reply)
    }
    
    private func tool(kind: String = "summarize", trigger: String = "on_message", language: String? = nil, applies: ToolAppliesToViewer) -> RoomToolView {
        RoomToolView(toolID: nil, toolKind: kind, triggerKind: trigger, targetLanguage: language,
                     params: nil, trigger: nil, safeSliceSalt: "t", appliesToViewer: applies)
    }
    
    private func detail(_ tool: RoomToolView) -> ToolDetail {
        let agent = RoomToolAgentEntry(agentID: "bob", matrixUserID: "@bob-agent:host", displayName: "Bob's agent",
                                       ownerUserID: "@b:host", isMine: false, tools: [tool])
        return ToolDetail(tool: tool, agent: agent, agentAvatarURL: nil, ownerName: "Bohdan")
    }
}

private enum ExampleError: Error {
    case notAChat
}
