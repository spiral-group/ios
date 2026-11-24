//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralComponents
import SwiftUI

// Brief 0039 canon pass (docs/project/CODEBASE/14-element-ui-canon.md §8).

/// "5 min ago" for the Agents tab's rows. The abbreviated style writes a
/// past time as "-5 мин" in Russian, so this is the short style; a time
/// ahead of this device's clock (skew) reads as now, never as the future.
enum AgentRelativeTime {
    /// How often a screen of relative times reads the clock again while it
    /// is open: often enough that «25 сек. назад» doesn't sit for a minute.
    static let refreshSchedule = PeriodicTimelineSchedule(from: .now, by: 30)
    
    static func string(for date: Date, now: Date = .now, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = locale
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}

// AGENT-PLATFORM (1.0.3 snapshot gate): the instant relative times count from.
extension EnvironmentValues {
    /// `nil` in the app, where a relative time reads the clock and follows it. The snapshot tests pin it to
    /// `PreviewClock.now`, the instant the previews' fixtures date themselves from, so «5 min ago» can't turn into
    /// «6 min ago» between making a fixture and rendering it (DEBT § Final pass 1.0.2, "feed fixtures' times drift").
    /// Read by the feed's times (`FeedShortTime`), the outreach queue and the Agents tab's activity and hub; a relative
    /// time elsewhere still follows the clock.
    @Entry var relativeTimeAnchor: Date?
}

/// The instant the previews' fixtures date themselves from: «5 minutes ago» is five minutes before it. Snapshot tests
/// render relative times against it too (`EnvironmentValues.relativeTimeAnchor`).
enum PreviewClock {
    static let now = Date()
}

/// The one status chip (F5): a capsule built from SEMANTIC tokens —
/// replaces the hand-rolled `color.opacity(0.15)` chips that derived
/// backgrounds from icon colours (token misuse, canon §7). Variants map
/// to the badge/subtle token pairs; no icon (status chips are text-only;
/// icon-bearing badges are `BadgeLabel`'s job).
struct AgentStatusBadge: View {
    enum Variant {
        case accent
        case success
        case critical
        case neutral
        
        @MainActor var textColor: Color {
            switch self {
            case .accent: .compound.textBadgeAccent
            case .success: .compound.textSuccessPrimary
            case .critical: .compound.textCriticalPrimary
            case .neutral: .compound.textSecondary
            }
        }
        
        @MainActor var backgroundColor: Color {
            switch self {
            case .accent: .compound.bgBadgeAccent
            case .success: .compound.bgSuccessSubtle
            case .critical: .compound.bgCriticalSubtle
            case .neutral: .compound.bgBadgeDefault
            }
        }
    }
    
    let title: String
    let variant: Variant
    
    var body: some View {
        Text(title)
            .font(.compound.bodyXSSemibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(variant.backgroundColor, in: Capsule())
            .foregroundStyle(variant.textColor)
            .accessibilityLabel(title)
    }
}

/// The one in-Form failure section (F2), with the one Retry: Spiral's empty
/// state (Brief 0083, decision 330). The title says what couldn't be loaded.
struct AgentSpacesRetryErrorSection: View {
    let title: String
    var subtitle: String?
    let retryAction: () -> Void
    
    var body: some View {
        Section {
            SpiralEmptyState(symbol: .exclamationmarkCircle,
                             title: title,
                             message: subtitle,
                             action: .init(L10n.actionRetry, perform: retryAction))
                .listRowBackground(Color.clear)
        }
        .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.error)
    }
}
