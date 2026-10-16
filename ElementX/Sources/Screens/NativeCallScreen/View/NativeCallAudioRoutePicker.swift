//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0063): the audio route sheet (`08 · Audio routes`).

import Combine
import Compound
import SwiftUI

/// Phase 5 (G8) — the audio route sheet (`08 · Audio routes`): the real
/// routes with the active one checked. The list is the session's truth,
/// refreshed by the view model on every system route change.
struct NativeCallAudioRoutePicker: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context

    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    ForEach(context.viewState.audioRoutes) { route in
                        // `08 · Audio routes`: a leading glyph per route and
                        // the active row's name in the accent.
                        ListRow(kind: .custom {
                            Button {
                                context.send(viewAction: .selectAudioRoute(id: route.id))
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: iconName(for: route))
                                        .font(.body)
                                        .foregroundStyle(route.isActive ? Color.compound.iconAccentPrimary : Color.secondary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(route.name)
                                            .font(.body)
                                            .foregroundStyle(route.isActive ? Color.compound.textActionAccent : Color.primary)

                                        if let description = description(for: route) {
                                            Text(description)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if route.isActive {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Color.compound.iconAccentPrimary)
                                    }
                                }
                                .contentShape(.rect)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(route.isActive ? .isSelected : [])
                        })
                    }
                }
            }
            .compoundList()
            .navigationTitle(UntranslatedL10n.screenNativeCallAudioRoutesTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func iconName(for route: NativeCallAudioRoute) -> String {
        switch route.kind {
        case .receiver: "iphone"
        case .speaker: "speaker.wave.2"
        case .external: "headphones"
        }
    }

    private func description(for route: NativeCallAudioRoute) -> String? {
        guard route.kind == .external else { return nil }
        return route.isActive
            ? UntranslatedL10n.screenNativeCallAudioRouteConnected
            : UntranslatedL10n.screenNativeCallAudioRouteBluetooth
    }
}

// MARK: - Previews

struct NativeCallAudioRoutePicker_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()

    static var previews: some View {
        NativeCallAudioRoutePicker(context: viewModel.context)
            .previewDisplayName("Routes")
    }

    /// `08 · Audio routes`: AirPods active, the built-ins, and a second
    /// Bluetooth device that is paired but silent.
    static func makeViewModel() -> NativeCallScreenViewModel {
        let viewModel = NativeCallScreen_Previews.makeViewModel()
        viewModel.state.audioRoutes = [.init(id: "airpods", name: "AirPods Pro", kind: .external, isActive: true),
                                       .init(id: NativeCallAudioRoute.receiverID, name: UntranslatedL10n.screenNativeCallAudioRouteIphone, kind: .receiver, isActive: false),
                                       .init(id: NativeCallAudioRoute.speakerID, name: UntranslatedL10n.screenNativeCallAudioRouteSpeaker, kind: .speaker, isActive: false),
                                       .init(id: "car", name: "Yurii's car", kind: .external, isActive: false)]
        return viewModel
    }
}
