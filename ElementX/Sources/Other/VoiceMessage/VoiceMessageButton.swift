//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct VoiceMessageButton: View {
    @Environment(\.ownBubbleInk) private var ownBubbleInk // AGENT-PLATFORM (Brief 0083)
    @ScaledMetric private var buttonSize: CGFloat
    
    enum State {
        case loading
        case playing
        case paused
    }
    
    enum Size {
        case small
        case medium
    }
    
    let state: State
    let action: () -> Void
    
    let iconSize: CompoundIcon.Size
    let iconColor: Color
    
    private static let minimumTapTarget: CGFloat = 44 // AGENT-PLATFORM (S7)
    
    /// AGENT-PLATFORM: draws the pressed state, so the previews can show it.
    fileprivate var isPressedInPreview = false
    
    init(state: State, size: Size, action: @escaping () -> Void) {
        switch size {
        case .small:
            _buttonSize = .init(wrappedValue: 30)
            iconSize = .small
            iconColor = .compound.iconPrimary
        case .medium:
            // AGENT-PLATFORM (S7): 32, not 36. In a voice message's bubble the 36 pt disc set the bubble's height and
            // left it 8 pt above and below, under a 16 pt corner, so it read as not fitting (operator, 2026-11-12). At 32
            // the speed and time column sets the height: 9 pt above and below at the default size, 11 at xxxLarge.
            _buttonSize = .init(wrappedValue: 32)
            iconSize = .medium
            iconColor = .compound.iconSecondary
        }
        
        self.state = state
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            buttonLabel
                .frame(width: buttonSize, height: buttonSize)
                .overlay {
                    Circle().stroke(.compound.borderInteractiveSecondary)
                }
                // AGENT-PLATFORM (S7): the disc is smaller than a finger, so the target reaches 44 pt around it.
                .contentShape(.interaction, Circle().inset(by: -max(0, (Self.minimumTapTarget - buttonSize) / 2)))
        }
        .animation(nil, value: state)
        .buttonStyle(VoiceMessageButtonStyle(color: ownBubbleInk?.onStrongFill ?? iconColor, fill: ownBubbleInk?.strongFill ?? .compound.bgCanvasDefault, isPressedInPreview: isPressedInPreview)) // AGENT-PLATFORM
        .disabled(state == .loading)
        .accessibilityLabel(accessibilityLabel)
    }
    
    @ViewBuilder
    private var buttonLabel: some View {
        switch state {
        case .loading:
            ProgressView()
        case .playing, .paused:
            CompoundIcon(state == .playing ? \.pauseSolid : \.playSolid,
                         size: iconSize,
                         relativeTo: .compound.headingLG)
        }
    }
    
    private var accessibilityLabel: String {
        switch state {
        case .loading:
            return ""
        case .playing:
            return L10n.a11yPause
        case .paused:
            return L10n.a11yPlay
        }
    }
}

private struct VoiceMessageButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled: Bool
    
    let color: Color
    let fill: Color // AGENT-PLATFORM (Brief 0083)
    let isPressedInPreview: Bool // AGENT-PLATFORM
    
    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || isPressedInPreview // AGENT-PLATFORM
        configuration.label
            // AGENT-PLATFORM: Spiral's iconDisabled is #E5E5EA in light mode, almost white on the white disc.
            .foregroundColor(isEnabled ? color.opacity(isPressed ? 0.6 : 1) : .compound.textDisabled)
            // AGENT-PLATFORM: Spiral's bgSubtlePrimary is the disc's own white in light mode, so the
            // press darkens the disc instead (bgActionSecondaryPressed is a translucent gray).
            .background {
                Circle()
                    .fill(fill)
                    .overlay {
                        if isPressed {
                            Circle().fill(Color.compound.bgActionSecondaryPressed)
                        }
                    }
            }
    }
}

extension VoiceMessageButton.State {
    init(_ state: AudioPlayerPlaybackState) {
        switch state {
        case .loading:
            self = .loading
        case .playing:
            self = .playing
        case .stopped, .error, .readyToPlay:
            self = .paused
        }
    }
}

struct VoiceMessageButton_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                VoiceMessageButton(state: .paused, size: .small) { }
                VoiceMessageButton(state: .paused, size: .medium) { }
            }
            HStack(spacing: 8) {
                VoiceMessageButton(state: .playing, size: .small) { }
                VoiceMessageButton(state: .playing, size: .medium) { }
            }
            // AGENT-PLATFORM: pressed, and disabled.
            HStack(spacing: 8) {
                VoiceMessageButton(state: .paused, size: .small) { }
                    .pressedInPreview()
                VoiceMessageButton(state: .paused, size: .medium) { }
                    .pressedInPreview()
            }
            HStack(spacing: 8) {
                VoiceMessageButton(state: .paused, size: .small) { }
                VoiceMessageButton(state: .paused, size: .medium) { }
            }
            .disabled(true)
        }
        .padding()
        .background(.compound.bgSubtleSecondary)
    }
}

private extension VoiceMessageButton {
    func pressedInPreview() -> Self { // AGENT-PLATFORM
        var button = self
        button.isPressedInPreview = true
        return button
    }
}
