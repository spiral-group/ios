//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

struct TimelineReadProgressTests {
    private let me = "@me:spiral.test"
    private let person = "@alice:spiral.test"
    private let agent = "@assistant-alice:spiral.test"
    
    @Test
    func aReceiptCountsForEveryEarlierOwnMessage() {
        let progress = TimelineReadProgress(events: [own("1"), own("2"), other("3", receipts: [person]), own("4")], ownUserID: me)
        
        #expect(readOwnMessages(of: progress) == ["1", "2"])
    }
    
    @Test
    func aReceiptOnAnEventWithoutARowCounts() {
        // A message of a type this build doesn't know, say: the row is never built, the receipt is still there.
        let progress = TimelineReadProgress(events: [own("1"), other("no-row", receipts: [person])], ownUserID: me)
        
        #expect(readOwnMessages(of: progress) == ["1"])
    }
    
    @Test
    func aMessageTheServerHasNotGotIsNeverRead() {
        let progress = TimelineReadProgress(events: [own("1"),
                                                     own("failed", isOnServer: false),
                                                     other("2", receipts: [person])],
                                            ownUserID: me)
        
        #expect(readOwnMessages(of: progress) == ["1"])
        #expect(progress.readers(of: .init("failed")).isEmpty)
    }
    
    @Test
    func myOwnReceiptIsNotARead() {
        let progress = TimelineReadProgress(events: [own("1", receipts: [me])], ownUserID: me)
        
        #expect(readOwnMessages(of: progress).isEmpty)
        #expect(progress.readers(of: .init("1")).isEmpty)
    }
    
    @Test
    func anAgentInADMWithAPersonIsNotARead() {
        let progress = TimelineReadProgress(events: [own("1", receipts: [agent])], ownUserID: me)
        
        #expect(readOwnMessages(of: progress, dmUserID: person).isEmpty)
    }
    
    @Test
    func thePersonStillCountsPastAnAgentThatReadFurther() {
        let progress = TimelineReadProgress(events: [own("1", receipts: [person]), own("2", receipts: [agent])], ownUserID: me)
        
        #expect(readOwnMessages(of: progress, dmUserID: person) == ["1"])
    }
    
    @Test
    func theAgentOfADMWithTheAgentIsARead() {
        let progress = TimelineReadProgress(events: [own("1", receipts: [agent])], ownUserID: me)
        
        #expect(readOwnMessages(of: progress, dmUserID: agent) == ["1"])
    }
    
    @Test
    func aGroupNeedsAPerson() {
        let onlyAgent = TimelineReadProgress(events: [own("1", receipts: [agent])], ownUserID: me)
        let anyPerson = TimelineReadProgress(events: [own("1", receipts: [agent, person])], ownUserID: me)
        
        #expect(readOwnMessages(of: onlyAgent, dmUserID: nil).isEmpty)
        #expect(readOwnMessages(of: anyPerson, dmUserID: nil) == ["1"])
    }
    
    @Test
    func anotherServersAssistantIsAPerson() {
        let stranger = "@assistant-bob:elsewhere.test"
        let progress = TimelineReadProgress(events: [own("1", receipts: [stranger])], ownUserID: me)
        
        #expect(readOwnMessages(of: progress, dmUserID: person) == ["1"])
    }
    
    @Test
    func seenByListsEveryoneWhoReachedTheMessageFurthestFirst() {
        let bob = "@bob:spiral.test"
        let progress = TimelineReadProgress(events: [own("1", receipts: [bob]), other("2"), own("3", receipts: [person, agent])],
                                            ownUserID: me)
        
        #expect(progress.readers(of: .init("1")).map(\.userID) == [person, agent, bob])
        #expect(progress.readers(of: .init("2")).map(\.userID) == [person, agent])
        #expect(progress.readers(of: .init("3")).map(\.userID) == [person, agent])
    }
    
    // MARK: - Helpers
    
    private func own(_ id: String, isOnServer: Bool = true, receipts: [String] = []) -> TimelineReadProgress.Event {
        event(id, isOwn: true, isOnServer: isOnServer, receipts: receipts)
    }
    
    private func other(_ id: String, receipts: [String] = []) -> TimelineReadProgress.Event {
        event(id, isOwn: false, isOnServer: true, receipts: receipts)
    }
    
    private func event(_ id: String, isOwn: Bool, isOnServer: Bool, receipts: [String]) -> TimelineReadProgress.Event {
        .init(uniqueID: .init(id),
              isOwn: isOwn,
              isOnServer: isOnServer,
              receipts: receipts.map { ReadReceipt(userID: $0, formattedTimestamp: nil) })
    }
    
    private func readOwnMessages(of progress: TimelineReadProgress, dmUserID: String? = nil) -> Set<String> {
        let ids = progress.readOwnMessages { TimelineReadProgress.isCounted($0, ownUserID: me, dmUserID: dmUserID) }
        return Set(ids.map(\.value))
    }
}
