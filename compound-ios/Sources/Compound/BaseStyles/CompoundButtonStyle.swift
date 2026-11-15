//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

public extension ButtonStyle where Self == CompoundButtonStyle {
    /// A button style that applies Compound design tokens to a button with various configuration options.
    /// - Parameter kind: The kind of button being shown such as primary or secondary.
    /// - Parameter size: The button size to use. Defaults to `large`.
    /// - Parameter isRaised: The button sits on a grey surface, so a quiet fill is raised above it, as a raised text
    ///   field is. Defaults to `false`.
    static func compound(_ kind: Self.Kind, size: Self.Size = .large, isRaised: Bool = false) -> CompoundButtonStyle { // AGENT-PLATFORM (Brief 0083, decision 329)
        CompoundButtonStyle(kind: kind, size: size, isRaised: isRaised)
    }
}

/// Default button style for standalone buttons.
public struct CompoundButtonStyle: ButtonStyle {
    var kind: Kind
    public enum Kind {
        // AGENT-PLATFORM (Brief 0083, decision 293): one button set, without Element's gradient and outline.
        /// Drawn as ``primary``, and kept so that its call sites stay.
        case `super`
        /// A filled button usually representing the default action.
        case primary
        /// A quiet filled button usually representing alternate actions.
        case secondary
        /// A plain button with matching dimensions to ``primary`` and ``secondary``.
        case tertiary
        /// A plain button with no padding.
        case textLink
    }
    
    var size: Size
    public enum Size {
        /// A button that is prominently sized.
        case large
        /// A button that is a regular size.
        case medium
        /// A button that is a small size.
        case small
        /// A (super/primary/secondary) button that should be place within a toolbar.
        case toolbarIcon
    }
    
    var isRaised = false // AGENT-PLATFORM (Brief 0083, decision 329)
    
    public func makeBody(configuration: Self.Configuration) -> some View {
        // AGENT-PLATFORM (Brief 0083): a view draws the button and takes the pressed state, so the previews can show it.
        CompoundButtonFace(kind: kind, size: size, isRaised: isRaised, role: configuration.role, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

// AGENT-PLATFORM (Brief 0083, decisions 293 and 329): Spiral's buttons, reworked in place. Every kind but the text link
// is a capsule: super and primary filled blue, secondary a quiet fill one surface step above what it sits on, tertiary
// plain. Large is 52 pt, medium 44 pt and small 32 pt at the default text size; a larger text size grows them. With
// Button Shapes on, a tertiary takes the secondary's fill and a secondary gains a ring.
/// What a ``CompoundButtonStyle`` draws for a button's role and pressed state.
struct CompoundButtonFace<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityShowButtonShapes) private var accessibilityShowButtonShapes
    
    let kind: CompoundButtonStyle.Kind
    let size: CompoundButtonStyle.Size
    var isRaised = false
    let role: ButtonRole?
    let isPressed: Bool
    @ViewBuilder let label: Label
    
    private var isDestructive: Bool {
        role == .destructive
    }
    
    private var font: Font {
        if kind == .textLink, size == .small {
            .compound.bodyMDSemibold
        } else {
            .compound.bodyLGSemibold
        }
    }
    
    private var horizontalPadding: CGFloat {
        if kind == .textLink {
            return 0
        }
        
        return switch size {
        case .large: 20
        case .medium: 20
        case .small: 16
        case .toolbarIcon: 3
        }
    }
    
    private var verticalPadding: CGFloat {
        if kind == .textLink {
            return 0
        }
        
        return switch size {
        case .large: 15
        case .medium: 11
        case .small: 5
        case .toolbarIcon: 3
        }
    }
    
    /// The height at the default text size, which a larger text size grows. A one-line label is about 20 pt tall, so
    /// the paddings alone would leave the button 2 pt short of it.
    private var minHeight: CGFloat? {
        if kind == .textLink {
            return nil
        }
        
        return switch size {
        case .large: 52
        case .medium: 44
        case .small: 32
        case .toolbarIcon: nil
        }
    }
    
    private var maxWidth: CGFloat? {
        if kind == .textLink {
            return nil
        }
        
        return switch size {
        case .large: .infinity
        case .medium: nil
        case .small: nil
        case .toolbarIcon: nil
        }
    }
    
    private var pressedOpacity: Double {
        colorScheme == .light ? 0.3 : 0.6
    }
    
    private var isUnderlined: Bool {
        kind == .textLink && accessibilityShowButtonShapes
    }
    
    private var contentShape: AnyShape {
        switch kind {
        case .super, .primary, .secondary, .tertiary:
            return size == .small ? AnyShape(SmallButtonTouchShape()) : AnyShape(Capsule())
        case .textLink:
            return AnyShape(Rectangle())
        }
    }
    
    private var fillColor: Color {
        // In dark the disabled fill is a step under the secondary's, which it matched (decision 329).
        guard isEnabled else { return colorScheme == .dark ? .compound.bgCanvasDisabled : .compound.bgActionPrimaryDisabled }
        if isDestructive {
            // A darker fill like the primary's; upstream faded it, which looked disabled in light.
            return isPressed ? .compound.bgCriticalHovered : .compound.bgCriticalPrimary
        } else {
            return isPressed ? .compound.bgActionPrimaryPressed : .compound.bgActionPrimaryRest
        }
    }
    
    /// One surface step above what the button sits on (decision 329). In light: grey on the white canvas and rows, white
    /// when raised on a grey surface, as a raised text field. In dark: the grey after `bgSubtleSecondary`, a dark row's
    /// own colour, lifted by ``liftColor``, so it shows on rows and on black alike. A destructive one takes the subtle
    /// critical fill one step up: the rest step is 1.06:1 on white, this one shows like the grey, and the red label keeps
    /// 4.7:1 on it in dark, where the grey would give 3.99:1.
    private var quietFillColor: Color {
        guard isEnabled else { return .compound.bgCanvasDisabled }
        if isRaised, colorScheme == .light {
            return .compound.bgCanvasDefaultLevel1
        }
        if isDestructive {
            return .compound.bgCriticalSubtleHovered
        }
        return colorScheme == .dark ? .compound.bgActionTertiarySelected : .compound.bgSubtleSecondary
    }
    
    /// Compound's dark greys stop one step above a row's #2C2C2E (`bgActionTertiarySelected`, 1.09:1, which hardly
    /// shows), so the secondary action's wash lifts the fill to 1.27:1, about what iOS's tertiary fill gives there.
    private var liftColor: Color {
        colorScheme == .dark && isEnabled && !isDestructive ? .compound.bgActionSecondaryPressed : .clear
    }
    
    private var textColor: Color {
        // A disabled primary's label dims too (decision 322), so its dark fill doesn't look tappable; upstream kept the
        // on-solid ink.
        guard isEnabled else { return .compound.textDisabled }
        switch kind {
        case .super, .primary:
            return .compound.textOnSolidPrimary
        case .secondary:
            // Its fill shows the press, so the label keeps its contrast and a pressed button doesn't look disabled.
            return isDestructive ? .compound.textCriticalPrimary : .compound.textActionPrimary
        case .tertiary, .textLink:
            let textColor: Color = isDestructive ? .compound.textCriticalPrimary : .compound.textActionPrimary
            return textColor.opacity(isPressed ? pressedOpacity : 1)
        }
    }
    
    var body: some View {
        label
            .font(font)
            .underline(isUnderlined)
            .multilineTextAlignment(.center)
            .foregroundColor(textColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: maxWidth, minHeight: minHeight)
            .background {
                background
            }
            .contentShape(contentShape)
    }
    
    @ViewBuilder
    private var background: some View {
        switch kind {
        case .super, .primary:
            Capsule().fill(fillColor)
        case .secondary:
            quietBackground(hasRing: accessibilityShowButtonShapes)
        case .tertiary:
            if accessibilityShowButtonShapes {
                quietBackground(hasRing: false)
            }
        case .textLink:
            EmptyView()
        }
    }
    
    /// The quiet fill, darkened while pressed. The 1 pt ring for Button Shapes is the capsule filled under an inset
    /// fill, like the text field's: a stroked capsule drew a straight bar at each end in iOS 27's snapshots.
    private func quietBackground(hasRing: Bool) -> some View {
        Capsule().fill(hasRing ? Color.compound.borderInteractiveHovered : .clear)
            .overlay(Capsule().inset(by: hasRing ? 1 : 0).fill(quietFillColor))
            .overlay(Capsule().inset(by: hasRing ? 1 : 0).fill(liftColor))
            .overlay(Capsule().inset(by: hasRing ? 1 : 0).fill(isPressed ? Color.compound.bgActionSecondaryPressed : .clear))
    }
}

// AGENT-PLATFORM (Brief 0083, decision 329).
/// A small button's touch area: its capsule and 6 pt above and below, so 44 pt at the default text size while it
/// draws 32.
private nonisolated struct SmallButtonTouchShape: Shape {
    func path(in rect: CGRect) -> Path {
        Capsule().path(in: rect.insetBy(dx: 0, dy: -6))
    }
}

// MARK: - Previews

public struct CompoundButtonStyle_Previews: PreviewProvider, TestablePreview {
    public static var previews: some View {
        ScrollView {
            states
        }
        .previewLayout(.fixed(width: 390, height: 3130)) // AGENT-PLATFORM (Brief 0083): taller buttons, pressed, raised and shapes.
    }
    
    @ViewBuilder
    public static var states: some View {
        Section {
            buttons(.large)
        } header: {
            Header(title: "Large")
        }
        
        Section {
            buttons(.medium)
        } header: {
            Header(title: "Medium")
        }
        
        Section {
            buttons(.small)
        } header: {
            Header(title: "Small")
        }
        
        // AGENT-PLATFORM (Brief 0083): a snapshot can't press a button, so these draw its face pressed.
        Section {
            pressedButtons
        } header: {
            Header(title: "Pressed")
        }
        
        // AGENT-PLATFORM (Brief 0083, decision 329): on the grey of a notice, then on a list row.
        Section {
            raisedButtons
        } header: {
            Header(title: "Raised and on a row")
        }
        
        // AGENT-PLATFORM (Brief 0083, decision 329).
        Section {
            buttonShapes
        } header: {
            Header(title: "Button Shapes")
        }
        
        Section {
            textLinks(.medium)
        } header: {
            Header(title: "Text Link")
        }
        
        Section {
            textLinks(.small)
        } header: {
            Header(title: "Text Link Small")
        }
        
        Section {
            startChat
                .padding(.bottom) // Only for the snapshot.
        } header: {
            Header(title: "Start chat")
        }
    }
    
    public static func buttons(_ size: CompoundButtonStyle.Size) -> some View {
        VStack(spacing: 8) {
            Button("Super") { }
                .buttonStyle(.compound(.super, size: size))
            
            Button("Disabled") { }
                .buttonStyle(.compound(.super, size: size))
                .disabled(true)
            
            Button("Primary") { }
                .buttonStyle(.compound(.primary, size: size))
            
            Button("Destructive", role: .destructive) { }
                .buttonStyle(.compound(.primary, size: size))
            
            Button("Disabled") { }
                .buttonStyle(.compound(.primary, size: size))
                .disabled(true)
            
            Button("Secondary") { }
                .buttonStyle(.compound(.secondary, size: size))
            
            Button("Destructive", role: .destructive) { }
                .buttonStyle(.compound(.secondary, size: size))
            
            Button("Disabled") { }
                .buttonStyle(.compound(.secondary, size: size))
                .disabled(true)
            
            Button("Tertiary") { }
                .buttonStyle(.compound(.tertiary, size: size))
            
            Button("Destructive", role: .destructive) { }
                .buttonStyle(.compound(.tertiary, size: size))
            
            Button("Disabled") { }
                .buttonStyle(.compound(.tertiary, size: size))
                .disabled(true)
        }
        .padding(.horizontal)
    }
    
    // AGENT-PLATFORM (Brief 0083).
    static var pressedButtons: some View {
        VStack(spacing: 8) {
            ForEach([CompoundButtonStyle.Kind.primary, .secondary, .tertiary], id: \.self) { kind in
                CompoundButtonFace(kind: kind, size: .large, role: nil, isPressed: true) {
                    Text("Pressed")
                }
                
                CompoundButtonFace(kind: kind, size: .large, role: .destructive, isPressed: true) {
                    Text("Destructive")
                }
            }
        }
        .padding(.horizontal)
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 329).
    static var raisedButtons: some View {
        VStack(spacing: 8) {
            VStack(spacing: 8) {
                Button("Raised") { }
                    .buttonStyle(.compound(.secondary, size: .medium, isRaised: true))
                
                Button("Destructive", role: .destructive) { }
                    .buttonStyle(.compound(.secondary, size: .medium, isRaised: true))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.compound.bgSubtleSecondary)
            
            Button("On a row") { }
                .buttonStyle(.compound(.secondary, size: .small))
                .frame(maxWidth: .infinity)
                .padding()
                .background(.compound.bgCanvasDefaultLevel1)
        }
        .padding()
        .background(.compound.bgSubtleSecondaryLevel0)
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 329).
    static var buttonShapes: some View {
        VStack(spacing: 8) {
            Button("Secondary") { }
                .buttonStyle(.compound(.secondary))
            
            Button("Tertiary") { }
                .buttonStyle(.compound(.tertiary))
            
            Button("Destructive", role: .destructive) { }
                .buttonStyle(.compound(.tertiary))
            
            Button("Text Link") { }
                .buttonStyle(.compound(.textLink))
        }
        .padding(.horizontal)
        .environment(\._accessibilityShowButtonShapes, true)
    }
    
    static func textLinks(_ size: CompoundButtonStyle.Size) -> some View {
        HStack(spacing: 20) {
            Button("Text Link") { }
                .buttonStyle(.compound(.textLink, size: size))
            
            Button("Destructive", role: .destructive) { }
                .buttonStyle(.compound(.textLink, size: size))
            
            Button("Disabled") { }
                .buttonStyle(.compound(.textLink, size: size))
                .disabled(true)
        }
        .padding(.top, 1)
    }
    
    static var startChat: some View {
        Button { } label: {
            CompoundIcon(\.plus)
        }
        .buttonStyle(.compound(.super, size: .toolbarIcon))
    }
    
    struct Header: View {
        let title: String
        
        var body: some View {
            Text(title)
                .foregroundStyle(.compound.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.leading, .top])
                .padding(.leading)
        }
    }
}
