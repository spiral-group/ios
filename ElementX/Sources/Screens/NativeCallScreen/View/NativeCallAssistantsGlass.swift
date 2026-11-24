//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, question 403, L5 — the operator's pick C1): the Assistants sheet is a continuation of
// the call screen, made of the call's own glass. Its parts, each borrowed from the call: the header (the agent's avatar
// in its colour, a title, one status line, a glass round ✕ like the call's top buttons, a glass ‹ on a pushed page),
// the four job buttons (the dock's own 60 pt circles and caption font), and rows as glass capsules. Blue is for on and
// for the one main action; red only for stop or a problem (DESIGN.md). Nothing here is a white card or settings grey.

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

// MARK: - The four buttons

struct NativeCallAssistantDockView: View {
    let state: NativeCallAssistantDockState
    /// While the assistant is on its way, or on someone else's page, the buttons show and take no taps; unlike a
    /// disabled button they don't fade (1.2, 4.3).
    var isInteractive = true
    /// Question 404: the avatar of the assistant whose recording covers the call, on the covered «Записує».
    var coverBadge: NativeCallSheetAvatar?
    let onTap: (NativeCallAssistantJob) -> Void

    var body: some View {
        SpiralGlassGroup(spacing: CompoundDesignTokens.space3X) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(state.buttons) { button in
                    NativeCallAssistantJobButton(button: button, isInteractive: isInteractive) { onTap(button.job) }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        // Over the glass group, not in it: the group draws its glass above anything its circles carry.
        .overlay(alignment: .topLeading) {
            if let coverBadge, let column = state.buttons.firstIndex(where: \.isCovered) {
                GeometryReader { proxy in
                    let columnWidth = proxy.size.width / CGFloat(state.buttons.count)
                    let radius = NativeCallRoundCircle.diameter / 2
                    coverBadge
                        .padding(2)
                        .background(Color.compound.bgCanvasDefault, in: Circle())
                        // On the circle's lower right edge, where an avatar badge sits on the call's own avatars.
                        .position(x: columnWidth * (CGFloat(column) + 0.5) + radius * 0.75, y: radius * 1.7)
                }
                .allowsHitTesting(false)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .animation(NativeCallAssistantsMotion.change, value: state)
    }
}

private struct NativeCallAssistantJobButton: View {
    let button: NativeCallAssistantDockState.Button
    let isInteractive: Bool
    let action: () -> Void

    /// The covered «Записує» is dimmed and still takes a tap: it says who records (question 404).
    private var takesTaps: Bool {
        isInteractive && (button.isEnabled || button.isCovered) && !button.isBusy
    }

    private var opacity: Double {
        button.isEnabled || button.isOn ? 1 : 0.4
    }

    /// Question 404: Liquid Glass ignores the button's opacity, so the covered «Записує» dims its glyph too (the sketch).
    private var coveredGlyphOpacity: Double {
        guard button.isCovered else { return 1 }
        if #available(iOS 26, *) { return opacity }
        return 1
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: CompoundDesignTokens.space2X) {
                NativeCallRoundCircle(image: Image(systemName: button.isRefused ? "exclamationmark.circle" : NativeCallAssistantsCopy.symbol(button.job)),
                                      fill: button.isOn && !button.isRefused ? .compound.bgAccentRest : nil,
                                      ring: ring,
                                      isBusy: button.isBusy,
                                      glyphOpacity: coveredGlyphOpacity)
                Text(NativeCallAssistantsCopy.title(button))
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(button.isRefused ? Color.compound.textCriticalPrimary : .compound.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            // Unavailable: dimmed, as the dock never is, so on and off stay the only two looks of a live button.
            .opacity(opacity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Not `disabled`: the system would fade an "on" button too, and a read-only page shows on as filled (4.3).
        .allowsHitTesting(takesTaps)
        .accessibilityRespondsToUserInteraction(takesTaps)
        .accessibilityLabel(NativeCallAssistantsCopy.title(button.job))
        // Question 404: «Записує» or «Продовжити» as the recording button's value, so the job keeps its name.
        .accessibilityValue(button.cover == nil ? "" : NativeCallAssistantsCopy.title(button))
        .accessibilityAddTraits(button.isOn ? [.isToggle, .isSelected] : button.isCovered ? [] : [.isToggle])
    }

    private var ring: Color? {
        if button.isRefused { return .compound.borderCriticalPrimary }
        if button.isPending { return .compound.bgAccentRest }
        return nil
    }
}

// MARK: - Motion

enum NativeCallAssistantsMotion {
    /// The call's own change: a button on or off, a status line, a row that swaps (the dock's spring).
    static let change = Animation.spring(duration: 0.35, bounce: 0)
}

// MARK: - A page of the sheet

/// One page: its header, then its content on the sheet's glass. The navigation bar is hidden: the header is the call's.
struct NativeCallSheetPage<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    /// The content is scrolled away from its top: it is clipped to stay under the header.
    @State private var isScrolled = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, CompoundDesignTokens.space4X)
                .padding(.top, CompoundDesignTokens.space5X)
                .padding(.bottom, CompoundDesignTokens.space3X)
            ScrollView {
                VStack(spacing: CompoundDesignTokens.space3X) {
                    content
                }
                .padding(.horizontal, CompoundDesignTokens.space4X)
                .padding(.bottom, CompoundDesignTokens.space6X)
            }
            .scrollBounceBehavior(.basedOnSize)
            // L9: a pressed glass button grows past the scroll view's top; at rest it is drawn over the header, as the
            // system draws it, whether or not the page could scroll (the job buttons are always at its top). Once the
            // content is scrolled, rows stay clipped under the header.
            .scrollClipDisabled(!isScrolled)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 0.5
            } action: { _, isScrolled in
                self.isScrolled = isScrolled
            }
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .containerBackground(.clear, for: .navigation)
    }
}

/// The header: a way back on a pushed page, the avatar, a title and one status line, and the glass ✕ — sharing one glass
/// capsule with the page's «…» when it has one, as iOS groups toolbar buttons (operator's pick in the call lab, 1.0.3).
struct NativeCallSheetHeader<Leading: View, Accessory: View>: View {
    let title: String
    let status: String?
    var isStatusCritical = false
    /// The status is still unknown: a placeholder of its size, never a guess that flips (loading rule).
    var isLoading = false
    /// Whether `accessory` draws anything, when its type can't tell (an `if` inside the builder).
    var hasAccessory: Bool?
    var onBack: (() -> Void)?
    let onClose: () -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            if let onBack {
                NativeCallSheetRoundButton(systemImage: "chevron.left",
                                           label: L10n.actionBack,
                                           action: onBack)
            }
            leading
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                // Always one line's height, so a status that comes or changes moves nothing.
                Text(isLoading ? "Placeholder status" : status ?? " ")
                    .font(.compound.bodySM)
                    .foregroundStyle(isStatusCritical ? Color.compound.textCriticalPrimary : .compound.textSecondary)
                    .lineLimit(1)
                    // A 375-pt phone with the "…" button: a long status (the standby line) gives up a little size
                    // before it gives up words.
                    .minimumScaleFactor(0.85)
                    .contentTransition(.opacity)
                    .spiralLoadingSlot(isLoading, label: L10n.commonLoading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(NativeCallAssistantsMotion.change, value: status)
            if hasAccessory ?? (Accessory.self != EmptyView.self) {
                HStack(spacing: 0) {
                    accessory
                    NativeCallSheetRoundButton(systemImage: "xmark", label: L10n.actionClose, action: onClose)
                }
                .environment(\.nativeCallGlyphInCapsule, true)
                // The glass is 36 pt high inside the glyphs' 44-pt tap frames.
                .background {
                    Color.clear
                        .nativeCallSurface(in: Capsule(), isInteractive: true)
                        .padding(.vertical, 4)
                }
            } else {
                accessory
                NativeCallSheetRoundButton(systemImage: "xmark", label: L10n.actionClose, action: onClose)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

extension NativeCallSheetHeader where Accessory == EmptyView {
    init(title: String,
         status: String?,
         isStatusCritical: Bool = false,
         isLoading: Bool = false,
         onBack: (() -> Void)? = nil,
         onClose: @escaping () -> Void,
         @ViewBuilder leading: () -> Leading) {
        self.init(title: title, status: status, isStatusCritical: isStatusCritical, isLoading: isLoading,
                  onBack: onBack, onClose: onClose, leading: leading) { EmptyView() }
    }
}

/// The call's top buttons, smaller: a glass circle with one glyph, 44 pt to tap.
struct NativeCallSheetRoundButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NativeCallSheetRoundGlyph(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct NativeCallSheetRoundGlyph: View {
    let systemImage: String
    @Environment(\.nativeCallGlyphInCapsule) private var isInCapsule

    var body: some View {
        if isInCapsule {
            // The capsule around it is the glass; the glyph takes its share of it, still 44 pt wide to tap.
            Image(systemName: systemImage)
                .font(.compound.bodyMDSemibold)
                .foregroundStyle(.compound.iconPrimary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        } else {
            Image(systemName: systemImage)
                .font(.compound.bodyMDSemibold)
                .foregroundStyle(.compound.iconPrimary)
                .frame(width: 32, height: 32)
                .nativeCallSurface(in: Circle(), isInteractive: true)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
    }
}

extension EnvironmentValues {
    /// A round glyph inside the header's shared capsule draws no glass of its own.
    @Entry var nativeCallGlyphInCapsule = false
}

/// An assistant's mark: its avatar, in its own agent colour (the only place the colour shows, DESIGN.md).
struct NativeCallSheetAvatar: View {
    let mxid: String
    let name: String
    let url: URL?
    var size: CGFloat = SpiralAvatarSize.small
    let mediaProvider: MediaProviderProtocol?

    var body: some View {
        LoadableAvatarImage(url: url,
                            name: name,
                            contentID: mxid,
                            avatarSize: .custom(size),
                            mediaProvider: mediaProvider)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityHidden(true)
    }
}

// MARK: - Rows and actions

/// A row of the sheet: a glass capsule, ~52 pt, full radius; taller rows keep the same radius.
struct NativeCallSheetRow<Leading: View, Trailing: View>: View {
    enum Role {
        case normal
        /// Stop, remove: the red of "End".
        case destructive
    }

    let title: String
    var detail: String?
    var value: String?
    var role = Role.normal
    var showsChevron = false
    var isSelected = false
    var isWaiting = false
    var action: (() -> Void)?
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .allowsHitTesting(!isWaiting)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    /// AX3: at accessibility sizes the value goes under the title and the glyph to the top, as Settings rows do, so a
    /// title is never broken into syllables beside its value.
    private var isStacked: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var content: some View {
        HStack(alignment: isStacked ? .top : .center, spacing: CompoundDesignTokens.space3X) {
            leading
                .foregroundStyle(role == .destructive ? Color.compound.iconCriticalPrimary : .compound.iconPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(role == .destructive ? Color.compound.textCriticalPrimary : .compound.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
                if isStacked, let value {
                    valueText(value)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isStacked, let value {
                valueText(value)
                    .lineLimit(1)
            }
            trailing
            if isWaiting {
                ProgressView()
            } else if isSelected {
                Image(systemName: "checkmark")
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.iconAccentPrimary)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.iconTertiary)
            }
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .frame(minHeight: NativeCallSheetMetrics.rowHeight)
        // As the header: past AX2 a word no longer fits a row's width and breaks into syllables.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .contentShape(.rect)
        .nativeCallSurface(in: RoundedRectangle(cornerRadius: NativeCallSheetMetrics.rowHeight / 2, style: .continuous),
                           isInteractive: action != nil)
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(.compound.bodyLG)
            .foregroundStyle(.compound.textSecondary)
            .contentTransition(.opacity)
    }
}

extension NativeCallSheetRow where Trailing == EmptyView {
    init(title: String,
         detail: String? = nil,
         value: String? = nil,
         role: Role = .normal,
         showsChevron: Bool = false,
         isSelected: Bool = false,
         isWaiting: Bool = false,
         action: (() -> Void)? = nil,
         @ViewBuilder leading: () -> Leading) {
        self.init(title: title, detail: detail, value: value, role: role, showsChevron: showsChevron, isSelected: isSelected,
                  isWaiting: isWaiting, action: action, leading: leading) { EmptyView() }
    }
}

extension NativeCallSheetRow where Leading == NativeCallSheetRowIcon, Trailing == EmptyView {
    init(icon: String?,
         title: String,
         detail: String? = nil,
         value: String? = nil,
         role: Role = .normal,
         showsChevron: Bool = false,
         isSelected: Bool = false,
         isWaiting: Bool = false,
         action: (() -> Void)? = nil) {
        self.init(title: title, detail: detail, value: value, role: role, showsChevron: showsChevron, isSelected: isSelected,
                  isWaiting: isWaiting, action: action) { NativeCallSheetRowIcon(systemName: icon) }
    }
}

/// A row's glyph, in a fixed slot so titles line up.
struct NativeCallSheetRowIcon: View {
    let systemName: String?
    /// The slot grows with the text, so a large glyph stays inside its row.
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 24

    var body: some View {
        if let systemName {
            Image(systemName: systemName)
                .font(.compound.bodyLG)
                .frame(width: width)
                .accessibilityHidden(true)
        }
    }
}

enum NativeCallSheetMetrics {
    static let rowHeight: CGFloat = 52
    static let actionHeight: CGFloat = 50
}

/// The page's one main action: a full-width blue capsule, or red for a removal's confirmation.
struct NativeCallSheetPrimaryButton: View {
    let title: String
    var isDestructive = false
    var isWaiting = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .opacity(isWaiting ? 0 : 1)
                if isWaiting {
                    ProgressView()
                        .tint(Color.compound.iconOnSolidPrimary)
                }
            }
            .foregroundStyle(.compound.textOnSolidPrimary)
            .frame(maxWidth: .infinity, minHeight: NativeCallSheetMetrics.actionHeight)
            .background(isDestructive ? Color.compound.bgCriticalPrimary : .compound.bgAccentRest, in: Capsule())
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isWaiting)
    }
}

/// A second action: a glass capsule, its title centred.
struct NativeCallSheetSecondaryButton: View {
    let title: String
    /// Red text on the glass: an action that stops something, not a second way forward.
    var isDestructive = false
    var isWaiting = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(isDestructive ? Color.compound.textCriticalPrimary : Color.compound.textPrimary)
                    .opacity(isWaiting ? 0 : 1)
                if isWaiting {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: NativeCallSheetMetrics.actionHeight)
            .contentShape(.capsule)
            .nativeCallSurface(in: Capsule(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isWaiting)
    }
}

/// A question or a problem, in one glass block: a glyph, its title (red for a problem) and one line on what it means.
struct NativeCallSheetNotice: View {
    let systemImage: String
    let title: String
    let detail: String?
    var isCritical = true
    /// Red, like the call's ЗАПИСЬ, unless the line is only news (a recording that stopped).
    var isIconCritical = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space3X) {
            Image(systemName: systemImage)
                .font(.compound.bodyLG)
                .foregroundStyle(isIconCritical ? Color.compound.iconCriticalPrimary : .compound.iconSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(isCritical ? Color.compound.textCriticalPrimary : .compound.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .frame(minHeight: NativeCallSheetMetrics.rowHeight)
        .nativeCallSurface(in: RoundedRectangle(cornerRadius: NativeCallSheetMetrics.rowHeight / 2, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One quiet line on what a choice means, centred under what it is about.
struct NativeCallSheetCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.compound.bodySM)
            .foregroundStyle(.compound.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, CompoundDesignTokens.space2X)
    }
}

/// A list's group title, as the call writes small captions: «УЖЕ ПЕРЕВОДЯТ — БЕСПЛАТНО».
struct NativeCallSheetSectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.compound.bodyXSSemibold)
            .foregroundStyle(.compound.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.top, CompoundDesignTokens.space2X)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row's placeholder at the row's own size, while what it says is unknown.
struct NativeCallSheetPlaceholderRow: View {
    var body: some View {
        NativeCallSheetRow(icon: "circle", title: "Placeholder title", value: "Value")
            .spiralLoadingSlot(true, label: L10n.commonLoading)
    }
}

/// A search on the sheet's glass (question 403, L10): a glass capsule with a magnifier, the field and a clear button.
/// The clear button's slot is always there, so typing the first letter moves nothing.
struct NativeCallSheetSearchField: View {
    @Binding var text: String
    let prompt: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: CompoundDesignTokens.space2X) {
            Image(systemName: "magnifyingglass")
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.iconSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(.compound.textSecondary))
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($isFocused)
                .accessibilityLabel(prompt)
            Button {
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.iconTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .opacity(text.isEmpty ? 0 : 1)
            .allowsHitTesting(!text.isEmpty)
            .accessibilityHidden(text.isEmpty)
            .accessibilityLabel(L10n.actionClear)
        }
        .padding(.leading, CompoundDesignTokens.space4X)
        .padding(.trailing, CompoundDesignTokens.space2X)
        .padding(.vertical, CompoundDesignTokens.space1X)
        // The system's search field height; it grows with the text.
        .frame(minHeight: 44)
        .contentShape(.capsule)
        .onTapGesture { isFocused = true }
        .nativeCallSurface(in: Capsule())
        // As the rows: past AX2 the field's words no longer fit the sheet's width.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
