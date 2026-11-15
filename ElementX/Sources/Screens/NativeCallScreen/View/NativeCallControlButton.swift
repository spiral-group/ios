//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): the call's controls. Brief 0083 phase 4 (lane call-v2, decisions 339 and 340): one
// model of the controls, drawn as one big glass dock with End across it.

import Compound
import SpiralTokens
import SwiftUI

/// One control of the call, as the screen builds it from its state.
struct NativeCallControl: Identifiable {
    enum Kind {
        /// Mute, video, sound, flip. On fills the control with the ink, as the system's call screens mark it.
        case toggle(isOn: Bool)
        /// Decision 300d: the same control as the others, filled with the accent only while the assistant is in the call.
        case assistant(isInCall: Bool)
        case end
    }

    /// A system symbol, or one of Spiral's own (decision 386: the assistant is the Peek, never `sparkles`), drawn in one
    /// ink like Mute, Video and Sound in every state (question 401, remark 16: two tones made it stand out).
    enum Symbol {
        case system(String)
        case spiral(String)

        var image: Image {
            switch self {
            case .system(let name): Image(systemName: name)
            case .spiral(let name): Image(name).symbolRenderingMode(.monochrome)
            }
        }
    }

    let id: String
    let symbol: Symbol
    let title: String
    let kind: Kind
    let accessibilityLabel: String
    var accessibilityHint: String?
    /// The sound control's long press opens the audio routes (G8).
    var longPressAction: (() -> Void)?
    let action: () -> Void

    var isEnd: Bool {
        if case .end = kind { return true }
        return false
    }

    /// A solid fill when the control is on, the assistant is in, or it ends the call; nil draws the dock's quiet wash.
    var fill: Color? {
        switch kind {
        case .toggle(isOn: true): .compound.iconPrimary
        case .assistant(isInCall: true): .compound.bgAccentRest
        case .end: .compound.bgCriticalPrimary
        case .toggle, .assistant: nil
        }
    }

    var ink: Color {
        switch kind {
        case .toggle(isOn: true): .compound.bgCanvasDefault
        case .assistant(isInCall: true), .end: .compound.iconOnSolidPrimary
        case .toggle, .assistant: .compound.iconPrimary
        }
    }
}

/// The tap, the long press and what VoiceOver reads, around a control's drawing.
struct NativeCallControlButton<Label: View>: View {
    let control: NativeCallControl
    @ViewBuilder let label: Label

    var body: some View {
        let button = Button(action: control.action) {
            label.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(control.accessibilityLabel)
        .accessibilityHint(control.accessibilityHint ?? "")

        if let longPressAction = control.longPressAction {
            button.simultaneousGesture(LongPressGesture().onEnded { _ in longPressAction() })
        } else {
            button
        }
    }
}

// MARK: - The glass dock

/// The call's controls as Liquid Glass (question 383): the round toggles are glass circles in one container, so they
/// merge and morph as the system's own controls do (over a live picture, the dark regular material: see
/// `NativeCallSurface`); End stays a solid red capsule.
/// A toggle that is on, or the assistant while it's in the call, is a solid fill, not tinted glass (decision 346).
/// Before iOS 26 each glass falls back to the regular material, as every Spiral surface does.
struct NativeCallGlassDock: View {
    let controls: [NativeCallControl]
    /// Captions under the circles read on the call's own field. Over a picture they would sit on whatever it shows,
    /// so the video stage keeps the glyphs and their accessibility labels only.
    var showsCaptions = true

    var body: some View {
        VStack(spacing: CompoundDesignTokens.space4X) {
            SpiralGlassGroup(spacing: CompoundDesignTokens.space3X) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(controls.filter { !$0.isEnd }) { control in
                        NativeCallRoundControl(control: control, showsCaption: showsCaptions)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if let end = controls.first(where: \.isEnd) {
                NativeCallEndCapsule(control: end)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, CompoundDesignTokens.space6X)
        .padding(.top, CompoundDesignTokens.space2X)
        .padding(.bottom, CompoundDesignTokens.space3X)
    }
}

/// A round control with its caption underneath.
private struct NativeCallRoundControl: View {
    let control: NativeCallControl
    let showsCaption: Bool

    var body: some View {
        NativeCallControlButton(control: control) {
            VStack(spacing: CompoundDesignTokens.space2X) {
                circle

                if showsCaption {
                    Text(control.title)
                        .font(.compound.bodySMSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    private var circle: some View {
        NativeCallRoundCircle(image: control.symbol.image, fill: control.fill, ink: control.ink)
    }
}

/// The dock's round control, drawn: a 60 pt circle of the call's glass, or a solid fill while on, with its glyph. The
/// Assistants sheet's job buttons are the same circle (Brief 0085, L5): a ring marks one waiting (blue) or refused
/// (red), and a spinner one whose write is out.
struct NativeCallRoundCircle: View {
    static let diameter: CGFloat = 60

    let image: Image
    var fill: Color?
    var ink: Color = .compound.iconOnSolidPrimary
    var ring: Color?
    var isBusy = false
    /// An unavailable button's glyph fades; the glass under it can't.
    var glyphOpacity: Double = 1

    var body: some View {
        let glyph = ZStack {
            if isBusy {
                ProgressView()
                    .tint(fill == nil ? Color.compound.iconSecondary : ink)
            } else {
                image.font(.compound.headingMD)
                    .opacity(glyphOpacity)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)

        if let fill {
            glyph
                .foregroundStyle(ink)
                .background(fill, in: Circle())
        } else {
            // On glass the glyph takes the primary style, which glass keeps legible over a bright or dark picture.
            // The ring is the glass's content, as the glyph is: drawn over it, a glass container composites it under.
            glyph
                .foregroundStyle(ring.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .overlay {
                    if let ring {
                        Circle().strokeBorder(ring, lineWidth: 2)
                    }
                }
                .nativeCallSurface(in: Circle(), isInteractive: true)
        }
    }
}

/// End across the dock: red, the glyph and the word, unmistakable at a glance. A solid capsule, not the system's
/// prominent glass: that lightens the red until the white word reads 3.85:1 (measured in the lab, question 383), and
/// the solid critical fill keeps it at 4.5:1 (decision 307).
private struct NativeCallEndCapsule: View {
    let control: NativeCallControl

    var body: some View {
        NativeCallControlButton(control: control) {
            label
                .background(control.fill ?? .compound.bgCriticalPrimary, in: Capsule())
        }
    }

    private var label: some View {
        HStack(spacing: CompoundDesignTokens.space2X) {
            control.symbol.image
                .font(.compound.headingSM)

            Text(control.title)
                .font(.compound.bodyLGSemibold)
                .lineLimit(1)
        }
        .foregroundStyle(control.ink)
        .frame(maxWidth: .infinity, minHeight: 56)
        .contentShape(.capsule)
    }
}
