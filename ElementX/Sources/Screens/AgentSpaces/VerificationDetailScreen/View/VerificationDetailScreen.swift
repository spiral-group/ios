//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreen.swift`.
//
// Layout adapted from upstream `SessionVerificationScreen`:
// FullscreenDialog with BigIcon + title + message header, 4+3
// emoji grid in the middle, two action buttons at the bottom.
// The agent-proxy variant adds an out-of-band-warning banner
// above the grid (the agent itself can't compare emojis — the
// owner must do so over an independent channel) and binds the
// buttons to our REST `/confirm` + `/reject` endpoints instead
// of the upstream SDK delegate.

import Compound
import SwiftUI

struct VerificationDetailScreen: View {
    @Bindable var context: VerificationDetailScreenViewModel.Context

    var body: some View {
        FullscreenDialog {
            VStack(spacing: 32) {
                header
                content
            }
        } bottomContent: {
            actionButtons
        }
        .background()
        .backgroundStyle(.compound.bgCanvasDefault)
        .navigationTitle(UntranslatedL10n.screenVerificationDetailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .onAppear { context.send(viewAction: .appeared) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            BigIcon(icon: headerIcon.keyPath, style: headerIcon.style)
            VStack(spacing: 8) {
                Text(headerTitle)
                    .font(.compound.headingMDBold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.compound.textPrimary)
                Text(headerSubtitle)
                    .font(.compound.bodyMD)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.compound.textSecondary)
            }
            requesterRow
        }
    }

    /// The MXID + optional device id; rendered as a small chip
    /// directly under the header copy so the user can confirm
    /// "yes, this is the request I'm expecting" before clicking
    /// They Match.
    @ViewBuilder
    private var requesterRow: some View {
        if !context.viewState.requesterUserID.isEmpty {
            VStack(spacing: 2) {
                Text(context.viewState.requesterUserID)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textPrimary)
                if let deviceID = context.viewState.requesterDeviceID,
                   !deviceID.isEmpty {
                    Text(deviceID)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .monospaced()
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color.compound.bgSubtleSecondary, in: Capsule())
        }
    }

    private var headerIcon: (keyPath: KeyPath<CompoundIcons, Image>, style: BigIcon.Style) {
        switch context.viewState.detailState {
        case .readyForReview, .confirming, .rejecting:
            return (\.reaction, .defaultSolid)
        case .awaitingRemoteDone, .confirmed:
            return (\.checkCircleSolid, .successSolid)
        case .rejected, .cancelled, .failed:
            return (\.infoSolid, .alertSolid)
        case .loading, .waitingForEmojis:
            return (\.lockSolid, .defaultSolid)
        }
    }

    private var headerTitle: String {
        switch context.viewState.detailState {
        case .loading:
            return UntranslatedL10n.screenVerificationDetailLoadingTitle
        case .waitingForEmojis:
            return UntranslatedL10n.screenVerificationDetailWaitingTitle
        case .readyForReview, .confirming, .rejecting:
            return UntranslatedL10n.screenVerificationDetailCompareTitle
        case .awaitingRemoteDone:
            return UntranslatedL10n.screenVerificationDetailAwaitingTitle
        case .confirmed:
            return UntranslatedL10n.screenVerificationDetailConfirmedTitle
        case .rejected, .cancelled:
            return UntranslatedL10n.screenVerificationDetailCancelledTitle
        case .failed:
            return L10n.commonError
        }
    }

    private var headerSubtitle: String {
        switch context.viewState.detailState {
        case .loading:
            return UntranslatedL10n.screenVerificationDetailLoadingSubtitle
        case .waitingForEmojis:
            return UntranslatedL10n.screenVerificationDetailWaitingSubtitle
        case .readyForReview, .confirming, .rejecting:
            return UntranslatedL10n.screenVerificationDetailCompareSubtitle
        case .awaitingRemoteDone:
            return UntranslatedL10n.screenVerificationDetailAwaitingSubtitle
        case .confirmed:
            return UntranslatedL10n.screenVerificationDetailConfirmedSubtitle
        case .rejected:
            return UntranslatedL10n.screenVerificationDetailRejectedSubtitle
        case .cancelled(let reason):
            // Fall through to a generic copy if the backend
            // didn't supply a cancel_code (e.g. timeout path).
            // Avoid surfacing raw machine codes ("m.mac",
            // "m.timeout") — they're diagnostic, not for users.
            if reason != nil {
                return UntranslatedL10n.screenVerificationDetailCancelledRemoteSubtitle
            }
            return UntranslatedL10n.screenVerificationDetailCancelledSubtitle
        case .failed(let reason):
            return reason
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var content: some View {
        switch context.viewState.detailState {
        case .readyForReview(let emojis),
             .confirming(let emojis),
             .rejecting(let emojis):
            VStack(spacing: 24) {
                warningBanner
                emojisPanel(with: emojis)
            }
        case .loading, .waitingForEmojis:
            ProgressView()
                .controlSize(.large)
                .padding(.vertical, 32)
        default:
            EmptyView()
        }
    }

    /// Out-of-band-comparison warning. The strict-SAS gate
    /// lives HERE (banner copy) and in the button label, NOT
    /// in a separate checkbox. Matches upstream Element X UX
    /// for cross-signing — see `SessionVerificationScreen`.
    /// The backend's `comparison_acknowledged: true` wire flag
    /// is the paranoia belt-and-braces underneath; the user-
    /// visible contract is "tap They Match only after you've
    /// actually compared".
    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            CompoundIcon(\.infoSolid, size: .small, relativeTo: .compound.bodyMD)
                .foregroundStyle(.compound.iconTertiary)
            Text(UntranslatedL10n.screenVerificationDetailWarning)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.compound.bgSubtleSecondary,
                    // swiftlint:disable:next spiral_raw_corner_radius - predates the rule
                    in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    /// 4+3 emoji grid. Same shape as upstream
    /// `SessionVerificationScreen.emojisPanel` so users get a
    /// consistent layout regardless of whether they verify a
    /// human (Element X native) or an agent (our screen).
    private func emojisPanel(with emojis: [VerificationEmoji]) -> some View {
        VStack(spacing: 32) {
            HStack(spacing: 16) {
                ForEach(emojis.prefix(4), id: \.self) { emoji in
                    EmojiView(emoji: emoji)
                }
            }
            HStack(spacing: 16) {
                ForEach(emojis.suffix(from: 4), id: \.self) { emoji in
                    EmojiView(emoji: emoji)
                }
            }
        }
    }

    // MARK: - Action buttons

    @ViewBuilder
    private var actionButtons: some View {
        switch context.viewState.detailState {
        case .readyForReview, .confirming, .rejecting:
            VStack(spacing: 16) {
                confirmButton
                rejectButton
            }
        case .loading, .waitingForEmojis:
            Button(L10n.actionRetry) { context.send(viewAction: .refresh) }
                .buttonStyle(.compound(.secondary))
                .disabled(context.viewState.detailState.isInFlight)
        case .awaitingRemoteDone, .confirmed, .rejected, .cancelled:
            Button(L10n.actionDone) { context.send(viewAction: .done) }
                .buttonStyle(.compound(.primary))
        case .failed:
            VStack(spacing: 16) {
                Button(L10n.actionRetry) { context.send(viewAction: .refresh) }
                    .buttonStyle(.compound(.primary))
                Button(L10n.actionDismiss) { context.send(viewAction: .done) }
                    .buttonStyle(.compound(.tertiary))
            }
        }
    }

    private var confirmButton: some View {
        Button {
            context.send(viewAction: .confirm)
        } label: {
            Label {
                Text(UntranslatedL10n.screenVerificationDetailActionMatch)
            } icon: {
                if case .confirming = context.viewState.detailState {
                    ProgressView()
                        .tint(.compound.iconOnSolidPrimary)
                }
            }
        }
        .buttonStyle(.compound(.primary))
        .disabled(context.viewState.detailState.isInFlight)
    }

    private var rejectButton: some View {
        Button {
            context.send(viewAction: .reject)
        } label: {
            Label {
                Text(UntranslatedL10n.screenVerificationDetailActionMismatch)
            } icon: {
                if case .rejecting = context.viewState.detailState {
                    ProgressView()
                }
            }
        }
        .buttonStyle(.compound(.tertiary))
        .disabled(context.viewState.detailState.isInFlight)
    }

    // MARK: - Emoji cell

    /// Local copy of the upstream
    /// `SessionVerificationScreen.EmojiView` recipe — same
    /// padding, font, and a11y `combine` behaviour. Inlined
    /// rather than reused because upstream's version is
    /// fileprivate.
    struct EmojiView: View {
        let emoji: VerificationEmoji

        var body: some View {
            VStack(spacing: 16) {
                Text(emoji.symbol)
                    .font(.compound.headingXLBold)
                    .accessibilityHidden(true)
                Text(SASL10n.localizedDescription(for: emoji.description.lowercased())
                    .capitalized)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .padding(8)
        }
    }
}

// MARK: - Previews

struct VerificationDetailScreen_Previews: PreviewProvider, TestablePreview {
    static let sampleEmojis: [VerificationEmoji] = [
        VerificationEmoji(symbol: "🐶", description: "Dog"),
        VerificationEmoji(symbol: "🐱", description: "Cat"),
        VerificationEmoji(symbol: "🦁", description: "Lion"),
        VerificationEmoji(symbol: "🐎", description: "Horse"),
        VerificationEmoji(symbol: "🦄", description: "Unicorn"),
        VerificationEmoji(symbol: "🐷", description: "Pig"),
        VerificationEmoji(symbol: "🐘", description: "Elephant")
    ]

    static var previews: some View {
        ElementNavigationStack {
            screen(state: .loading)
        }
        .previewDisplayName("Loading")

        ElementNavigationStack {
            screen(state: .waitingForEmojis)
        }
        .previewDisplayName("Waiting for emojis")

        ElementNavigationStack {
            screen(state: .readyForReview(emojis: sampleEmojis))
        }
        .previewDisplayName("Ready for review")

        ElementNavigationStack {
            screen(state: .confirming(emojis: sampleEmojis))
        }
        .previewDisplayName("Confirming")

        ElementNavigationStack {
            screen(state: .rejecting(emojis: sampleEmojis))
        }
        .previewDisplayName("Rejecting")

        ElementNavigationStack {
            screen(state: .awaitingRemoteDone)
        }
        .previewDisplayName("Awaiting remote done")

        ElementNavigationStack {
            screen(state: .confirmed)
        }
        .previewDisplayName("Confirmed")

        ElementNavigationStack {
            screen(state: .cancelled(reason: "m.mac"))
        }
        .previewDisplayName("Cancelled (remote)")

        ElementNavigationStack {
            screen(state: .failed(reason: "transport error"))
        }
        .previewDisplayName("Failed")
    }

    static func screen(state: VerificationDetailState) -> some View {
        let service = AgentPlatformServiceMock()
        // Provide a hung fetch so .onAppear doesn't overwrite
        // the preview's seeded state with a real result.
        service.fetchVerificationIdClosure = { _ in
            try? await Task.sleep(for: .seconds(60))
            return .failure(.serverError(status: 0))
        }
        let viewModel = VerificationDetailScreenViewModel(verificationID: "preview",
                                                          agentPlatformService: service,
                                                          initialDetailState: state,
                                                          initialRequesterUserID: "@alice:spiral.md",
                                                          initialRequesterDeviceID: "IPHONEDEVICE",
                                                          initialDeadlineAt: Date().addingTimeInterval(280))
        return VerificationDetailScreen(context: viewModel.context)
    }
}
