//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

// TODO: @pixlwave Check if the primitive style is actually needed now the insets are part of ListRow.
// It might still be useful for ListRow(kind: .custom) usage?

/// Default button styling for list rows.
///
/// The primitive style is needed to set the list row insets to `0`. The inner style is then needed
/// to change the background colour depending on whether the button is currently pressed or not.
public struct ListRowButtonStyle: PrimitiveButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
        }
        .buttonStyle(Style())
    }
    
    /// Inner style used to set the pressed background colour.
    struct Style: ButtonStyle {
        @Environment(\.listRowFill) private var fill // AGENT-PLATFORM (Brief 0083): `spiralGroupedList()` sets it.
        
        /// AGENT-PLATFORM: draws the pressed state, so the previews can show it.
        fileprivate var isPressedInPreview = false
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .contentShape(Rectangle())
                // AGENT-PLATFORM: Spiral's bgSubtlePrimary is the row's own white in light mode, so the
                // press darkens the row instead (bgActionSecondaryPressed is a translucent gray).
                .background {
                    fill // AGENT-PLATFORM (Brief 0083): was `Color.compound.bgCanvasDefaultLevel1`.
                        .overlay(configuration.isPressed || isPressedInPreview ? Color.compound.bgActionSecondaryPressed : .clear)
                }
        }
    }
}

// MARK: - Previews

// TODO: @pixlwave Fix the previews, either the style should expand the label to fill or
// the previews need to do this manually for demonstration purposes.

public struct ListRowButtonStyle_Previews: PreviewProvider, TestablePreview {
    public static var previews: some View {
        Form {
            Section {
                Button("Title") { }
                    .buttonStyle(ListRowButtonStyle.Style())
                // AGENT-PLATFORM: the pressed row.
                Button("Pressed") { }
                    .buttonStyle(ListRowButtonStyle.Style(isPressedInPreview: true))
            }
            .listRowInsets(EdgeInsets())
            
            Section {
                Button("Title") { }
                Button("Title") { }
                Button("Title") { }
            }
            .buttonStyle(ListRowButtonStyle())
            .listRowInsets(EdgeInsets())
            
            Section {
                ShareLink(item: "test")
                    .buttonStyle(ListRowButtonStyle())
            }
            .listRowInsets(EdgeInsets())
        }
        .compoundList()
    }
}
