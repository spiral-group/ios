//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (AGPL publication): Settings > About says where the app's
// and the server's source is and where to ask for it, as NOTICE and SOURCES.md do.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct SpiralSourceOfferTests {
    @Test
    func aboutOffersTheSourceAndTheAddressToAskForIt() {
        let viewModel = LegalInformationScreenViewModel(appSettings: .volatile(), appMediator: AppMediatorMock())
        let state = viewModel.context.viewState

        #expect(state.sourceCodeURL == URL(string: "https://github.com/spiral-group/ios"))
        // Decision 107: the server's source is offered too, and the list of every source.
        #expect(state.serverSourceCodeURL == URL(string: "https://github.com/spiral-group/ios/blob/spiral/main/SOURCES.md#the-server"),
                "not a pinned branch, which an old build would keep showing after a server upgrade")
        #expect(state.sourcesListURL == URL(string: "https://github.com/spiral-group/ios/blob/spiral/main/SOURCES.md"))
        #expect(state.sourceRequestAddress == "support@spiral.md")
        #expect(state.sourceRequestURL == URL(string: "mailto:support@spiral.md"))
    }
}
