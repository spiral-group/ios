//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SFSafeSymbols
import SwiftUI

/// What an agent is doing, said in words; the dot or glyph beside them only repeats it.
public enum SpiralAgentStatus: Equatable {
    /// Online: a green dot before the text.
    case online(String)
    /// Paused by its owner: the pause glyph before the text.
    case paused(String)
}

/// An agent as Spiral shows one (Brief 0083 phase 4, batch P4-D): its avatar, its name, what it is ("your personal
/// assistant", or its role), its status and the actions it offers. An assistant is drawn by its own avatar and the
/// word for what it is, never by the Agents tab's glyph (critique of 2026-11-02, F5).
///
/// - `row`: a list's row, the avatar leading, the text beside it and an accessory trailing (a chevron, a status, a
///   spinner). In a `Form` it is a `ListRow`'s custom content, and a button's label when the row opens something.
/// - `profile`: a screen's header, centred, as Settings' profile card (decision 337).
///
/// Actions go under the text, as the screen's own buttons (Compound's capsules, decision 329).
public struct SpiralAgentCard<Avatar: View, Accessory: View, Actions: View>: View {
    public enum Layout {
        case row
        case profile
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let layout: Layout
    private let name: String
    private let subtitle: String?
    private let role: String?
    private let status: SpiralAgentStatus?
    private let details: String?
    private let avatar: Avatar
    private let accessory: Accessory
    private let actions: Actions

    /// - Parameters:
    ///   - name: the agent's name.
    ///   - subtitle: its address, under the name in a profile (a row leaves it out).
    ///   - role: what it is: "your personal assistant", or a role agent's role.
    ///   - status: online or paused; nothing when neither.
    ///   - details: one more line of facts, after the status ("4 chats · 2 tools").
    public init(layout: Layout = .row,
                name: String,
                subtitle: String? = nil,
                role: String? = nil,
                status: SpiralAgentStatus? = nil,
                details: String? = nil,
                @ViewBuilder avatar: () -> Avatar,
                @ViewBuilder accessory: () -> Accessory,
                @ViewBuilder actions: () -> Actions) {
        self.layout = layout
        self.name = name
        self.subtitle = subtitle
        self.role = role
        self.status = status
        self.details = details
        self.avatar = avatar()
        self.accessory = accessory()
        self.actions = actions()
    }

    public var body: some View {
        switch layout {
        case .row:
            row
        case .profile:
            profile
        }
    }

    // MARK: Layouts

    private var row: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space3X) {
            Group {
                // At accessibility sizes the text goes under the avatar, so the name keeps the width.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
                        HStack(spacing: CompoundDesignTokens.space3X) {
                            rowAvatar
                            Spacer(minLength: 0)
                            accessory
                        }
                        rowText
                    }
                } else {
                    HStack(spacing: CompoundDesignTokens.space3X) {
                        rowAvatar
                        rowText
                        accessory
                    }
                }
            }
            .accessibilityElement(children: .combine)

            actions
        }
        .padding(.horizontal, ListRowPadding.horizontal)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private var rowAvatar: some View {
        avatar
            .accessibilityHidden(true)
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space0_5X) {
            Text(Self.keepingSeparators(name))
                .font(.compound.bodyLGSemibold)
                .foregroundStyle(isEnabled ? .compound.textPrimary : .compound.textSecondary) // textDisabled read 2.21:1, and a dimmed row still tells who's in the chat

            if let role {
                Text(Self.keepingSeparators(role))
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }

            statusLine(alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profile: some View {
        VStack(spacing: CompoundDesignTokens.space1X) {
            VStack(spacing: CompoundDesignTokens.space1X) {
                avatar
                    .accessibilityHidden(true)
                    .padding(.bottom, CompoundDesignTokens.space2X)

                Text(Self.keepingSeparators(name))
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                        .textSelection(.enabled)
                }

                if let role {
                    Text(Self.keepingSeparators(role))
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                }

                statusLine(alignment: .center)
            }
            .accessibilityElement(children: .combine)

            actions
                .padding(.top, CompoundDesignTokens.space4X)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ListRowPadding.horizontal)
        .padding(.vertical, CompoundDesignTokens.space4X)
    }

    // MARK: Status

    /// "● Online · 4 chats · 2 tools": the status first, then the facts.
    @ViewBuilder
    private func statusLine(alignment: HorizontalAlignment) -> some View {
        let text = Self.keepingSeparators([status?.title, details].compactMap(\.self).joined(separator: " · "))
        if !text.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space1X) {
                SpiralAgentStatusMark(status: status)
                Text(text)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }
            .frame(maxWidth: layout == .row ? .infinity : nil, alignment: Alignment(horizontal: alignment, vertical: .center))
        }
    }

    private static func keepingSeparators(_ text: String) -> String {
        text.keepingSeparators
    }
}

public extension String {
    /// A no-break space before each " · ", so a wrapped line never starts with the separator ("Anna · assistant").
    var keepingSeparators: String {
        replacingOccurrences(of: " ·", with: "\u{00A0}·")
    }
}

/// The dot or glyph before an agent's status words; it only repeats them, so VoiceOver skips it.
public struct SpiralAgentStatusMark: View {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .footnote) private var dotSize = 8

    private let status: SpiralAgentStatus?

    public init(status: SpiralAgentStatus?) {
        self.status = status
    }

    public var body: some View {
        switch status {
        case .online:
            Circle()
                .fill(isEnabled ? Color.compound.iconSuccessPrimary : .compound.iconDisabled)
                .frame(width: dotSize, height: dotSize)
                .accessibilityHidden(true)
        case .paused:
            Image(systemSymbol: .pauseCircleFill)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.iconSecondary)
                .accessibilityHidden(true)
        case nil:
            EmptyView()
        }
    }
}

public extension SpiralAgentStatus {
    var title: String {
        switch self {
        case .online(let title), .paused(let title): title
        }
    }
}

public extension SpiralAgentCard where Actions == EmptyView {
    init(layout: Layout = .row,
         name: String,
         subtitle: String? = nil,
         role: String? = nil,
         status: SpiralAgentStatus? = nil,
         details: String? = nil,
         @ViewBuilder avatar: () -> Avatar,
         @ViewBuilder accessory: () -> Accessory) {
        self.init(layout: layout, name: name, subtitle: subtitle, role: role, status: status, details: details,
                  avatar: avatar, accessory: accessory) { EmptyView() }
    }
}

public extension SpiralAgentCard where Accessory == EmptyView {
    init(layout: Layout = .row,
         name: String,
         subtitle: String? = nil,
         role: String? = nil,
         status: SpiralAgentStatus? = nil,
         details: String? = nil,
         @ViewBuilder avatar: () -> Avatar,
         @ViewBuilder actions: () -> Actions) {
        self.init(layout: layout, name: name, subtitle: subtitle, role: role, status: status, details: details,
                  avatar: avatar, accessory: { EmptyView() }, actions: actions)
    }
}

/// A `SpiralAgentCard` row's trailing chevron: the row opens the agent.
public struct SpiralAgentCardChevron: View {
    public init() { }

    public var body: some View {
        ListRowAccessory.navigationLink
    }
}
