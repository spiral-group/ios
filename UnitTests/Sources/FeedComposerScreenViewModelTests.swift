//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The text composer (lane I2): one key per
// session through every retry, a failure that never looks posted, the rules
// sheet on `409` or "Update Spiral" for newer rules, the link warning and the
// daily cap from the standing, and a draft kept until it is posted.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedComposerScreenViewModelTests {
    private let service = FeedServiceMock()

    private static let trusted = FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: true,
                                              postsPerDay: 30, postsToday: 0, suspendedUntil: nil)

    init() {
        service.draftReturnValue = nil
        service.standingReturnValue = .success(Self.trusted)
    }

    private static let draftSaveDelay = Duration.milliseconds(20)

    private func makeViewModel(text: String = "Hello feed",
                               clientProxy: ClientProxyMock = ClientProxyMock(.init(userID: "@me:spiral.md"))) -> FeedComposerScreenViewModel {
        let viewModel = FeedComposerScreenViewModel(feedService: service, clientProxy: clientProxy, mediaProvider: MediaProviderMock(.init()), draftSaveDelay: Self.draftSaveDelay)
        viewModel.context.text = text
        return viewModel
    }

    /// What the composer handed on: the sheet closes and the store sends it (decision 289).
    private func sent(by viewModel: FeedComposerScreenViewModel, _ action: () async -> Void) async -> (text: String, key: UUID)? {
        var sent: (String, UUID)?
        let cancellable = viewModel.actionsPublisher.sink { action in
            if case .send(let text, let key) = action { sent = (text, key) }
        }
        await action()
        _ = cancellable
        return sent
    }

    // MARK: - The byline

    /// A name or photo changed elsewhere reaches a composer already open.
    @Test
    func theBylineFollowsAChangedProfile() async throws {
        let profile = CurrentValueSubject<UserProfile, Never>(UserProfile(userID: "@me:spiral.md", displayName: "Before"))
        let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
        clientProxy.userProfilePublisher = profile.asCurrentValuePublisher()
        let viewModel = makeViewModel(clientProxy: clientProxy)
        #expect(viewModel.context.viewState.ownProfile?.displayName == "Before")

        let changed = deferFulfillment(viewModel.context.observe(\.viewState.ownProfile)) { $0?.displayName == "After" }
        profile.send(UserProfile(userID: "@me:spiral.md", displayName: "After"))
        try await changed.fulfill()
    }

    // MARK: - The key

    /// Decision 289: posting closes the composer at once; the draft is kept with the key until the store has the post.
    @Test
    func postingHandsTheTextAndItsKeyOnAndKeepsTheDraft() async throws {
        let viewModel = makeViewModel()

        let sent = await sent(by: viewModel) { await viewModel.post() }

        #expect(sent?.text == "Hello feed")
        #expect(sent?.key == viewModel.idempotencyKey)
        #expect(service.saveDraftReceivedDraft == FeedDraft(text: "Hello feed", idempotencyKey: viewModel.idempotencyKey))
        #expect(service.deleteDraftCallsCount == 0)
        #expect(!service.createPostTextIdempotencyKeyCalled)
    }

    @Test
    func aRestoredDraftReplaysItsKeyAndText() async throws {
        let key = UUID()
        service.draftReturnValue = FeedDraft(text: "Written before the app closed", idempotencyKey: key)

        let viewModel = FeedComposerScreenViewModel(feedService: service, clientProxy: ClientProxyMock(.init(userID: "@me:spiral.md")), mediaProvider: MediaProviderMock(.init()))
        #expect(viewModel.context.text == "Written before the app closed")
        let sent = await sent(by: viewModel) { await viewModel.post() }

        #expect(sent?.key == key)
        #expect(sent?.text == "Written before the app closed")
    }

    @Test
    func emptyOrTooLongTextIsNotSent() async throws {
        for text in ["   \n ", String(repeating: "a", count: FeedPostText.maximumLength + 1)] {
            let viewModel = makeViewModel(text: text)
            #expect(!viewModel.context.viewState.canPost)
            #expect(await sent(by: viewModel) { await viewModel.post() } == nil)
        }
    }

    struct Refusal: CustomTestStringConvertible {
        let error: FeedError
        let title: String
        var testDescription: String {
            error.description
        }
    }

    /// What a post on its way says when it was refused (the row on Latest).
    @Test(arguments: [
        Refusal(error: .linkRefused, title: UntranslatedL10n.screenFeedComposerErrorLinkRefusedTitle),
        Refusal(error: .duplicate, title: UntranslatedL10n.screenFeedComposerErrorDuplicateTitle),
        Refusal(error: .suspended, title: UntranslatedL10n.screenFeedComposerErrorSuspendedTitle),
        Refusal(error: .rateLimited(retryAfterSeconds: 90), title: UntranslatedL10n.screenFeedComposerErrorRateLimitedTitle),
        Refusal(error: .readOnly, title: UntranslatedL10n.screenFeedComposerErrorReadOnlyTitle),
        Refusal(error: .idempotencyKeyReused, title: UntranslatedL10n.screenFeedComposerErrorKeyReusedTitle),
        // Unknown refusals: the generic error.
        Refusal(error: .server(status: 422), title: UntranslatedL10n.screenFeedComposerErrorGenericTitle),
        Refusal(error: .forbidden, title: UntranslatedL10n.screenFeedComposerErrorSuspendedTitle),
        Refusal(error: .temporarilyUnavailable(retryAfterSeconds: nil), title: UntranslatedL10n.screenFeedComposerErrorGenericTitle),
        Refusal(error: .transport, title: UntranslatedL10n.screenFeedComposerErrorGenericTitle)
    ])
    func eachRefusalSaysWhatHappened(refusal: Refusal) {
        #expect(FeedComposerScreenViewModel.message(for: refusal.error).title == refusal.title)
    }

    @Test
    func aFeedThatIsOffSaysSoNotThatItCanBeRead() {
        let message = FeedComposerScreenViewModel.message(for: .unavailable)
        #expect(message.title == UntranslatedL10n.screenFeedUnavailableTitle)
        #expect(message.message == UntranslatedL10n.screenFeedComposerErrorUnavailableMessage)
        #expect(FeedComposerScreenViewModel.message(for: .readOnly).message == UntranslatedL10n.screenFeedComposerErrorReadOnlyMessage)
    }

    /// Only "no answer" blames the connection; a server's refusal says what it refused (L-b).
    @Test(arguments: [(FeedError.temporarilyUnavailable(retryAfterSeconds: 5), UntranslatedL10n.screenFeedComposerErrorTryShortlyMessage),
                      (.forbidden, UntranslatedL10n.screenFeedComposerErrorAccountRestrictedMessage),
                      (.server(status: 400), UntranslatedL10n.screenFeedComposerErrorNotAcceptedMessage),
                      (.unprocessable, UntranslatedL10n.screenFeedComposerErrorUnsupportedMessage),
                      (.server(status: 500), UntranslatedL10n.screenFeedComposerErrorServerMessage),
                      (.transport, UntranslatedL10n.screenFeedComposerErrorGenericMessage)])
    func aRefusalIsNotBlamedOnTheConnection(error: FeedError, message: String) {
        #expect(FeedComposerScreenViewModel.message(for: error).message == message)
        if error != .transport {
            #expect(message != UntranslatedL10n.screenFeedComposerErrorGenericMessage)
        }
    }

    /// The daily cap answers with the seconds to midnight UTC: that is said as
    /// the standing notice says it, not as ~1,440 minutes.
    @Test
    func aDailyCapSaysAfterMidnightUTC() {
        #expect(FeedComposerScreenViewModel.message(for: .rateLimited(retryAfterSeconds: 3600), dailyCap: 5).message
            == UntranslatedL10n.screenFeedComposerErrorRateLimitedMinutes(60))
        #expect(FeedComposerScreenViewModel.message(for: .rateLimited(retryAfterSeconds: 3601), dailyCap: 5).message
            == UntranslatedL10n.screenFeedComposerDailyCapNotice(5))
        #expect(FeedComposerScreenViewModel.message(for: .rateLimited(retryAfterSeconds: 86000), dailyCap: nil).message
            == UntranslatedL10n.screenFeedComposerErrorRateLimitedLater)

    }

    @Test
    func aRateLimitSaysWhenInWholeMinutes() {
        #expect(FeedComposerScreenViewModel.minutes(fromSeconds: 1) == 1)
        #expect(FeedComposerScreenViewModel.minutes(fromSeconds: 60) == 1)
        #expect(FeedComposerScreenViewModel.minutes(fromSeconds: 61) == 2)
        #expect(FeedComposerScreenViewModel.message(for: .rateLimited(retryAfterSeconds: 61)).message
            == UntranslatedL10n.screenFeedComposerErrorRateLimitedMinutes(2))
        #expect(FeedComposerScreenViewModel.message(for: .rateLimited(retryAfterSeconds: nil)).message
            == UntranslatedL10n.screenFeedComposerErrorRateLimitedLater)
    }

    // MARK: - Rules

    private static let rulesNotAccepted = FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: false,
                                                       postsPerDay: 30, postsToday: 0, suspendedUntil: nil)

    /// The rules come before the post when the standing says they are not accepted; agreeing sends it with the same key.
    @Test
    func rulesNotAcceptedShowsTheRulesAndAgreeingPostsWithTheSameKey() async throws {
        let viewModel = makeViewModel()
        await setStanding(Self.rulesNotAccepted, on: viewModel)
        let held = await sent(by: viewModel) { await viewModel.post() }
        #expect(held == nil)
        #expect(viewModel.context.isPresentingRules)
        #expect(viewModel.context.alertInfo == nil)

        service.acceptRulesVersionReturnValue = .success(Self.trusted)
        let posted = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .send(_, let key) = action { key == viewModel.idempotencyKey } else { false }
        }
        viewModel.context.send(viewAction: .acceptRules)
        try await posted.fulfill()

        #expect(!viewModel.context.isPresentingRules)
        #expect(service.acceptRulesVersionReceivedVersion == FeedRules.version)
    }

    @Test
    func aFailedAgreeKeepsTheRulesAndPostsNothing() async throws {
        let viewModel = makeViewModel()
        await setStanding(Self.rulesNotAccepted, on: viewModel)
        await viewModel.post()
        service.acceptRulesVersionReturnValue = .failure(.transport)

        var actions = 0
        let cancellable = viewModel.actionsPublisher.sink { _ in actions += 1 }
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.rulesAcceptFailed)) { $0 }
        viewModel.context.send(viewAction: .acceptRules)
        try await failed.fulfill()

        #expect(viewModel.context.isPresentingRules)
        #expect(actions == 0)
        _ = cancellable
    }

    @Test
    func notNowClosesTheRulesAndKeepsTheText() async throws {
        let viewModel = makeViewModel()
        await setStanding(Self.rulesNotAccepted, on: viewModel)
        await viewModel.post()

        viewModel.context.send(viewAction: .declineRules)

        #expect(!viewModel.context.isPresentingRules)
        #expect(viewModel.context.text == "Hello feed")
        #expect(!service.acceptRulesVersionCalled)
    }

    // MARK: - The keyboard after the rules

    /// Agreeing posts and closes the composer: the keyboard must not rise on the way out.
    @Test
    func agreeingLeavesTheKeyboardDown() async throws {
        let viewModel = makeViewModel()
        await setStanding(Self.rulesNotAccepted, on: viewModel)
        await viewModel.post()
        service.acceptRulesVersionReturnValue = .success(Self.trusted)

        let posted = deferFulfillment(viewModel.actionsPublisher) { if case .send = $0 { true } else { false } }
        viewModel.context.send(viewAction: .acceptRules)
        try await posted.fulfill()
        viewModel.context.send(viewAction: .rulesSheetDismissed)

        #expect(viewModel.context.viewState.focusEditorRequest == 0)
    }

    /// Not now keeps the composer: the keyboard comes back, once the sheet has gone.
    @Test
    func notNowBringsTheKeyboardBackOnceTheSheetHasClosed() async {
        let viewModel = makeViewModel()
        await setStanding(Self.rulesNotAccepted, on: viewModel)
        await viewModel.post()

        viewModel.context.send(viewAction: .declineRules)
        #expect(viewModel.context.viewState.focusEditorRequest == 0)

        viewModel.context.send(viewAction: .rulesSheetDismissed)
        #expect(viewModel.context.viewState.focusEditorRequest == 1)
    }

    /// A refused Agree keeps the composer too, with the text the person wrote.
    @Test
    func aRefusedAgreeBringsTheKeyboardBack() async throws {
        let viewModel = makeViewModel()
        await setStanding(Self.rulesNotAccepted, on: viewModel)
        await viewModel.post()
        service.acceptRulesVersionReturnValue = .failure(.rulesNotAccepted(currentVersion: nil))

        let closed = deferFulfillment(viewModel.context.observe(\.isPresentingRules)) { !$0 }
        viewModel.context.send(viewAction: .acceptRules)
        try await closed.fulfill()
        viewModel.context.send(viewAction: .rulesSheetDismissed)

        #expect(viewModel.context.viewState.focusEditorRequest == 1)
    }

    // MARK: - Rules versions

    @Test
    func newerRulesOnTheServerAskForAnUpdateInsteadOfTheSheet() async throws {
        let viewModel = makeViewModel()
        await setStanding(FeedStanding(rulesVersion: "2099-01-01", rulesAccepted: false, postsPerDay: 30, postsToday: 0, suspendedUntil: nil), on: viewModel)

        let sent = await sent(by: viewModel) { await viewModel.post() }

        #expect(sent == nil)
        #expect(!viewModel.context.isPresentingRules)
        #expect(viewModel.context.alertInfo?.id == .updateRequired)
        #expect(viewModel.context.text == "Hello feed")
    }

    /// The alert waits for the rules sheet to finish closing: set in the same
    /// tick as the sheet's close, SwiftUI drops it.
    @Test
    func aRefusedAgreeWithNewerRulesAsksForAnUpdateOnceTheSheetHasClosed() async throws {
        let viewModel = makeViewModel()
        await setStanding(Self.rulesNotAccepted, on: viewModel)
        await viewModel.post()
        #expect(viewModel.context.isPresentingRules)
        service.acceptRulesVersionReturnValue = .failure(.rulesNotAccepted(currentVersion: "2099-01-01"))

        let closed = deferFulfillment(viewModel.context.observe(\.isPresentingRules)) { !$0 }
        viewModel.context.send(viewAction: .acceptRules)
        try await closed.fulfill()
        #expect(viewModel.context.alertInfo == nil)

        viewModel.context.send(viewAction: .rulesSheetDismissed)
        #expect(viewModel.context.alertInfo?.id == .updateRequired)
    }

    /// Rules the server refuses without naming newer ones are not the app's
    /// fault: "Update Spiral" would send the person to an update that changes nothing.
    @Test(arguments: [String?.none, "2000-01-01", FeedRules.version])
    func aRefusedAgreeWithoutNewerRulesSaysPostingIsPaused(serverVersion: String?) async throws {
        let viewModel = makeViewModel()
        await setStanding(Self.rulesNotAccepted, on: viewModel)
        await viewModel.post()
        service.acceptRulesVersionReturnValue = .failure(.rulesNotAccepted(currentVersion: serverVersion))

        let closed = deferFulfillment(viewModel.context.observe(\.isPresentingRules)) { !$0 }
        viewModel.context.send(viewAction: .acceptRules)
        try await closed.fulfill()
        viewModel.context.send(viewAction: .rulesSheetDismissed)

        #expect(viewModel.context.alertInfo?.id == .postingPaused)
        #expect(viewModel.context.alertInfo?.message == UntranslatedL10n.screenFeedComposerRulesPausedMessage)
        #expect(viewModel.context.text == "Hello feed")
    }

    private func setStanding(_ standing: FeedStanding, on viewModel: FeedComposerScreenViewModel) async {
        service.standingReturnValue = .success(standing)
        await viewModel.loadStanding()
    }

    @Test
    func theAppsRulesAreOutdatedOnlyWhenTheServersAreNewer() {
        #expect(FeedRules.isOutdated(serverVersion: "2099-01-01"))
        #expect(!FeedRules.isOutdated(serverVersion: FeedRules.version))
        #expect(!FeedRules.isOutdated(serverVersion: "2000-01-01"))
        #expect(!FeedRules.isOutdated(serverVersion: nil))
    }

    // MARK: - Standing

    /// Decision 287: links from day one, for every tier; the composer neither warns nor holds one back.
    @Test
    func aNewAccountPostsALinkWithoutAWarning() async throws {
        service.standingReturnValue = .success(FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: true,
                                                            postsPerDay: 30, postsToday: 0, suspendedUntil: nil))
        let viewModel = makeViewModel(text: "See https://example.org")
        await viewModel.loadStanding()

        #expect(viewModel.context.viewState.canPost)
        #expect(viewModel.context.viewState.standingNotice == nil)
        #expect(await sent(by: viewModel) { await viewModel.post() }?.text == "See https://example.org")
    }

    @Test
    func theStandingSaysWhenTheDailyCapIsReachedOrPostingIsSuspended() async throws {
        service.standingReturnValue = .success(FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: true,
                                                            postsPerDay: 5, postsToday: 5, suspendedUntil: nil))
        let viewModel = makeViewModel()
        await viewModel.loadStanding()
        #expect(viewModel.context.viewState.standingNotice == UntranslatedL10n.screenFeedComposerDailyCapNotice(5))

        let until = Date.now.addingTimeInterval(3600)
        service.standingReturnValue = .success(FeedStanding(rulesVersion: FeedRules.version, rulesAccepted: true,
                                                            postsPerDay: 5, postsToday: 5, suspendedUntil: until))
        await viewModel.loadStanding()
        #expect(viewModel.context.viewState.standingNotice
            == UntranslatedL10n.screenFeedComposerSuspendedNotice(until.formatted(date: .abbreviated, time: .shortened)))

        service.standingReturnValue = .success(Self.trusted)
        await viewModel.loadStanding()
        #expect(viewModel.context.viewState.standingNotice == nil)
    }

    // MARK: - Counter

    @Test
    func theCounterShowsNearAndPastTheLimit() {
        let viewModel = makeViewModel(text: String(repeating: "a", count: 4000))
        #expect(viewModel.context.viewState.counter == nil)
        viewModel.context.text = String(repeating: "a", count: 4990)
        #expect(viewModel.context.viewState.counter == .remaining(10))
        viewModel.context.text = String(repeating: "a", count: 5003)
        #expect(viewModel.context.viewState.counter == .over(3))
    }

    @Test
    func theLengthIsCountedAsTheServerCountsIt() {
        // NFKC turns the ligature into two letters; trimming drops the spaces.
        #expect(FeedPostText.length(of: "  \u{FB01}  ") == 2)
        #expect(FeedPostText.length(of: "e\u{301}") == 1)
    }

    // MARK: - Cancel

    @Test
    func cancellingAnEmptyComposerClosesAndKeepsNothing() async throws {
        let viewModel = makeViewModel(text: " ")
        let dismissed = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismiss = action { true } else { false }
        }
        viewModel.context.send(viewAction: .cancel)
        try await dismissed.fulfill()

        #expect(service.deleteDraftCallsCount == 1)
    }

    @Test
    func cancellingWithTextAsksThenSavesTheDraftWithItsKey() async throws {
        let viewModel = makeViewModel()
        viewModel.context.send(viewAction: .cancel)
        let alert = try #require(viewModel.context.alertInfo)
        #expect(alert.id == .confirmCancel)

        let dismissed = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismiss = action { true } else { false }
        }
        alert.verticalButtons?.first?.action?()
        try await dismissed.fulfill()

        #expect(service.saveDraftReceivedDraft == FeedDraft(text: "Hello feed", idempotencyKey: viewModel.idempotencyKey))
        #expect(service.deleteDraftCallsCount == 0)
    }

    // MARK: - Draft

    @Test
    func typingKeepsTheDraftOnceTheTypingPauses() async throws {
        let viewModel = makeViewModel(text: "Hel")
        viewModel.context.send(viewAction: .textChanged)
        viewModel.context.text = "Hello"
        viewModel.context.send(viewAction: .textChanged)
        #expect(!service.saveDraftCalled)

        try await Task.sleep(for: Self.draftSaveDelay * 10)

        #expect(service.saveDraftCallsCount == 1)
        #expect(service.saveDraftReceivedDraft == FeedDraft(text: "Hello", idempotencyKey: viewModel.idempotencyKey))
    }

    @Test
    func textDeletedWhileTypingDeletesTheDraft() async throws {
        let viewModel = makeViewModel(text: " \n")
        viewModel.context.send(viewAction: .textChanged)

        try await Task.sleep(for: Self.draftSaveDelay * 10)

        #expect(!service.saveDraftCalled)
        #expect(service.deleteDraftCallsCount == 1)
    }

    /// A save still waiting when the post goes out must not bring the posted text back.
    @Test
    func aPostedTextIsNotKeptByASaveThatWasWaiting() async throws {
        let viewModel = makeViewModel()
        viewModel.context.send(viewAction: .textChanged)
        await viewModel.post()
        viewModel.stop()

        try await Task.sleep(for: Self.draftSaveDelay * 10)

        // The one kept before sending; the store deletes it once the server has the post.
        #expect(service.saveDraftCallsCount == 1)
        #expect(service.deleteDraftCallsCount == 0)
    }

    @Test
    func closingWithBlankTextDeletesTheDraft() {
        service.draftReturnValue = FeedDraft(text: "Old draft", idempotencyKey: UUID())
        let viewModel = makeViewModel(text: "  ")

        viewModel.stop()

        #expect(service.deleteDraftCallsCount == 1)
        #expect(!service.saveDraftCalled)
    }

    /// Closed from outside (a link, a tab change) before the pause: the text is kept anyway.
    @Test
    func closingWithTextKeepsItAtOnce() async throws {
        let viewModel = makeViewModel()
        viewModel.context.send(viewAction: .textChanged)

        viewModel.stop()
        #expect(service.saveDraftReceivedDraft == FeedDraft(text: "Hello feed", idempotencyKey: viewModel.idempotencyKey))

        try await Task.sleep(for: Self.draftSaveDelay * 10)
        #expect(service.saveDraftCallsCount == 1)
    }

    @Test
    func discardingDeletesTheDraft() async throws {
        let viewModel = makeViewModel()
        viewModel.context.send(viewAction: .cancel)
        let alert = try #require(viewModel.context.alertInfo)

        alert.verticalButtons?.last?.action?()
        viewModel.stop()

        #expect(service.deleteDraftCallsCount == 1)
        #expect(!service.saveDraftCalled)
    }
}
