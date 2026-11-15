//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 387): the call's "Assistants" sheet in every state, on the call's real screen,
// without a real call. The sheet opens over the call as it does from the dock; the menu at the top picks the state
// (`NativeCallAssistantsLabState`). Done closes the sheet, and the dock's Assistant button opens it again. No platform
// is behind it, so a write shows its progress and changes nothing; every state is one pick away instead.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import Compound
import SpiralTokens
import SwiftUI

struct CallMotionLabAssistantsStage: View {
    @Binding var state: NativeCallAssistantsLabState
    /// The lab's own panel is away: one sheet at a time.
    let canPresent: Bool

    @Environment(\.nativeCallVoiceLevels) private var levels
    @State private var renderer = CallMotionLabVideoRenderer()
    @State private var model: NativeCallScreenViewModel?

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if let model {
                NativeCallScreen(context: model.context, videoRenderer: renderer, voiceLevels: levels)
            }
            Menu {
                Picker("Assistants", selection: $state) {
                    ForEach(NativeCallAssistantsLabState.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label(state.rawValue, systemImage: "list.bullet")
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .padding(.horizontal, CompoundDesignTokens.space3X)
                    .padding(.vertical, CompoundDesignTokens.space2X)
                    .spiralGlass(in: Capsule(), isInteractive: true)
            }
            .padding(.top, CompoundDesignTokens.space2X)
        }
        .task(id: state) {
            model = NativeCallAssistantsLabModel.make(state)
            await present()
        }
        .onChange(of: canPresent) { _, canPresent in
            if canPresent { Task { await present() } }
        }
    }

    private func present() async {
        guard canPresent, let model else { return }
        // After the lab's own panel has gone.
        try? await Task.sleep(for: .milliseconds(600))
        model.context.isAgentCenterPresented = true
    }
}

#endif
