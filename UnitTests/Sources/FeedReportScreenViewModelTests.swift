//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The report screen (lane I3 on B4): the
// receipt shows only once the server gave it, an open report's receipt is
// shown as such, a double tap sends once, and a refusal keeps the form.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedReportScreenViewModelTests {
    private let service = FeedServiceMock()
    private static let receipt = FeedReportReceipt(reportID: "01933f2c-0000-7000-8000-000000000001",
                                                   deadline: Date(timeIntervalSince1970: 1_793_203_200),
                                                   isExisting: false)

    private func viewModel(_ target: FeedReportTarget = .post(id: "01933f2a-0000-7000-8000-000000000001")) -> FeedReportScreenViewModel {
        FeedReportScreenViewModel(target: target, feedService: service)
    }

    @Test
    func nothingIsSentWithoutARule() async {
        let viewModel = viewModel()
        #expect(!viewModel.context.viewState.canSend)

        await viewModel.send()

        #expect(service.reportReasonDetailCallsCount == 0)
    }

    /// Never show success before the server says so.
    @Test
    func theReceiptShowsOnlyOnceTheServerGaveIt() async {
        let viewModel = viewModel(.comment(id: "01933f2b-0000-7000-8000-000000000001"))
        var receiptWhileSending: FeedReportReceipt?
        service.reportReasonDetailClosure = { _, _, _ in
            receiptWhileSending = viewModel.context.viewState.receipt
            return .success(Self.receipt)
        }
        viewModel.context.send(viewAction: .selectReason(.harassment))
        viewModel.context.detail = "  Keeps insulting me  "

        await viewModel.send()

        #expect(receiptWhileSending == nil)
        #expect(viewModel.context.viewState.receipt == Self.receipt)
        #expect(!viewModel.context.viewState.isSending)
        let arguments = service.reportReasonDetailReceivedArguments
        #expect(arguments?.target == .comment(id: "01933f2b-0000-7000-8000-000000000001"))
        #expect(arguments?.reason == .harassment)
        #expect(arguments?.detail == "Keeps insulting me")
    }

    /// The person's open report answers its receipt again: shown as "already reported", not an error.
    @Test
    func anOpenReportShowsItsReceipt() async {
        let existing = FeedReportReceipt(reportID: Self.receipt.reportID, deadline: Self.receipt.deadline, isExisting: true)
        service.reportReasonDetailReturnValue = .success(existing)
        let viewModel = viewModel(.author(userID: "@ann:spiral.md"))
        viewModel.context.send(viewAction: .selectReason(.impersonation))

        await viewModel.send()

        #expect(viewModel.context.viewState.receipt?.isExisting == true)
        #expect(viewModel.context.alertInfo == nil)
        #expect(service.reportReasonDetailReceivedArguments?.detail == nil)
    }

    /// A double tap on Send must never send twice.
    @Test
    func aSecondTapWhileSendingSendsNothing() async {
        let viewModel = viewModel()
        viewModel.context.send(viewAction: .selectReason(.spam))
        service.reportReasonDetailClosure = { _, _, _ in
            await viewModel.send()
            return .success(Self.receipt)
        }

        await viewModel.send()

        #expect(service.reportReasonDetailCallsCount == 1)
    }

    /// 10 a day: nothing was filed, the form stays to send later, and the message names the wait.
    @Test
    func theDailyCapKeepsTheForm() async {
        service.reportReasonDetailReturnValue = .failure(.rateLimited(retryAfterSeconds: 5400))
        let viewModel = viewModel()
        viewModel.context.send(viewAction: .selectReason(.spam))
        viewModel.context.detail = "Same link everywhere"

        await viewModel.send()

        #expect(viewModel.context.viewState.receipt == nil)
        #expect(viewModel.context.alertInfo?.id == .rateLimited)
        #expect(viewModel.context.alertInfo?.message == UntranslatedL10n.screenFeedReportRateLimitedMessageHours(2))
        #expect(viewModel.context.detail == "Same link everywhere")
        #expect(viewModel.context.viewState.canSend)
    }

    /// Decision 276: a suspended person is told why, and the form stays as it was.
    @Test
    func aSuspensionKeepsTheFormAndSaysWhy() async {
        service.reportReasonDetailReturnValue = .failure(.suspended)
        let viewModel = viewModel()
        viewModel.context.send(viewAction: .selectReason(.spam))

        await viewModel.send()

        #expect(viewModel.context.viewState.receipt == nil)
        #expect(viewModel.context.alertInfo?.id == .suspended)
        #expect(viewModel.context.alertInfo?.message == UntranslatedL10n.screenFeedReportSuspendedMessage)
        #expect(viewModel.context.viewState.canSend)
    }

    @Test
    func aRateLimitWithoutRetryAfterNamesNoTime() {
        #expect(FeedReportScreenViewModel.rateLimitMessage(retryAfterSeconds: nil) == UntranslatedL10n.screenFeedReportRateLimitedMessage)
        #expect(FeedReportScreenViewModel.rateLimitMessage(retryAfterSeconds: 60) == UntranslatedL10n.screenFeedReportRateLimitedMessageHours(1))
    }

    /// Only the feed's own 404 closes the form, after the person read why.
    @Test
    func whatIsGoneClosesTheFormAndAnyOtherFailureDoesNot() async {
        let viewModel = viewModel()
        var dismissed = 0
        let cancellable = viewModel.actionsPublisher.sink { if case .dismiss = $0 { dismissed += 1 } }
        viewModel.context.send(viewAction: .selectReason(.hate))

        service.reportReasonDetailReturnValue = .failure(.server(status: 500))
        await viewModel.send()
        #expect(viewModel.context.alertInfo?.id == .failed)
        viewModel.context.alertInfo?.primaryButton.action?()
        #expect(dismissed == 0)

        service.reportReasonDetailReturnValue = .failure(.notFound)
        await viewModel.send()
        #expect(viewModel.context.alertInfo?.id == .notAvailable)
        viewModel.context.alertInfo?.primaryButton.action?()
        #expect(dismissed == 1)
        #expect(viewModel.context.viewState.receipt == nil)
        _ = cancellable
    }

    @Test
    func aNoteOverTheLimitIsNotSent() async {
        let viewModel = viewModel()
        viewModel.context.send(viewAction: .selectReason(.other))
        viewModel.context.detail = String(repeating: "a", count: FeedReportText.maximumLength + 1)

        #expect(!viewModel.context.viewState.canSend)
        await viewModel.send()
        #expect(service.reportReasonDetailCallsCount == 0)
    }

    /// A person is never held by reports (decision 269): their form does not say it hides at once.
    @Test
    func onlyPostsAndCommentsSayASevereReportHidesAtOnce() {
        #expect(viewModel(.post(id: "p")).context.viewState.severeFooter != nil)
        #expect(viewModel(.comment(id: "c")).context.viewState.severeFooter != nil)
        #expect(viewModel(.author(userID: "@ann:spiral.md")).context.viewState.severeFooter == nil)
        #expect(FeedReportReason.severe == [.childSafety, .threatToLife, .privateInformation])
    }

    /// Regulated goods sit among the others, after illegal content as the server lists them; a report holds nothing at once.
    @Test
    func regulatedGoodsIsAnOrdinaryReasonAfterIllegal() async {
        #expect(FeedReportReason.others.starts(with: [.illegal, .regulatedGoods, .sexualContent]))
        #expect(!FeedReportReason.regulatedGoods.isSevere)
        #expect(FeedReportReason.regulatedGoods.title == UntranslatedL10n.screenFeedReportReasonRegulatedGoods)
        #expect(FeedReportReason.regulatedGoods.subtitle == nil)

        service.reportReasonDetailReturnValue = .success(Self.receipt)
        let viewModel = viewModel()
        viewModel.context.send(viewAction: .selectReason(.regulatedGoods))
        #expect(viewModel.context.viewState.canSend)
        await viewModel.send()
        #expect(service.reportReasonDetailReceivedArguments?.reason == .regulatedGoods)
    }

    /// Logs carry ids, never a person's MXID.
    @Test
    func aTargetLogsNoMXID() {
        #expect(String(describing: FeedReportTarget.author(userID: "@ann:spiral.md")) == "author")
        #expect(String(describing: FeedReportTarget.post(id: "p1")) == "post p1")
    }
}
