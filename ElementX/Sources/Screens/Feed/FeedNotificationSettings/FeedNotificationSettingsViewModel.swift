//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, decisions 266, 287). The feed's section
// of the notification settings: who the likes, comments and replies pushes
// come from, each "From everyone" or "Off" (`GET|PUT
// /feed/me/notification-settings`). A row shows what the server stored and
// moves only once the server has stored the change. A value newer than this
// build shows as "Update Spiral" and is not offered (decision 96). Notices
// always push, whatever these say.
//

import Combine
import SwiftUI

/// A kind of engagement push, one row each.
enum FeedPushKind: CaseIterable {
    case likes
    case comments
    case replies
}

enum FeedNotificationSettingsState: Equatable {
    case loading
    case loaded(FeedNotificationSettings)
    /// `FEED_MODE=off`: the section is not shown.
    case unavailable
    /// Could not be read: never shown as off.
    case failed
}

struct FeedNotificationSettingsViewState: BindableState {
    var settingsState: FeedNotificationSettingsState = .loading
    /// A change is on its way to the server.
    var isSaving = false

    var settings: FeedNotificationSettings? {
        if case .loaded(let settings) = settingsState { settings } else { nil }
    }
}

enum FeedNotificationSettingsViewAction {
    case retry
    case set(FeedPushKind, FeedPushAudience)
}

typealias FeedNotificationSettingsViewModelType = StateStoreViewModelV2<FeedNotificationSettingsViewState, FeedNotificationSettingsViewAction>

class FeedNotificationSettingsViewModel: FeedNotificationSettingsViewModelType {
    private let feedService: FeedServiceProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol

    init(feedService: FeedServiceProtocol, userIndicatorController: UserIndicatorControllerProtocol) {
        self.feedService = feedService
        self.userIndicatorController = userIndicatorController
        super.init(initialViewState: FeedNotificationSettingsViewState())
        Task { await load() }
    }

    override func process(viewAction: FeedNotificationSettingsViewAction) {
        switch viewAction {
        case .retry:
            state.settingsState = .loading
            Task { await load(isManual: true) }
        case .set(let kind, let audience):
            Task { await set(kind, to: audience) }
        }
    }

    /// - Parameter isManual: Retry; over the read window it says "slow down" rather than wait.
    func load(isManual: Bool = false) async {
        let read = { [feedService] in await feedService.notificationSettings() }
        switch isManual ? await read() : await FeedReadWindow.retryingOnce(read) {
        case .success(let settings):
            state.settingsState = .loaded(settings)
        case .failure(.unavailable):
            state.settingsState = .unavailable
        case .failure(let error):
            MXLog.error("Failed to read the feed's push settings: \(error)")
            // Over the read window the rows already shown stay as they are.
            if !(error.isRateLimited && state.settings != nil) {
                state.settingsState = .failed
            }
            if isManual, error.isRateLimited {
                FeedReadWindow.showSlowDown(userIndicatorController)
            }
        }
    }

    /// One change at a time, and only to a value this build offers; the row shows the server's answer, or stays as it was.
    func set(_ kind: FeedPushKind, to audience: FeedPushAudience) async {
        guard !state.isSaving, audience == .everyone || audience == .off,
              var settings = state.settings, settings[kind] != audience else { return }
        settings[kind] = audience
        state.isSaving = true
        defer { state.isSaving = false }

        switch await feedService.setNotificationSettings(settings) {
        case .success(let stored):
            state.settingsState = .loaded(stored)
        case .failure:
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: UntranslatedL10n.screenFeedNotificationSettingsSaveFailed,
                                                                  icon: \.close))
        }
    }
}

extension FeedNotificationSettings {
    subscript(kind: FeedPushKind) -> FeedPushAudience {
        get {
            switch kind {
            case .likes: likes
            case .comments: comments
            case .replies: replies
            }
        }
        set {
            switch kind {
            case .likes: likes = newValue
            case .comments: comments = newValue
            case .replies: replies = newValue
            }
        }
    }
}
