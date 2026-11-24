//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import Macros
import Synchronization // AGENT-PLATFORM (1.0.3)

final nonisolated class AccountSettings: @unchecked Sendable {
    /// UserDefaults to be used on reads and writes.
    private let store: AccountUserDefaults
    private let userID: String
    
    // MARK: Session Activity
    
    /// When this account was last selected, used to order the accounts most recently selected first.
    @UserPreference
    var lastSelectedDate: Date?
    
    @UserPreference(defaultValue: false)
    var hasRunIdentityConfirmationOnboarding: Bool
    
    /// AGENT-PLATFORM (1.0.3): the platform's answer about the invite welcome is settled for this account — nothing
    /// was owed, or it was shown and the platform recorded it. Until then each session start asks again.
    @UserPreference(defaultValue: false)
    var hasSettledInviteWelcome: Bool
    
    /// AGENT-PLATFORM (1.0.3): the welcome was shown on this device but the platform hasn't recorded it yet: the next
    /// session start retries the record instead of showing it again.
    @UserPreference(defaultValue: false)
    var hasShownInviteWelcome: Bool
    
    /// The queries the user searched for and the rooms they opened from the results, most recent first.
    @UserPreference(defaultValue: [SearchBreadcrumb]())
    var searchBreadcrumbs: [SearchBreadcrumb]
    
    /// The Set of room identifiers of invites that the user already saw in the invites list.
    /// This Set is being used to implement badges for unread invites.
    @UserPreference(defaultValue: Set<String>())
    var seenInvites: Set<String>
    
    /// The rooms this account is sharing its live location in.
    @UserPreference(key: "liveLocationSharingTimeoutDatesByRoomID", defaultValue: [String: LiveLocationSession]())
    var liveLocationSharingSessionsByRoomID: [String: LiveLocationSession]
    
    /// AGENT-PLATFORM (1.0.3): the Element X release whose per-account migrations this account ran, see `UpstreamMigrationBaseline`.
    @UserPreference(key: "spiralUpstreamMigrationsVersion")
    var upstreamMigrationsVersion: String?
    
    /// AGENT-PLATFORM (1.0.3): the sign-in methods the platform last reported, so Security draws its
    /// rows on the first frame instead of moving them when the answer arrives. Cleared with the account.
    @UserPreference(key: "spiralSignInMethods")
    var signInMethods: SignInMethods?
    
    // MARK: Visible Preferences
    
    @UserPreference(defaultValue: true)
    var showAllRoomListActivity: Bool
    
    /// Whether this account's notifications are on. When off, its pusher is deleted from the homeserver.
    @UserPreference(defaultValue: true)
    var enableNotifications: Bool
    
    /// The tone played when the user hasn't selected one, which the homeserver can configure remotely.
    let defaultNotificationTone: RemotePreference<NotificationTone> = .init(.default)
    
    /// The sound played when delivering noisy notifications. If nil, use ``defaultNotificationTone``.
    @UserPreference
    var selectedNotificationTone: NotificationTone?
    
    @UserPreference(defaultValue: true)
    var sharePresence: Bool
    
    /// AGENT-PLATFORM (1.0.3): set by `reset()` at sign-out, so a read that answers afterwards
    /// (the Security screen's sign-in methods) doesn't write the account's values back.
    private let wasReset = Atomic<Bool>(false)
    var isReset: Bool {
        wasReset.load(ordering: .acquiring)
    }
    
    init(userID: String, store: UserDefaultsProtocol) {
        self.store = .init(userID: userID, store: store)
        self.userID = userID
    }
    
    func migrateAppSettingsValue(_ keyPath: KeyPath<AccountSettings, UserPreferenceKey>) {
        let storeKey = self[keyPath: keyPath].rawValue
        store.migrateAppSettingsValue(forKey: storeKey)
    }
    
    // AGENT-PLATFORM (Spiral 1.0.1 → 1.0.2): 1.0.1 stored the room list's activity as the
    // app-wide enum `roomListActivityVisibility` (current, show, hide); upstream 26.10 made
    // it this account's `showAllRoomListActivity`. 1.0.1 read `hide` and `show` alike (the
    // restricted dot, `needsAttention`), as upstream's own replacement does; only `current` meant all.
    func migrateRoomListActivityVisibility() {
        store.migrateAppSettingsValue(forKey: "roomListActivityVisibility",
                                      toKey: showAllRoomListActivityKey.rawValue) { (visibility: LegacyRoomListActivityVisibility) in
            visibility == .current
        }
    }
    
    /// Spiral 1.0.1's stored shape, JSON-encoded like every non-plist preference.
    private enum LegacyRoomListActivityVisibility: String, Codable {
        case current, show, hide
    }
    
    func reset() {
        MXLog.warning("Resetting AccountSettings for \(userID).")
        wasReset.store(true, ordering: .releasing) // AGENT-PLATFORM (1.0.3)
        store.reset()
    }
}
