//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

typealias FeedReportScreenViewModelType = StateStoreViewModelV2<FeedReportScreenViewState, FeedReportScreenViewAction>

protocol FeedReportScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<FeedReportScreenViewModelAction, Never> { get }
    var context: FeedReportScreenViewModelType.Context { get }
}

class FeedReportScreenViewModel: FeedReportScreenViewModelType, FeedReportScreenViewModelProtocol {
    private let feedService: FeedServiceProtocol

    private let actionsSubject: PassthroughSubject<FeedReportScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<FeedReportScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(target: FeedReportTarget, feedService: FeedServiceProtocol) {
        self.feedService = feedService
        super.init(initialViewState: FeedReportScreenViewState(target: target))
    }

    override func process(viewAction: FeedReportScreenViewAction) {
        switch viewAction {
        case .selectReason(let reason):
            guard !state.isSending, state.receipt == nil else { return }
            state.reason = reason
        case .send:
            Task { await send() }
        case .dismiss:
            actionsSubject.send(.dismiss)
        }
    }

    /// One report in flight: a second tap waits for the first answer, and
    /// the receipt shows only once the server has given it.
    func send() async {
        guard state.canSend, let reason = state.reason else { return }
        state.isSending = true
        defer { state.isSending = false }

        let detail = state.bindings.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        switch await feedService.report(state.target, reason: reason, detail: detail.isEmpty ? nil : detail) {
        case .success(let receipt):
            state.receipt = receipt
        case .failure(let error):
            state.bindings.alertInfo = Self.alert(for: error) { [weak self] in
                self?.actionsSubject.send(.dismiss)
            }
        }
    }

    /// A refusal keeps the form as it was, so the person can send it again;
    /// only "not there" closes it.
    static func alert(for error: FeedError, dismiss: @escaping () -> Void) -> AlertInfo<FeedReportScreenAlertType> {
        switch error {
        case .rateLimited(let seconds):
            return .init(id: .rateLimited,
                         title: UntranslatedL10n.screenFeedReportRateLimitedTitle,
                         message: rateLimitMessage(retryAfterSeconds: seconds))
        case .notFound:
            return .init(id: .notAvailable,
                         title: UntranslatedL10n.screenFeedReportNotAvailableTitle,
                         message: UntranslatedL10n.screenFeedReportNotAvailableMessage,
                         primaryButton: .init(title: L10n.actionOk, action: dismiss))
        case .suspended:
            return .init(id: .suspended,
                         title: UntranslatedL10n.screenFeedReportSuspendedTitle,
                         message: UntranslatedL10n.screenFeedReportSuspendedMessage)
        case .unavailable:
            return .init(id: .failed,
                         title: UntranslatedL10n.screenFeedReportFailedTitle,
                         message: UntranslatedL10n.screenFeedUnavailableMessage)
        default:
            return .init(id: .failed,
                         title: UntranslatedL10n.screenFeedReportFailedTitle,
                         message: error.actionFailedMessage)
        }
    }

    /// `Retry-After` is the seconds to the next UTC midnight; without it the message names no time.
    static func rateLimitMessage(retryAfterSeconds: Int?) -> String {
        guard let retryAfterSeconds, retryAfterSeconds > 0 else { return UntranslatedL10n.screenFeedReportRateLimitedMessage }
        let hours = max(1, Int((Double(retryAfterSeconds) / 3600).rounded(.up)))
        return UntranslatedL10n.screenFeedReportRateLimitedMessageHours(hours)
    }
}
