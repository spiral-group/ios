//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, decision 386): the agent's own symbols in the call-motion lab, in their places (the
// dock's Assistant button, an Agent Center header, a tab bar of Chats, Feed, Agents and Settings) and in the colour
// treatments the operator compared: monochrome, hierarchical (the dock and the tab bar) and palette in the brand blues.
// The logo one-to-one symbols were dropped once the picks were made. Bounce and Pulse show the symbol effects.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import Compound
import SpiralTokens
import SwiftUI

struct CallMotionIconStage: View {
    enum Treatment: String, CaseIterable, Identifiable {
        case monochrome = "Mono"
        case hierarchical = "Hierarchy"
        case palette = "Palette"

        var id: Self {
            self
        }
    }

    let treatment: Treatment

    @State private var bounces = 0
    @State private var isPulsing = false
    @State private var isAgentsSelected = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: CompoundDesignTokens.space6X) {
                section("The dock's Assistant button") {
                    HStack(spacing: CompoundDesignTokens.space6X) {
                        dockButton(isInCall: false)
                        dockButton(isInCall: true)
                        // Over a picture the dock is on the dark material, as in a video call.
                        HStack(spacing: CompoundDesignTokens.space3X) {
                            dockButton(isInCall: false)
                            dockButton(isInCall: true)
                        }
                        .padding(CompoundDesignTokens.space2X)
                        .background { CallMotionSamplePicture(scene: .bright).clipShape(RoundedRectangle(cornerRadius: SpiralRadius.listCard)) }
                        .environment(\.colorScheme, .dark)
                        .environment(\.nativeCallIsOverPicture, true)
                    }
                }

                section("Agent Center") {
                    HStack(spacing: CompoundDesignTokens.space3X) {
                        peek(onAccent: false)
                            .font(.compound.headingMD)
                            .frame(width: 44, height: 44)
                            .background(Color.compound.bgSubtleSecondary, in: Circle())
                        VStack(alignment: .leading, spacing: CompoundDesignTokens.space0_5X) {
                            Text("Assistants")
                                .font(.compound.headingSMSemibold)
                            Text("Your assistant · in the call")
                                .font(.compound.bodySM)
                                .foregroundStyle(.compound.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(CompoundDesignTokens.space4X)
                    .background(Color.compound.bgCanvasDefault, in: RoundedRectangle(cornerRadius: SpiralRadius.listCard))
                }

                section("Tab bar") {
                    VStack(spacing: CompoundDesignTokens.space3X) {
                        tabBar(isAgentsSelected: true)
                        tabBar(isAgentsSelected: false)
                    }
                }

                section("Effects") {
                    HStack(spacing: CompoundDesignTokens.space3X) {
                        Button("Bounce (joins)") { bounces += 1 }
                        Button(isPulsing ? "Stop pulse" : "Pulse (thinking)") { isPulsing.toggle() }
                        Button("Select Agents") { isAgentsSelected.toggle() }
                    }
                    .buttonStyle(.bordered)
                    .font(.compound.bodySM)
                }

                Text(note)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .padding(.horizontal, CompoundDesignTokens.space6X)
            }
            .padding(.vertical, CompoundDesignTokens.space8X)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { NativeCallBackdrop(tone: .wash).ignoresSafeArea() }
    }

    // MARK: - Places

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
            Text(title)
                .font(.compound.bodySMSemibold)
                .foregroundStyle(.compound.textSecondary)
            content()
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The dock's round control: white on the accent while the assistant is in, the ink on glass when it isn't.
    private func dockButton(isInCall: Bool) -> some View {
        peek(onAccent: isInCall)
            .font(.compound.headingMD)
            .foregroundStyle(isInCall ? AnyShapeStyle(Color.compound.iconOnSolidPrimary) : AnyShapeStyle(.primary))
            .frame(width: 60, height: 60)
            .background { if isInCall { Circle().fill(Color.compound.bgAccentRest) } }
            .modifier(OffSurface(isOn: !isInCall))
    }

    private func tabBar(isAgentsSelected: Bool) -> some View {
        HStack(spacing: 0) {
            tab("Chats", selected: false) { CompoundIcon(\.chat) }
            tab("Feed", selected: false) { CompoundIcon(\.home) }
            tab("Agents", selected: isAgentsSelected) {
                peek(onAccent: false)
                    .font(.compound.headingMD)
            }
            tab("Settings", selected: !isAgentsSelected) { CompoundIcon(isAgentsSelected ? \.userProfile : \.userProfileSolid) }
        }
        .padding(.vertical, CompoundDesignTokens.space2X)
        .spiralGlass(in: Capsule())
    }

    private func tab(_ title: String, selected: Bool, @ViewBuilder icon: () -> some View) -> some View {
        VStack(spacing: CompoundDesignTokens.space0_5X) {
            icon()
                .frame(height: 28)
            Text(title)
                .font(.compound.bodyXSSemibold)
        }
        .foregroundStyle(selected ? Color.compound.iconAccentPrimary : Color.compound.iconSecondary)
        .frame(maxWidth: .infinity)
    }

    // MARK: - The Peek in each treatment

    @ViewBuilder
    private func peek(onAccent: Bool) -> some View {
        switch treatment {
        case .monochrome:
            effects(Image("spiral.peek.fill").symbolRenderingMode(.monochrome))
        case .hierarchical:
            effects(Image("spiral.peek.layers").symbolRenderingMode(.hierarchical))
        case .palette:
            // Head and wave in two brand blues, lighter in dark so nothing sinks; white and a pale blue on the accent.
            effects(Image("spiral.peek.layers")
                .symbolRenderingMode(.palette)
                .foregroundStyle(onAccent ? Color.white : brandBlue, onAccent ? paleBlue : lightBlue))
        }
    }

    private func effects(_ image: some View) -> some View {
        image
            .symbolEffect(.bounce, value: bounces)
            .symbolEffect(.pulse, isActive: isPulsing)
    }

    // The brand blues (blue/500 and blue/300 of the tokens), light and dark.
    private var brandBlue: Color {
        colorScheme == .dark ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color(red: 0.18, green: 0.42, blue: 0.9)
    }

    private var lightBlue: Color {
        colorScheme == .dark ? Color(red: 0.42, green: 0.7, blue: 1.0) : Color(red: 0.48, green: 0.65, blue: 0.94)
    }

    private var paleBlue: Color {
        Color(red: 0.75, green: 0.83, blue: 0.98)
    }

    private var note: String {
        switch treatment {
        case .monochrome: "The app's default: one colour from the tint, as the system symbols beside it."
        case .hierarchical: "One colour: the head full, the wave at the system's secondary opacity."
        case .palette: "Two brand blues, set for light and dark; on the accent the head is white."
        }
    }
}

/// The off control's glass, through the call's own surface.
private struct OffSurface: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.nativeCallSurface(in: Circle(), isInteractive: true)
        } else {
            content
        }
    }
}

#endif
