//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SwiftUI

/// The chat-tools screens' title: what the screen is, and under it the chat or the agent it is about.
struct ToolScreenTitle: View {
    let title: String
    let subtitle: String?
    
    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.compound.bodyLGSemibold)
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
