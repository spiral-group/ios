//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0085, question 403): an own assistant's four jobs, and how someone
// else's assistant is named.

struct NativeCallAgentJobsTests {
    @Test(arguments: NativeCallAssistantJob.allCases)
    func aTapOnAJobBringsTheAssistantForThatJobAlone(job: NativeCallAssistantJob) {
        let params = job.attachParams(translation: .forLanguage("uk"))
        #expect((params.translation != nil) == (job == .translation))
        #expect(params.summary == (job == .summary))
        #expect(params.recording == (job == .recording))
        #expect(params.conversation == (job == .conversation))
    }

    @Test
    func anotherPersonsAssistantIsNamedAfterItsOwner() {
        let people = ["@mira:x.org": "Mira Testova", "@alex:x.org": "Alex Sample"]
        #expect(NativeCallForeignAssistantName(agentMxid: "@assistant-mira:x.org", displayName: "Mira Testova · асистент", people: people)
            == .personal(owner: "Mira Testova"))
        #expect(NativeCallForeignAssistantName(agentMxid: "@assistant-mira-2:x.org", displayName: "Book helper", people: people)
            == .custom(name: "Book helper", owner: "Mira Testova"))
        #expect(NativeCallForeignAssistantName(agentMxid: "@agent-shop:x.org", displayName: "Shop", people: people)
            == .custom(name: "Shop", owner: nil))
    }
}
