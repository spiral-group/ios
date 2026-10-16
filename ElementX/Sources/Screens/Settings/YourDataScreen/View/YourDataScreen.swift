//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0078, GDPR): «Your data» — the account export and
// one call's export, each handed to the share sheet.
//

import Compound
import SwiftUI

struct YourDataScreen: View {
    @Bindable var context: YourDataScreenViewModel.Context

    var body: some View {
        Form {
            accountSection
            callsSection
            memorySection
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenYourDataTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $context.exportFile) { file in
            PersonalDataShareSheet(file: file) {
                context.send(viewAction: .exportDismissed)
            }
        }
        .onChange(of: context.exportFile == nil) { _, isGone in
            // A swipe-down closes the sheet without a callback from it.
            if isGone {
                context.send(viewAction: .exportDismissed)
            }
        }
    }

    private var accountSection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenYourDataExportAccount,
                                    icon: \.downloadIos),
                    details: .isWaiting(context.viewState.isExportingAccount),
                    kind: .button {
                        context.send(viewAction: .exportAccount)
                    })
                    .disabled(context.viewState.isExporting)
                    .accessibilityIdentifier(A11yIdentifiers.yourDataScreen.exportAccount)
        } footer: {
            Text(UntranslatedL10n.screenYourDataExportAccountFooter)
                .compoundListSectionFooter()
        }
    }

    private var callsSection: some View {
        Section {
            switch context.viewState.calls {
            case .loading:
                ListRow(label: .plain(title: L10n.commonLoading),
                        details: .isWaiting(true),
                        kind: .label)
            case .failure:
                ListRow(label: .plain(title: UntranslatedL10n.screenYourDataCallsLoadFailed), kind: .label)
                ListRow(label: .default(title: L10n.actionRetry, icon: \.restart),
                        kind: .button {
                            context.send(viewAction: .retryCalls)
                        })
            case .loaded(let calls, let nextCursor):
                if calls.isEmpty {
                    ListRow(label: .description(UntranslatedL10n.screenYourDataCallsEmpty), kind: .label)
                }

                ForEach(calls) { call in
                    ListRow(label: .default(title: call.roomName ?? UntranslatedL10n.screenYourDataCallUnknownRoom,
                                            description: Self.callDescription(call.session),
                                            icon: \.voiceCall),
                            details: .isWaiting(context.viewState.exportingCallID == call.id),
                            kind: .button {
                                context.send(viewAction: .exportCall(id: call.id))
                            })
                            .disabled(context.viewState.isExporting)
                }

                if nextCursor != nil {
                    ListRow(label: .default(title: L10n.actionLoadMore, icon: \.arrowDown),
                            details: .isWaiting(context.viewState.isLoadingMoreCalls),
                            kind: .button {
                                context.send(viewAction: .loadMoreCalls)
                            })
                            .disabled(context.viewState.isLoadingMoreCalls)
                }
            }
        } header: {
            Text(UntranslatedL10n.screenYourDataCallsSection)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenYourDataCallsFooter)
                .compoundListSectionFooter()
        }
    }

    private var memorySection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenYourDataMemoryTitle,
                                    description: UntranslatedL10n.screenYourDataMemoryDescription,
                                    icon: \.user),
                    kind: .label)
        }
    }

    /// «9 Oct, 14:23 · 25 min», or «Ongoing» for a call that has not ended.
    static func callDescription(_ session: VoiceSessionRecord) -> String {
        let date = session.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        guard let endedAt = session.endedAt else {
            return "\(date) · \(UntranslatedL10n.screenYourDataCallOngoing)"
        }
        guard let startedAt = session.startedAt else {
            return date
        }
        let duration = Duration.seconds(max(0, endedAt.timeIntervalSince(startedAt).rounded()))
        return "\(date) · \(duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))"
    }
}

/// The system share sheet for an export file.
private struct PersonalDataShareSheet: View {
    let file: PersonalDataExportFile
    let onFinish: () -> Void

    var body: some View {
        AppActivityView(activityItems: [file.url],
                        onCancel: onFinish,
                        onComplete: { _ in onFinish() })
            .ignoresSafeArea(edges: .bottom)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
    }
}

// MARK: - Previews

struct YourDataScreen_Previews: PreviewProvider, TestablePreview {
    static let callsViewModel = makeViewModel(.success(.init(sessions: sessions, nextCursor: "more")))
    static let noCallsViewModel = makeViewModel(.success(.init(sessions: [], nextCursor: nil)))
    static let failureViewModel = makeViewModel(.failure(.serverError(status: 500)))

    static var previews: some View {
        ElementNavigationStack {
            YourDataScreen(context: callsViewModel.context)
        }
        .previewDisplayName("Calls")
        .snapshotPreferences(expect: callsViewModel.context.observe(\.viewState.calls).map { $0 != .loading })

        ElementNavigationStack {
            YourDataScreen(context: noCallsViewModel.context)
        }
        .previewDisplayName("No calls")
        .snapshotPreferences(expect: noCallsViewModel.context.observe(\.viewState.calls).map { $0 != .loading })

        ElementNavigationStack {
            YourDataScreen(context: failureViewModel.context)
        }
        .previewDisplayName("Calls failed")
        .snapshotPreferences(expect: failureViewModel.context.observe(\.viewState.calls).map { $0 != .loading })
    }

    /// 2026-10-09 10:00 UTC.
    static let start = Date(timeIntervalSince1970: 1_791_540_000)

    static let sessions: [VoiceSessionRecord] = [
        .init(id: "s-live", agentMXID: "@assistant-alice:spiral.md", roomID: "!dm:spiral.md",
              createdAt: start.addingTimeInterval(86400), startedAt: start.addingTimeInterval(86404), endedAt: nil),
        .init(id: "s-standup", agentMXID: "@assistant-alice:spiral.md", roomID: "!standup:spiral.md",
              createdAt: start, startedAt: start.addingTimeInterval(4), endedAt: start.addingTimeInterval(1504)),
        .init(id: "s-left", agentMXID: "@assistant-alice:spiral.md", roomID: "!gone:spiral.md",
              createdAt: start.addingTimeInterval(-86400), startedAt: start.addingTimeInterval(-86396), endedAt: start.addingTimeInterval(-86351))
    ]

    static func makeViewModel(_ calls: Result<VoiceSessionsPage, AgentPlatformError>) -> YourDataScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.listVoiceSessionsCursorReturnValue = calls

        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierClosure = { roomID in
            switch roomID {
            case "!dm:spiral.md": RoomSummary.mock(id: roomID, name: "Bob")
            case "!standup:spiral.md": RoomSummary.mock(id: roomID, name: "Daily standup")
            default: nil
            }
        }

        return YourDataScreenViewModel(agentPlatformService: service,
                                       clientProxy: clientProxy,
                                       userIndicatorController: UserIndicatorControllerMock())
    }
}
