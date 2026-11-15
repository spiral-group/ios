//
// Copyright 2024 New Vector Ltd
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// The button component for sending messages and media.
///
/// The button's size is 36pt x 36pt on iOS 26 and later, and 32pt x 32pt on iOS 18 and earlier: it sits inside the
/// composer's field.
///
/// AGENT-PLATFORM (Brief 0083): it was 44pt and 36pt, beside the field.
public struct SendButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    
    public enum Mode { case send, edit }
    /// Whether the button is for sending a new message or editing an existing one.
    private let mode: Mode
    /// The action to perform when the user triggers the button.
    private let action: () -> Void
    
    private var icon: KeyPath<CompoundIcons, Image> {
        switch mode {
        case .send: \.sendSolid
        case .edit: \.check
        }
    }
    
    private var iconColor: Color {
        guard isEnabled else { return .compound.textDisabled } // AGENT-PLATFORM (Brief 0083): the disabled primary's label
        return colorScheme == .light ? .compound.iconOnSolidPrimary : .compound.iconPrimary
    }
    
    // AGENT-PLATFORM (Brief 0083): disabled is the disabled primary's disc (decision 329), so the end of the field
    // keeps its shape; it was a bare arrow.
    private var backgroundColor: Color {
        guard isEnabled else { return colorScheme == .dark ? .compound.bgCanvasDisabled : .compound.bgActionPrimaryDisabled }
        return .compound.bgAccentRest
    }
    
    /// Creates a send button that performs the provided action.
    public init(mode: Mode = .send, action: @escaping () -> Void) {
        self.mode = mode
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            label
                .compositingGroup()
                // AGENT-PLATFORM (Brief 0083): a 44 pt target around the 36 pt disc (32 pt before iOS 26), the look unchanged.
                .padding(hitPadding)
                .contentShape(.rect)
                .padding(-hitPadding)
        }
    }
    
    private var hitPadding: CGFloat {
        Compound.supportsGlass ? 4 : 6
    }
    
    // AGENT-PLATFORM (Brief 0083): a solid disc inside the composer's glass field, as Messages draws send; glass on
    // glass isn't drawn. It was a tinted glass disc beside the field.
    public var label: some View {
        baseIcon
            .background(backgroundColor, in: .circle)
    }
    
    var baseIcon: some View {
        CompoundIcon(icon, size: Compound.supportsGlass ? .medium : .small, relativeTo: .compound.headingLG) // AGENT-PLATFORM (Brief 0083)
            .fontWeight(.semibold) // AGENT-PLATFORM (Brief 0083, decision 320): an arrow on a disc, as iOS draws send.
            .foregroundStyle(iconColor)
            // AGENT-PLATFORM (Brief 0083, question 357): the plane flies forward, right to left too; an edit keeps its check.
            .flipsForRightToLeftLayoutDirection(mode == .send)
            .scaledPadding(6, relativeTo: .compound.headingLG) // AGENT-PLATFORM (Brief 0083): 36pt, and 32pt before iOS 26
    }
}

// MARK: - Previews

public struct SendButton_Previews: PreviewProvider, TestablePreview {
    public static var previews: some View {
        VStack(spacing: 0) {
            states
                .padding(20)
                .background(.compound.bgCanvasDefault)
            states
                .padding(20)
                .background(.compound.bgCanvasDefault)
                .environment(\.colorScheme, .dark)
        }
        .cornerRadius(20)
    }
    
    public static var states: some View {
        HStack(spacing: 30) {
            SendButton { }
                .disabled(true)
            SendButton { }
            
            SendButton(mode: .edit) { }
        }
    }
}
