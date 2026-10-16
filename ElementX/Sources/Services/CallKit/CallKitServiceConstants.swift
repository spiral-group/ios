//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// AGENT-PLATFORM (Brief 0067): upstream's `ElementCallServiceNotificationKey`, renamed (ADR-0079).
nonisolated enum CallKitNotificationKey: String {
    case roomID
    case roomDisplayName
    // AGENT-PLATFORM (Brief 0063): native CallKit banner identity (caller, avatar, DM-ness)
    // plus the clock-safe ring duration replacing upstream's absolute `expirationDate`.
    case callerID
    case callerDisplayName
    case callerAvatarData
    /// When an incoming call is set to ring, there will be a `m.rtc.notification`event  (MSC4075).
    /// Keep the notification event id as it is needed to decline calls (MSC4310).
    case rtcNotifyEventID
    /// How long the incoming call should still ring, in seconds.
    ///
    /// A DURATION, not a deadline, and that is the whole point (audit
    /// W6-5-3). This used to be an absolute `Date` derived from a server
    /// timestamp, which the app then compared against its own wall clock
    /// with no tolerance at all — so a device running even slightly ahead
    /// of the homeserver decided every ring had already expired and
    /// reported it as missed before it could ring once.
    ///
    /// The NSE computes it from two SERVER timestamps (the event's and the
    /// expiry's), so whatever the device thinks the time is cancels out of
    /// the subtraction entirely.
    case remainingRingSeconds
    case isVoiceCall
    /// Whether the ringing room is a DM. Decides the CallKit banner name:
    /// a DM rings as the person, a group as "Group — Person". The room's
    /// display name alone cannot make that call — for a DM it already IS
    /// the caller's name.
    case isDM
}

// AGENT-PLATFORM (Brief 0063): CallKit handle -> room routing for Recents redial;
// replaces upstream's `CallKitServiceNotificationDiscardDelta` constant.
nonisolated enum CallKitRoomRouting {
    private static let roomIDsByHandleKey = "callKitRoomIDsByHandle"

    static func store(roomID: String, for handle: String) {
        var roomIDsByHandle = UserDefaults.standard.dictionary(forKey: roomIDsByHandleKey) as? [String: String] ?? [:]
        roomIDsByHandle[handle] = roomID
        UserDefaults.standard.set(roomIDsByHandle, forKey: roomIDsByHandleKey)
    }

    static func roomID(for handle: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: roomIDsByHandleKey) as? [String: String])?[handle]
    }

    /// Audit W6-5-6: the table survived logout and grew forever — a Recents
    /// redial after switching accounts routed into the PREVIOUS account's
    /// room mapping. Cleared whenever the user session is torn down.
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: roomIDsByHandleKey)
    }
}
