//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
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

/// A centred loading spinner that only appears after a short delay
/// (~250 ms). Our Agent-Spaces data loads fast and rarely, so a skeleton
/// or an immediate spinner just flickers (operator feedback 2026-07-11);
/// the member-list canon delays the indicator so quick loads show nothing
/// at all and only genuinely slow loads get a quiet spinner.
struct DelayedProgressView: View {
    var delay: Duration = .milliseconds(250)
    @State private var isVisible = false
    
    var body: some View {
        Group {
            if isVisible {
                ProgressView()
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: delay)
            isVisible = true
        }
    }
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

/// The one presence dot (F3): the agent's name with a token-coloured,
/// Dynamic-Type-scaled dot set in the text, so a name that wraps keeps the
/// dot right after its last word instead of beside the whole block. An
/// offline agent shows its name alone: being offline says nothing useful
/// about an agent, which answers when a message comes.
struct AgentNameWithPresence: View {
    let name: String
    let isOnline: Bool
    
    @ScaledMetric(relativeTo: .title) private var dotSize = 8
    /// Lifts the dot from the baseline to the middle of the capitals.
    @ScaledMetric(relativeTo: .title) private var dotOffset = 7
    
    var body: some View {
        if isOnline {
            (Text(name) + Text(verbatim: "\u{00A0}") + dot)
                .accessibilityLabel("\(name), \(UntranslatedL10n.screenAgentSpaceAgentPresenceOnline)")
        } else {
            Text(name)
        }
    }
    
    private var dot: Text {
        Text(Image(systemName: "circle.fill"))
            .font(.system(size: dotSize))
            .foregroundColor(.compound.iconSuccessPrimary)
            .baselineOffset(dotOffset)
    }
}

/// The one in-Form failure section (F2): the ApprovalDetail `failedSection`
/// anatomy (canon §5 — icon + title + retry), replacing four icon-less
/// hand-rolled duplicates across the Form-based Agent-Spaces lists.
struct AgentSpacesRetryErrorSection: View {
    var title = L10n.errorUnknown
    var subtitle: String?
    let retryAction: () -> Void
    
    var body: some View {
        errorSection
            .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.error)
    }
    
    private var errorSection: some View {
        Section {
            ListRow(kind: .custom {
                VStack(spacing: 16) {
                    BigIcon(icon: \.errorSolid, style: .alertSolid)
                    
                    VStack(spacing: 8) {
                        Text(title)
                            .font(.compound.headingSMSemibold)
                            .foregroundStyle(.compound.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        if let subtitle {
                            Text(subtitle)
                                .font(.compound.bodyMD)
                                .foregroundStyle(.compound.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    Button(L10n.actionRetry, action: retryAction)
                        .buttonStyle(.compound(.secondary, size: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .padding(.horizontal, 16)
            })
        }
        .listRowBackground(Color.clear)
    }
}
