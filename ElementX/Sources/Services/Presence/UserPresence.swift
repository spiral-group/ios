//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0072, ADR-0083, ADR-0084): another user's presence as
// the app reasons about it — the SDK's record, read once, with the time it was
// read. Views and view models see this type, never `MatrixRustSDK.UserPresence`.
//
// Two shapes reach the app, decided by the server (ADR-0084): EXACT when both
// sides share their presence — online, or the moment of the last activity —
// and COARSE when either side hides it: only a Telegram-style bucket. The
// client shows what it is given; it never coarsens or refines on its own.
//

import Foundation

struct UserPresence: Equatable {
    enum State: Equatable {
        case online
        case unavailable
        case offline
    }
    
    /// What the server says instead of exact presence when either side hides
    /// theirs (ADR-0084).
    enum LastSeenBucket: Equatable {
        /// Up to about three days ago, or online right now.
        case recently
        case withinWeek
        case withinMonth
        case longAgo
    }
    
    let userID: String
    let state: State
    /// How long before `receivedAt` the server last saw the user act.
    let lastActiveAgo: TimeInterval?
    /// Synapse: active within `last_active_granularity` (60 s).
    let currentlyActive: Bool
    /// Set instead of the exact fields when either side hides presence.
    var lastSeenBucket: LastSeenBucket?
    /// When this answer arrived. `lastActiveAgo` ages from here.
    let receivedAt: Date
    /// The owner paused this agent. The server's answer doesn't say so: `PresenceObservation` adds it for the owner.
    var isAgentPaused = false
    
    /// The absolute instant of the last activity, if the server gave one.
    var lastActiveAt: Date? {
        lastActiveAgo.map { receivedAt.addingTimeInterval(-$0) }
    }
    
    /// The green dot: the server says online and the user did something in
    /// the last minute. Never for a coarse answer — "recently" includes "now"
    /// on purpose.
    var isOnline: Bool {
        lastSeenBucket == nil && state == .online && currentlyActive && !isAgentPaused
    }
    
    /// Shows the same as `other`. Every poll re-anchors `receivedAt`, which
    /// moves `lastActiveAt` by the request's jitter; and while a user is
    /// online each of their syncs moves it (Synapse bumps `last_active_ts` on
    /// a sync that sets `online`) without anything visible changing.
    func isEquivalent(to other: UserPresence) -> Bool {
        if isOnline, other.isOnline {
            return true
        }
        guard state == other.state, currentlyActive == other.currentlyActive, lastSeenBucket == other.lastSeenBucket else {
            return false
        }
        switch (lastActiveAt, other.lastActiveAt) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs.timeIntervalSince(rhs)) < 5
        default:
            return false
        }
    }
}

// MARK: - Display

extension UserPresence {
    /// The line under a name, as Telegram words it: «online»; «last seen just
    /// now / 5 minutes ago / today at 14:32 / yesterday at 21:10 / on 12
    /// September»; or, for a coarse answer, «last seen recently / within a
    /// week / within a month / a long time ago». `nil` when there is nothing
    /// to say. Re-evaluate as time passes (the minutes move without a new
    /// answer).
    func statusText(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        if isAgentPaused {
            return UntranslatedL10n.screenAgentsPaused
        }
        // An agent's `last_active_ts` stays at its setup time, so it has no «last seen» to tell.
        if SpiralAppPostSession.isAgent(userID), !isOnline {
            return nil
        }
        if let lastSeenBucket {
            return switch lastSeenBucket {
            case .recently: UntranslatedL10n.commonPresenceLastSeenRecently
            case .withinWeek: UntranslatedL10n.commonPresenceLastSeenWithinWeek
            case .withinMonth: UntranslatedL10n.commonPresenceLastSeenWithinMonth
            case .longAgo: UntranslatedL10n.commonPresenceLastSeenLongAgo
            }
        }
        if isOnline {
            return UntranslatedL10n.commonPresenceOnline
        }
        guard let lastActiveAt else {
            return nil
        }
        
        let ago = now.timeIntervalSince(lastActiveAt)
        if ago < 60 {
            return UntranslatedL10n.commonPresenceLastSeenJustNow
        }
        if ago < 60 * 60 {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .numeric
            return UntranslatedL10n.commonPresenceLastSeenAgo(formatter.localizedString(for: lastActiveAt, relativeTo: now))
        }
        
        let time = lastActiveAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                           calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(lastActiveAt, inSameDayAs: now) {
            return UntranslatedL10n.commonPresenceLastSeenTodayAt(time)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(lastActiveAt, inSameDayAs: yesterday) {
            return UntranslatedL10n.commonPresenceLastSeenYesterdayAt(time)
        }
        
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide)
        let sameYear = calendar.component(.year, from: lastActiveAt) == calendar.component(.year, from: now)
        let date = lastActiveAt.formatted(sameYear ? style : style.year())
        return UntranslatedL10n.commonPresenceLastSeenOnDate(date)
    }
}

// MARK: - Whose presence means anything

enum SpiralPresencePolicy {
    /// Whether presence is worth asking for and showing: an agent has it as
    /// a person does; the puppets and bots of the bridges don't — a Telegram,
    /// WhatsApp or Instagram contact never opens this app, so they would read
    /// as «a long time ago» forever.
    static func hasPresence(_ userID: String) -> Bool {
        guard userID.hasPrefix("@"), userID.contains(":") else {
            return false
        }
        return !SpiralBridgeUsers.isBridgeUser(userID)
    }
}
