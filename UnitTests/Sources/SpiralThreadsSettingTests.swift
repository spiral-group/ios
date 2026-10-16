//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 188): threads and the thread list are on for everyone.
//

@testable import ElementX
import Testing

@MainActor
struct SpiralThreadsSettingTests {
    /// An earlier build's Labs or Developer options toggle stored `false` under
    /// upstream's keys; nothing reads those keys any more.
    @Test
    func anOldStoredOffStillReadsOn() {
        let store = VolatileUserDefaults(initialValues: ["threadsEnabled": false, "roomThreadListEnabled": false])
        let appSettings = AppSettings(store: store)
        
        #expect(appSettings.threadsEnabled)
        #expect(appSettings.roomThreadListEnabled)
    }
}
