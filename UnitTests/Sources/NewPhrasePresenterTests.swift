//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0075 — how the identity page's return is read.
//

import SwiftUI
@testable import Spiral
import Testing

struct NewPhrasePresenterTests {
    @Test
    func aChangedPhraseIsReportedAsChanged() {
        #expect(NewPhrasePresenter.outcome(for: URL(string: "spiral://phrase-changed?result=changed")) == .changed)
    }
    
    @Test
    func everythingElseIsACancel() {
        #expect(NewPhrasePresenter.outcome(for: URL(string: "spiral://phrase-changed?result=cancelled")) == .cancelled)
        #expect(NewPhrasePresenter.outcome(for: URL(string: "spiral://phrase-changed")) == .cancelled)
        #expect(NewPhrasePresenter.outcome(for: URL(string: "spiral://join/abc?result=changed")) == .cancelled)
        #expect(NewPhrasePresenter.outcome(for: URL(string: "https://phrase-changed?result=changed")) == .cancelled)
        #expect(NewPhrasePresenter.outcome(for: nil) == .cancelled)
    }
    
    // MARK: - The wait for the scene after Face ID (Fable, 1.0.3 new phrase)
    
    @Test
    func theWaitEndsOnceTheSceneIsActive() async {
        let states = SceneStates([.foregroundInactive, .foregroundInactive, .foregroundActive])
        let wait = await IdentityPageSession.waitForActiveScene(activationState: states.next, hasEnteredBackground: { false }, interval: .zero)
        #expect(wait == .active)
    }
    
    /// Swiping home during Face ID cancels: on return the page must not open unprompted.
    @Test
    func aTripToTheBackgroundCancelsTheWait() async {
        let states = SceneStates([.foregroundInactive, .background, .foregroundInactive, .foregroundActive])
        let wait = await IdentityPageSession.waitForActiveScene(activationState: states.next, hasEnteredBackground: { false }, interval: .zero)
        #expect(wait == .wentToBackground)
    }
    
    /// The app suspended mid-wait wakes up to an active scene; the notification it missed in the loop still counts.
    @Test
    func aBackgroundTripTheLoopDidNotSeeStillCancels() async {
        let wait = await IdentityPageSession.waitForActiveScene(activationState: { .foregroundActive }, hasEnteredBackground: { true }, interval: .zero)
        #expect(wait == .wentToBackground)
    }
    
    /// Fable L1: a swipe home while the ticket is requested (before the page's wait begins) still cancels on return.
    @MainActor
    @Test
    func aTripToTheBackgroundDuringTheTicketRequestCancels() async throws {
        let service = AgentPlatformServiceMock()
        let ticketURL = try #require(URL(string: "https://id.spiral.md/phrase/reset?ticket=t"))
        service.createPhraseResetClosure = {
            await MainActor.run {
                NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: nil)
            }
            return .success(ticketURL)
        }
        let authenticator = DeviceOwnerAuthenticatorMock()
        authenticator.authenticateReasonReturnValue = .authenticated
        // A window with no scene: its state never reads active, so only the noted trip can end the wait quickly.
        let presenter = NewPhrasePresenter(agentPlatformService: service, presentationAnchor: UIWindow(), authenticator: authenticator)
        
        let started = ContinuousClock.now
        #expect(await presenter.start() == .cancelled)
        #expect(ContinuousClock.now - started < .seconds(5), "Cancelled at once, not after the wait ran out.")
    }
    
    @Test
    func aSceneThatNeverBecomesActiveTimesOut() async {
        let wait = await IdentityPageSession.waitForActiveScene(activationState: { .foregroundInactive },
                                                                hasEnteredBackground: { false },
                                                                attempts: 3,
                                                                interval: .zero)
        #expect(wait == .timedOut)
    }
}

/// Hands out the scene's states in order, then keeps the last.
private final class SceneStates {
    private var states: [UIScene.ActivationState]
    
    init(_ states: [UIScene.ActivationState]) {
        self.states = states
    }
    
    func next() -> UIScene.ActivationState? {
        states.count > 1 ? states.removeFirst() : states.first
    }
}
