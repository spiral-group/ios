//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decisions 266, 287). The feed's push
// settings per kind: a row moves only on the server's answer, a failed read
// is never "off", one change is on its way at a time, all three kinds go with
// it, and a value newer than this build is shown, never offered or replaced.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedNotificationSettingsViewModelTests {
    private let service = FeedServiceMock()
    private static let everyone = FeedNotificationSettings(likes: .everyone, comments: .everyone, replies: .everyone)

    private func loadedViewModel(_ result: Result<FeedNotificationSettings, FeedError>) async throws -> FeedNotificationSettingsViewModel {
        service.notificationSettingsReturnValue = result
        let viewModel = FeedNotificationSettingsViewModel(feedService: service, userIndicatorController: UserIndicatorControllerMock())
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.settingsState)) { if case .loading = $0 { false } else { true } }
        try await settled.fulfill()
        return viewModel
    }

    /// A failure is not an answer: settings that could not be read are not shown as off.
    @Test
    func aFailedReadIsNotOff() async throws {
        let viewModel = try await loadedViewModel(.failure(.transport))

        #expect(viewModel.context.viewState.settingsState == .failed)
        #expect(viewModel.context.viewState.settings == nil)

        await viewModel.set(.likes, to: .off)
        #expect(service.setNotificationSettingsCallsCount == 0)
    }

    /// One kind changes; the other two go with it as the server stored them.
    @Test(arguments: [FeedPushKind.likes, .comments, .replies])
    func aRowMovesOnlyOnTheServersAnswer(kind: FeedPushKind) async throws {
        let viewModel = try await loadedViewModel(.success(Self.everyone))
        var shownWhileSaving: FeedPushAudience?
        service.setNotificationSettingsClosure = { settings in
            shownWhileSaving = viewModel.context.viewState.settings?[kind]
            return .success(settings)
        }

        await viewModel.set(kind, to: .off)

        var expected = Self.everyone
        expected[kind] = .off
        #expect(shownWhileSaving == .everyone)
        #expect(viewModel.context.viewState.settings == expected)
        #expect(service.setNotificationSettingsReceivedSettings == expected)
    }

    @Test
    func aRefusalLeavesTheRowAsItWas() async throws {
        let viewModel = try await loadedViewModel(.success(Self.everyone))
        service.setNotificationSettingsReturnValue = .failure(.server(status: 500))

        await viewModel.set(.comments, to: .off)

        #expect(viewModel.context.viewState.settings == Self.everyone)
        #expect(!viewModel.context.viewState.isSaving)
    }

    @Test
    func oneChangeAtATime() async throws {
        let viewModel = try await loadedViewModel(.success(Self.everyone))
        service.setNotificationSettingsClosure = { settings in
            await viewModel.set(.replies, to: .off)
            return .success(settings)
        }

        await viewModel.set(.likes, to: .off)

        #expect(service.setNotificationSettingsCallsCount == 1)
    }

    /// Decision 96: a newer server's value is not this build's to replace, nor a value it may send.
    @Test
    func aValueNewerThanThisBuildIsShownAndKept() async throws {
        let newer = FeedNotificationSettings(likes: .other("following"), comments: .everyone, replies: .everyone)
        let viewModel = try await loadedViewModel(.success(newer))
        service.setNotificationSettingsClosure = { .success($0) }

        await viewModel.set(.likes, to: .other("close_friends"))
        #expect(service.setNotificationSettingsCallsCount == 0)

        await viewModel.set(.comments, to: .off)
        #expect(service.setNotificationSettingsReceivedSettings == FeedNotificationSettings(likes: .other("following"), comments: .off, replies: .everyone))
    }

    @Test
    func anOffFeedHidesTheSection() async throws {
        let viewModel = try await loadedViewModel(.failure(.unavailable))

        #expect(viewModel.context.viewState.settingsState == .unavailable)
    }
}
