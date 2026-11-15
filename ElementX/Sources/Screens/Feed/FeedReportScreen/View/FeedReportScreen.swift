//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082).
//

import Compound
import SwiftUI

struct FeedReportScreen: View {
    @Bindable var context: FeedReportScreenViewModel.Context

    var body: some View {
        content
            .navigationTitle(context.viewState.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert(item: $context.alertInfo)
            .interactiveDismissDisabled(context.viewState.isSending)
    }

    @ViewBuilder
    private var content: some View {
        if let receipt = context.viewState.receipt {
            FeedReportReceiptView(receipt: receipt)
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                reasonRows(FeedReportReason.severe)
            } header: {
                Text(UntranslatedL10n.screenFeedReportSevereHeader)
                    .compoundListSectionHeader()
            } footer: {
                if let footer = context.viewState.severeFooter {
                    Text(footer)
                        .compoundListSectionFooter()
                }
            }

            Section {
                reasonRows(FeedReportReason.others)
            } header: {
                Text(UntranslatedL10n.screenFeedReportOtherHeader)
                    .compoundListSectionHeader()
            }

            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenFeedReportDetailPlaceholder),
                        kind: .textField(text: $context.detail, axis: .vertical))
                    .lineLimit(4, reservesSpace: true)
                    .accessibilityIdentifier(A11yIdentifiers.feedReportScreen.detail)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let counter = context.viewState.detailCounter {
                        Text(counter)
                            .foregroundStyle(context.viewState.detailLength > FeedReportText.maximumLength ? .compound.textCriticalPrimary : .compound.textSecondary)
                    }
                    Text(UntranslatedL10n.screenFeedReportDetailFooter)
                }
                .compoundListSectionFooter()
            }
        }
        .spiralGroupedList() // Brief 0083: Settings' grouped cards (337).
        .disabled(context.viewState.isSending)
    }

    private func reasonRows(_ reasons: [FeedReportReason]) -> some View {
        ForEach(reasons) { reason in
            ListRow(label: .plain(title: reason.title, description: reason.subtitle),
                    kind: .selection(isSelected: context.viewState.reason == reason) {
                        context.send(viewAction: .selectReason(reason))
                    })
                    .accessibilityIdentifier(A11yIdentifiers.feedReportScreen.reason(reason.rawValue))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if context.viewState.receipt != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.actionDone) { context.send(viewAction: .dismiss) }
                    .accessibilityIdentifier(A11yIdentifiers.feedReportScreen.done)
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.actionCancel) { context.send(viewAction: .dismiss) }
                    .disabled(context.viewState.isSending)
            }
            ToolbarItem(placement: .confirmationAction) {
                if context.viewState.isSending {
                    ProgressView()
                        .accessibilityLabel(UntranslatedL10n.screenFeedReportSending)
                } else {
                    Button(UntranslatedL10n.screenFeedReportSend) { context.send(viewAction: .send) }
                        .disabled(!context.viewState.canSend)
                        .accessibilityIdentifier(A11yIdentifiers.feedReportScreen.send)
                }
            }
        }
    }
}

/// The receipt (Art. 16(4)): the report is in, and when a moderator decides by.
private struct FeedReportReceiptView: View {
    let receipt: FeedReportReceipt

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BigIcon(icon: \.checkCircle, style: .successSolid)
                    .accessibilityHidden(true)
                Text(receipt.isExisting ? UntranslatedL10n.screenFeedReportExistingTitle : UntranslatedL10n.screenFeedReportSentTitle)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(receiptMessage)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .accessibilityIdentifier(A11yIdentifiers.feedReportScreen.receipt)
    }

    private var receiptMessage: String {
        let deadline = receipt.deadline.formatted(date: .abbreviated, time: .shortened)
        return receipt.isExisting ? UntranslatedL10n.screenFeedReportExistingMessage(deadline) : UntranslatedL10n.screenFeedReportSentMessage(deadline)
    }
}

// MARK: - Previews

struct FeedReportScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let deadline = Date(timeIntervalSince1970: 1_793_116_800) // 27 Oct 2026, 00:00 UTC.

    static let postViewModel = makeViewModel(.post(id: "01933f2a-0000-7000-8000-000000000001"))
    static let authorViewModel = makeViewModel(.author(userID: "@ann:spiral.md"))
    static let filledViewModel = makeViewModel(.comment(id: "01933f2b-0000-7000-8000-000000000001"),
                                               reason: .harassment,
                                               detail: "Keeps replying to everything I post with insults.")
    static let sendingViewModel = makeViewModel(.post(id: "01933f2a-0000-7000-8000-000000000001"), reason: .spam, isSending: true)
    static let receiptViewModel = makeViewModel(.post(id: "01933f2a-0000-7000-8000-000000000001"),
                                                receipt: FeedReportReceipt(reportID: "01933f2c-0000-7000-8000-000000000001", deadline: deadline, isExisting: false))
    static let existingViewModel = makeViewModel(.author(userID: "@ann:spiral.md"),
                                                 receipt: FeedReportReceipt(reportID: "01933f2c-0000-7000-8000-000000000001", deadline: deadline, isExisting: true))

    static var previews: some View {
        preview(postViewModel, name: "Post")
        preview(authorViewModel, name: "Author")
        preview(filledViewModel, name: "Filled")
        preview(sendingViewModel, name: "Sending")
        preview(receiptViewModel, name: "Receipt")
        preview(existingViewModel, name: "Already reported")
        preview(receiptViewModel, name: "Receipt AX5")
            .dynamicTypeSize(.accessibility5)
    }

    private static func preview(_ viewModel: FeedReportScreenViewModel, name: String) -> some View {
        ElementNavigationStack {
            FeedReportScreen(context: viewModel.context)
        }
        .previewDisplayName(name)
    }

    static func makeViewModel(_ target: FeedReportTarget,
                              reason: FeedReportReason? = nil,
                              detail: String = "",
                              isSending: Bool = false,
                              receipt: FeedReportReceipt? = nil) -> FeedReportScreenViewModel {
        let viewModel = FeedReportScreenViewModel(target: target, feedService: FeedServiceMock())
        viewModel.state.reason = reason
        viewModel.state.bindings.detail = detail
        viewModel.state.isSending = isSending
        viewModel.state.receipt = receipt
        return viewModel
    }
}
