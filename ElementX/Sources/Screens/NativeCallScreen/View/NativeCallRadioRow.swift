//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): the design's leading-radio list row —
// WHAT YOU HEAR (`10`), the booth style (`13`), the who-scope picker.

import Compound
import SwiftUI

/// `10 · Agent Center`'s WHAT YOU HEAR rows: a leading radio, the channel
/// name, and `No translation` under Original. `13 · Booths` reuses it for
/// the interpreting style with a third, accent-tinted line.
struct NativeCallRadioRow: View {
    let title: String
    var subtitle: String?
    /// The style rows' third line (`Several languages, played in order`),
    /// tinted accent on the selected row.
    var detail: String?
    /// `13 · Booths` washes the SELECTED style row in the accent tint.
    /// Drawn inside the row — `ListRow` overrides `listRowBackground`.
    var showsSelectedWash = false
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        ListRow(kind: .custom {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "inset.filled.circle" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.compound.iconAccentPrimary : Color(.tertiaryLabel))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(.primary)

                        if let subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(isSelected ? Color.compound.textActionAccent : Color(.tertiaryLabel))
                        }
                    }

                    Spacer()
                }
                .contentShape(.rect)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(showsSelectedWash && isSelected ? Color.compound.iconAccentPrimary.opacity(0.12) : .clear)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        })
    }
}
