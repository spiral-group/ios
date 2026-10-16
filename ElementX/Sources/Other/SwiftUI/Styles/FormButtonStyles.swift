//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// Small squared action button style for settings screens
struct FormActionButtonStyle: ButtonStyle {
    let title: String
    
    // AGENT-PLATFORM: Apple contact-card style (ADR-0005) — accent icon +
    // single-line small label (long RU labels used to hyphen-wrap and
    // misalign the icons across sibling buttons).
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.label
                .buttonStyle(.plain)
                .foregroundColor(.compound.iconAccentPrimary)
                .scaledFrame(size: 24)
            
            Text(title)
                .foregroundColor(.compound.textPrimary)
                .font(.compound.bodySM)
                .textCase(.none)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(configuration.isPressed ? Color.compound.bgSubtlePrimary : .compound.bgCanvasDefaultLevel1)
        }
    }
}

struct FormButtonStyles_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        Form {
            Section { } header: {
                Button { } label: {
                    CompoundIcon(\.shareIos)
                }
                .buttonStyle(FormActionButtonStyle(title: "Share"))
            }
        }
        .compoundList()
    }
}
