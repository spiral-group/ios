//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A composer session owns one idempotency
// key: every retry, the one after the rules are accepted, and a draft restored
// after the app closed mid-post send the same key, so the server answers the
// post it already made instead of making a second one. Posting closes the
// sheet: the store sends the post and shows it as sending, and a refusal stays
// on it with Retry (decision 289); the messages for refusals live here.
//

import Combine
import SwiftUI

typealias FeedComposerScreenViewModelType = StateStoreViewModelV2<FeedComposerScreenViewState, FeedComposerScreenViewAction>

protocol FeedComposerScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<FeedComposerScreenViewModelAction, Never> { get }
    var context: FeedComposerScreenViewModelType.Context { get }
    /// The composer is gone, however it was closed.
    func stop()
}

class FeedComposerScreenViewModel: FeedComposerScreenViewModelType, FeedComposerScreenViewModelProtocol {
    /// A `429` waiting longer than this is the daily cap, which ends at midnight UTC.
    static let dailyCapRetryThreshold = 3600

    private let feedService: FeedServiceProtocol
    private let draftSaveDelay: Duration
    private(set) var idempotencyKey: UUID

    private var draftSaveTask: Task<Void, Never>?
    /// Posted or closed through Cancel: the draft is settled and nothing may bring it back.
    private var isFinished = false
    /// From the sheet's presentation until its `onDismiss`, which runs after it has closed.
    private var isRulesSheetOnScreen = false
    /// An alert raised while the rules sheet was on screen, shown once it has closed.
    private var pendingAlert: AlertInfo<FeedComposerScreenAlertType>?
    /// The rules were accepted in this session: a further `409` must not show them again.
    private var hasAcceptedRules = false

    private let actionsSubject: PassthroughSubject<FeedComposerScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedComposerScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(feedService: FeedServiceProtocol,
         clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         draftSaveDelay: Duration = .seconds(1)) {
        self.feedService = feedService
        self.draftSaveDelay = draftSaveDelay
        let draft = feedService.draft()
        idempotencyKey = draft?.idempotencyKey ?? UUID()

        var initialState = FeedComposerScreenViewState(ownProfile: clientProxy.userProfilePublisher.value)
        initialState.bindings.text = draft?.text ?? ""
        super.init(initialViewState: initialState, mediaProvider: mediaProvider)

        clientProxy.userProfilePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.state.ownProfile = profile
            }
            .store(in: &cancellables)

        Task { await loadStanding() }
    }

    /// The rules, the cap and a suspension the composer shows; unread, the server still decides.
    func loadStanding() async {
        switch await FeedReadWindow.retryingOnce({ [feedService] in await feedService.standing() }) {
        case .success(let standing):
            state.standing = standing
        case .failure(let error):
            MXLog.info("Could not read the feed standing: \(error)")
        }
    }

    override func process(viewAction: FeedComposerScreenViewAction) {
        switch viewAction {
        case .post:
            Task { await post() }
        case .cancel:
            cancel()
        case .acceptRules:
            Task { await acceptRules() }
        case .declineRules:
            state.bindings.isPresentingRules = false
            state.rulesAcceptFailed = false
        case .rulesSheetDismissed:
            isRulesSheetOnScreen = false
            if !isFinished {
                state.focusEditorRequest += 1
            }
            if let pendingAlert {
                self.pendingAlert = nil
                state.bindings.alertInfo = pendingAlert
            }
        case .textChanged:
            scheduleDraftSave()
        }
    }

    // MARK: - Posting

    /// The rules first when the standing says they are not accepted; then the
    /// sheet closes and the post shows at once as sending, with this key.
    func post() async {
        guard state.canPost else { return }
        if let standing = state.standing, !standing.rulesAccepted, !hasAcceptedRules {
            if FeedRules.isOutdated(serverVersion: standing.rulesVersion) {
                showUpdateRequired()
            } else {
                state.rulesAcceptFailed = false
                isRulesSheetOnScreen = true
                state.bindings.isPresentingRules = true
            }
            return
        }
        send()
    }

    private func send() {
        let text = state.bindings.text
        draftSaveTask?.cancel()
        isFinished = true
        // Kept until the server has the post: if the app closes before the
        // answer, the restored draft replays this key instead of posting twice.
        feedService.saveDraft(FeedDraft(text: text, idempotencyKey: idempotencyKey))
        actionsSubject.send(.send(text: text, idempotencyKey: idempotencyKey))
    }

    /// What the person is told for each refusal; anything the app does not know is the generic one.
    static func message(for error: FeedError, dailyCap: Int? = nil) -> (title: String, message: String) {
        switch error {
        case .linkRefused:
            (UntranslatedL10n.screenFeedComposerErrorLinkRefusedTitle, UntranslatedL10n.screenFeedComposerErrorLinkRefusedMessage)
        case .duplicate:
            (UntranslatedL10n.screenFeedComposerErrorDuplicateTitle, UntranslatedL10n.screenFeedComposerErrorDuplicateMessage)
        case .suspended:
            (UntranslatedL10n.screenFeedComposerErrorSuspendedTitle, UntranslatedL10n.screenFeedComposerErrorSuspendedMessage)
        case .rateLimited(let seconds?) where seconds > dailyCapRetryThreshold:
            (UntranslatedL10n.screenFeedComposerErrorRateLimitedTitle,
             dailyCap.map(UntranslatedL10n.screenFeedComposerDailyCapNotice) ?? UntranslatedL10n.screenFeedComposerErrorRateLimitedLater)
        case .rateLimited(let seconds):
            (UntranslatedL10n.screenFeedComposerErrorRateLimitedTitle,
             seconds.map { UntranslatedL10n.screenFeedComposerErrorRateLimitedMinutes(Self.minutes(fromSeconds: $0)) } ?? UntranslatedL10n.screenFeedComposerErrorRateLimitedLater)
        case .readOnly:
            (UntranslatedL10n.screenFeedComposerErrorReadOnlyTitle, UntranslatedL10n.screenFeedComposerErrorReadOnlyMessage)
        case .unavailable:
            (UntranslatedL10n.screenFeedUnavailableTitle, UntranslatedL10n.screenFeedComposerErrorUnavailableMessage)
        case .idempotencyKeyReused:
            (UntranslatedL10n.screenFeedComposerErrorKeyReusedTitle, UntranslatedL10n.screenFeedComposerErrorKeyReusedMessage)
        case .temporarilyUnavailable:
            (UntranslatedL10n.screenFeedComposerErrorGenericTitle, UntranslatedL10n.screenFeedComposerErrorTryShortlyMessage)
        case .forbidden:
            // Synapse does not show the account (locked or suspended there).
            (UntranslatedL10n.screenFeedComposerErrorSuspendedTitle, UntranslatedL10n.screenFeedComposerErrorAccountRestrictedMessage)
        case .server(status: 400):
            (UntranslatedL10n.screenFeedComposerErrorGenericTitle, UntranslatedL10n.screenFeedComposerErrorNotAcceptedMessage)
        case .unprocessable:
            (UntranslatedL10n.screenFeedComposerErrorGenericTitle, UntranslatedL10n.screenFeedComposerErrorUnsupportedMessage)
        case .transport:
            (UntranslatedL10n.screenFeedComposerErrorGenericTitle, UntranslatedL10n.screenFeedComposerErrorGenericMessage)
        default:
            // The server answered: the connection is not to blame.
            (UntranslatedL10n.screenFeedComposerErrorGenericTitle, UntranslatedL10n.screenFeedComposerErrorServerMessage)
        }
    }

    /// Whole minutes, rounded up, at least one.
    static func minutes(fromSeconds seconds: Int) -> Int {
        max(1, (seconds + 59) / 60)
    }

    // MARK: - Rules

    private func acceptRules() async {
        guard !state.isAcceptingRules else { return }
        state.isAcceptingRules = true
        state.rulesAcceptFailed = false

        let result = await feedService.acceptRules(version: FeedRules.version)
        state.isAcceptingRules = false

        switch result {
        case .success(let standing):
            hasAcceptedRules = true
            state.standing = standing
            state.bindings.isPresentingRules = false
            send()
        case .failure(.rulesNotAccepted(let currentVersion)):
            state.bindings.isPresentingRules = false
            if FeedRules.isOutdated(serverVersion: currentVersion) {
                // Only an update brings the server's newer rules.
                showUpdateRequired()
            } else {
                // The server's rules are older or unnamed (mid-deploy): an update would change nothing.
                showPostingPaused()
            }
        case .failure(let error):
            MXLog.error("Failed to accept the feed rules: \(error)")
            state.rulesAcceptFailed = true
        }
    }

    private func showUpdateRequired() {
        present(.init(id: .updateRequired,
                      title: UntranslatedL10n.screenFeedComposerUpdateRequiredTitle,
                      message: UntranslatedL10n.screenFeedComposerUpdateRequiredMessage))
    }

    private func showPostingPaused() {
        present(.init(id: .postingPaused,
                      title: UntranslatedL10n.screenFeedComposerErrorReadOnlyTitle,
                      message: UntranslatedL10n.screenFeedComposerRulesPausedMessage))
    }

    /// An alert set while the rules sheet is still closing is dropped by
    /// SwiftUI, so it waits for the sheet's `onDismiss`.
    private func present(_ alert: AlertInfo<FeedComposerScreenAlertType>) {
        if isRulesSheetOnScreen {
            pendingAlert = alert
        } else {
            state.bindings.alertInfo = alert
        }
    }

    // MARK: - Draft

    /// Kept a moment after the typing pauses, so a crash or a kill loses at most that moment.
    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self, draftSaveDelay] in
            try? await Task.sleep(for: draftSaveDelay)
            guard !Task.isCancelled else { return }
            self?.keepDraft()
        }
    }

    /// Blank text is no draft: one kept earlier must not come back.
    private func keepDraft() {
        guard !isFinished else { return }
        if Self.isBlank(state.bindings.text) {
            feedService.deleteDraft()
        } else {
            feedService.saveDraft(FeedDraft(text: state.bindings.text, idempotencyKey: idempotencyKey))
        }
    }

    func stop() {
        draftSaveTask?.cancel()
        // Closed from outside (a link, a swipe on blank text): the text as it is now.
        keepDraft()
        isFinished = true
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Cancel

    private func cancel() {
        guard !Self.isBlank(state.bindings.text) else {
            close(keepingDraft: false)
            return
        }

        state.bindings.alertInfo = .init(id: .confirmCancel,
                                         title: UntranslatedL10n.screenFeedComposerCancelTitle,
                                         message: UntranslatedL10n.screenFeedComposerCancelMessage,
                                         primaryButton: .init(title: UntranslatedL10n.screenFeedComposerKeepEditing, role: .cancel, action: nil),
                                         verticalButtons: [
                                             .init(title: UntranslatedL10n.screenFeedComposerSaveDraft) { [weak self] in self?.close(keepingDraft: true) },
                                             .init(title: UntranslatedL10n.screenFeedComposerDiscard, role: .destructive) { [weak self] in self?.close(keepingDraft: false) }
                                         ])
    }

    private func close(keepingDraft: Bool) {
        draftSaveTask?.cancel()
        isFinished = true
        if keepingDraft {
            feedService.saveDraft(FeedDraft(text: state.bindings.text, idempotencyKey: idempotencyKey))
        } else {
            feedService.deleteDraft()
        }
        actionsSubject.send(.dismiss)
    }
}
