//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decision 284). The bio in the profile
// editor: offered only when the server allows it, a failed read never
// becomes an empty bio, one normalised line of at most 160 characters,
// empty saves as a delete, a failed save keeps the text.
//

import Combine
@testable import Spiral
import Testing

@MainActor
struct UserDetailsEditScreenBioTests {
    private var clientProxy: ClientProxyMock!
    private var viewModel: UserDetailsEditScreenViewModel!

    private var context: UserDetailsEditScreenViewModelType.Context {
        viewModel.context
    }

    @Test
    func theBioIsNotOfferedWhenTheServerDoesNotAllowIt() async throws {
        var testSetup = self
        testSetup.setUp(canSetBio: false, bio: .success("Hi"))

        try await testSetup.waitForBio { $0 == .unavailable }

        #expect(testSetup.clientProxy.canSetUserBioCalled)
        #expect(!testSetup.clientProxy.userBioCalled)
    }

    /// Brief 0083, question 359: the server nearly always allows it, so the section stands before it says so.
    @Test
    func theBioHasItsPlaceFromTheFirstFrame() {
        var testSetup = self
        testSetup.setUp(bio: .success("Gardener"))

        #expect(testSetup.context.viewState.bio == .loading)
    }

    @Test
    func aFailedCheckShowsNoFieldAndTheNextOpeningChecksAgain() async throws {
        var testSetup = self
        // A failed check reads as `false` (ClientProxy.canSetUserBio logs the error).
        testSetup.setUp(canSetBio: false, bio: .success("Hi"))
        try await testSetup.waitForBio { $0 == .unavailable }
        
        // The screen opened again is a new view model, and it asks again.
        testSetup.clientProxy.canSetUserBioReturnValue = true
        testSetup.makeViewModel()
        try await testSetup.waitForBio { $0 == .loaded("Hi") }
        #expect(testSetup.clientProxy.canSetUserBioCallsCount == 2)
    }

    @Test
    func theBioLoadsIntoTheField() async throws {
        var testSetup = self
        testSetup.setUp(bio: .success("Gardener"))

        try await testSetup.waitForBio { $0 == .loaded("Gardener") }

        #expect(testSetup.context.bio == "Gardener")
        #expect(!testSetup.context.viewState.bioDidChange)
        #expect(!testSetup.context.viewState.canSave)
    }

    @Test
    func anUnsetBioLoadsAsAnEmptyField() async throws {
        var testSetup = self
        testSetup.setUp(bio: .success(nil))

        try await testSetup.waitForBio { $0 == .loaded(nil) }

        #expect(testSetup.context.bio.isEmpty)
        #expect(!testSetup.context.viewState.canSave)
    }

    @Test
    func aFailedLoadIsNeverAnEmptyBioToSave() async throws {
        var testSetup = self
        testSetup.setUp(bio: .failure(.sdkError(ClientProxyMockError.generic)))

        try await testSetup.waitForBio { $0 == .loadFailed }

        testSetup.context.bio = ""
        #expect(!testSetup.context.viewState.bioDidChange)
        #expect(!testSetup.context.viewState.canSave)

        // A name change still saves, and leaves the bio alone.
        testSetup.clientProxy.setUserDisplayNameReturnValue = .success(())
        let dismissed = deferFulfillment(testSetup.viewModel.actions) { $0 == .dismiss }
        testSetup.context.name = "New name"
        testSetup.context.send(viewAction: .save)
        try await dismissed.fulfill()
        #expect(!testSetup.clientProxy.setUserBioCalled)
        #expect(!testSetup.clientProxy.removeUserBioCalled)
    }

    @Test
    func aFailedLoadCanBeRetried() async throws {
        var testSetup = self
        testSetup.setUp(bio: .failure(.sdkError(ClientProxyMockError.generic)))
        try await testSetup.waitForBio { $0 == .loadFailed }

        testSetup.clientProxy.userBioReturnValue = .success("Back")
        let loaded = deferFulfillment(testSetup.context.observe(\.viewState.bio)) { $0 == .loaded("Back") }
        testSetup.context.send(viewAction: .retryLoadingBio)
        try await loaded.fulfill()

        #expect(testSetup.context.bio == "Back")
    }

    @Test
    func anEditedBioCanBeSaved() async throws {
        var testSetup = self
        testSetup.setUp(bio: .success("Gardener"))
        try await testSetup.waitForBio { $0 == .loaded("Gardener") }

        testSetup.context.bio = "Gardener and hiker"

        #expect(testSetup.context.viewState.bioDidChange)
        #expect(testSetup.context.viewState.canSave)
        #expect(testSetup.context.viewState.bioLength == 18)
    }

    @Test
    func whatNormalisesBackToTheSavedBioIsNoChange() async throws {
        var testSetup = self
        testSetup.setUp(bio: .success(nil))
        try await testSetup.waitForBio { $0 == .loaded(nil) }

        testSetup.context.bio = "  \n "

        #expect(!testSetup.context.viewState.bioDidChange)
        #expect(!testSetup.context.viewState.canSave)
    }

    @Test
    func theLimitCountsCharactersAsPeopleSeeThem() async throws {
        var testSetup = self
        testSetup.setUp(bio: .success(nil))
        try await testSetup.waitForBio { $0 == .loaded(nil) }

        // 👩‍💻 is three code points joined by U+200D: one character.
        testSetup.context.bio = String(repeating: "\u{1F469}\u{200D}\u{1F4BB}", count: FeedBio.maxLength)
        #expect(testSetup.context.viewState.bioLength == FeedBio.maxLength)
        #expect(!testSetup.context.viewState.isBioTooLong)
        #expect(testSetup.context.viewState.canSave)

        testSetup.context.bio = String(repeating: "я", count: FeedBio.maxLength + 1)
        #expect(testSetup.context.viewState.isBioTooLong)
        #expect(!testSetup.context.viewState.canSave)
    }

    @Test
    func anUnchangedTooLongBioDoesNotHoldBackANameChange() async throws {
        var testSetup = self
        let longBio = String(repeating: "a", count: FeedBio.maxLength + 1)
        testSetup.setUp(bio: .success(longBio))
        try await testSetup.waitForBio { $0 == .loaded(longBio) }
        #expect(testSetup.context.viewState.isBioTooLong)
        
        testSetup.context.name = "New name"
        #expect(testSetup.context.viewState.canSave)
        
        testSetup.clientProxy.setUserDisplayNameReturnValue = .success(())
        let dismissed = deferFulfillment(testSetup.viewModel.actions) { $0 == .dismiss }
        testSetup.context.send(viewAction: .save)
        try await dismissed.fulfill()
        #expect(testSetup.clientProxy.setUserDisplayNameCalled)
        #expect(!testSetup.clientProxy.setUserBioCalled)
    }

    @Test
    func aChangedTooLongBioHoldsBackANameChange() async throws {
        var testSetup = self
        testSetup.setUp(bio: .success("Gardener"))
        try await testSetup.waitForBio { $0 == .loaded("Gardener") }
        
        testSetup.context.name = "New name"
        testSetup.context.bio = String(repeating: "a", count: FeedBio.maxLength + 1)
        // Saving would drop the bio the person typed, so Save waits and the footer says to shorten it.
        #expect(!testSetup.context.viewState.canSave)
    }

    @Test
    func theSavedBioIsOneNormalisedLine() async throws {
        var testSetup = self
        testSetup.setUp(bio: .success(nil))
        try await testSetup.waitForBio { $0 == .loaded(nil) }

        let dismissed = deferFulfillment(testSetup.viewModel.actions) { $0 == .dismiss }
        testSetup.context.bio = "  Hi,\n\nI am Ann \u{202E}gpj.exe\u{202C}\u{200B}  "
        testSetup.context.send(viewAction: .save)
        try await dismissed.fulfill()

        #expect(testSetup.clientProxy.setUserBioReceivedBio == "Hi, I am Ann gpj.exe")
        #expect(!testSetup.clientProxy.removeUserBioCalled)
    }

    @Test(arguments: ["", "  \n\u{200B} "])
    func anEmptiedBioSavesAsADelete(emptied: String) async throws {
        var testSetup = self
        testSetup.setUp(bio: .success("Gardener"))
        try await testSetup.waitForBio { $0 == .loaded("Gardener") }

        let dismissed = deferFulfillment(testSetup.viewModel.actions) { $0 == .dismiss }
        testSetup.context.bio = emptied
        testSetup.context.send(viewAction: .save)
        try await dismissed.fulfill()

        #expect(testSetup.clientProxy.removeUserBioCalled)
        #expect(!testSetup.clientProxy.setUserBioCalled)
    }

    @Test
    func aFailedSaveKeepsTheTextAndSaysSo() async throws {
        var testSetup = self
        testSetup.setUp(bio: .success("Gardener"))
        try await testSetup.waitForBio { $0 == .loaded("Gardener") }
        testSetup.clientProxy.setUserBioReturnValue = .failure(.sdkError(ClientProxyMockError.generic))

        let notDismissed = deferFailure(testSetup.viewModel.actions, timeout: .seconds(1)) { $0 == .dismiss }
        let alerted = deferFulfillment(testSetup.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .bioSaveError }
        testSetup.context.bio = "Hiker"
        testSetup.context.send(viewAction: .save)
        try await alerted.fulfill()
        try await notDismissed.fulfill()

        #expect(testSetup.context.bio == "Hiker")
        #expect(testSetup.context.viewState.bio == .loaded("Gardener"))
        #expect(testSetup.context.viewState.canSave)
    }

    // MARK: - Helpers

    private mutating func setUp(canSetBio: Bool = true, bio: Result<String?, ClientProxyError>) {
        clientProxy = ClientProxyMock(.init(canSetBio: canSetBio))
        clientProxy.userBioReturnValue = bio
        makeViewModel()
    }

    private mutating func makeViewModel() {
        viewModel = UserDetailsEditScreenViewModel(userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                                   mediaUploadingPreprocessor: MediaUploadingPreprocessor(userSettings: .mock()),
                                                   appMediator: AppMediatorMock(.init()),
                                                   userIndicatorController: UserIndicatorControllerMock())
    }

    private func waitForBio(_ condition: @escaping (UserDetailsEditBioState) -> Bool) async throws {
        let deferred = deferFulfillment(context.observe(\.viewState.bio), until: condition)
        try await deferred.fulfill()
    }
}
