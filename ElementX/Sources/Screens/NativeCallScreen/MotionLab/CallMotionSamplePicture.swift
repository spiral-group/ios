//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): what the call-motion lab's stages share: a drawn stand-in for a camera
// picture, and the dock's controls for stages that show the dock without a call.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import Compound
import SwiftUI

enum CallMotionLabControls {
    static let controls = [
        NativeCallControl(id: "assistant", symbol: .spiral("spiral.peek.layers"), title: "Assistant", kind: .assistant(isInCall: true),
                          accessibilityLabel: "Assistant") { },
        NativeCallControl(id: "mute", symbol: .system("mic"), title: "Mic", kind: .toggle(isOn: false),
                          accessibilityLabel: "Mic") { },
        NativeCallControl(id: "video", symbol: .system("video"), title: "Video", kind: .toggle(isOn: true),
                          accessibilityLabel: "Video") { },
        NativeCallControl(id: "sound", symbol: .system("speaker.wave.2"), title: "Sound", kind: .toggle(isOn: false),
                          accessibilityLabel: "Sound") { },
        NativeCallControl(id: "end", symbol: .system("phone.down.fill"), title: "End", kind: .end,
                          accessibilityLabel: "End") { }
    ]
}

/// A stand-in for a camera picture: an overcast sky and snow for the bright case white text struggles on, a dim room
/// for the usual one. Drawn, so it holds nobody's face.
struct CallMotionSamplePicture: View {
    enum Scene: String, CaseIterable, Identifiable {
        case bright = "Bright"
        case dim = "Dim"

        var id: Self {
            self
        }
    }

    let scene: Scene

    var body: some View {
        Canvas { context, size in
            switch scene {
            case .bright: drawBright(in: &context, size: size)
            case .dim: drawDim(in: &context, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawBright(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(white: 0.97), Color(red: 0.8, green: 0.88, blue: 0.95)]),
                                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.55)))
        let sun = CGRect(x: size.width * 0.62, y: size.height * 0.08, width: size.width * 0.5, height: size.width * 0.5)
        context.fill(Path(ellipseIn: sun), with: .radialGradient(Gradient(colors: [.white, .white.opacity(0)]),
                                                                 center: CGPoint(x: sun.midX, y: sun.midY), startRadius: 0, endRadius: sun.width / 2))
        var hills = Path()
        hills.move(to: CGPoint(x: 0, y: size.height * 0.55))
        hills.addCurve(to: CGPoint(x: size.width, y: size.height * 0.5),
                       control1: CGPoint(x: size.width * 0.3, y: size.height * 0.42),
                       control2: CGPoint(x: size.width * 0.65, y: size.height * 0.62))
        hills.addLine(to: CGPoint(x: size.width, y: size.height))
        hills.addLine(to: CGPoint(x: 0, y: size.height))
        context.fill(hills, with: .color(Color(red: 0.55, green: 0.66, blue: 0.6)))
        var snow = Path()
        snow.move(to: CGPoint(x: 0, y: size.height * 0.68))
        snow.addCurve(to: CGPoint(x: size.width, y: size.height * 0.64),
                      control1: CGPoint(x: size.width * 0.4, y: size.height * 0.6),
                      control2: CGPoint(x: size.width * 0.7, y: size.height * 0.72))
        snow.addLine(to: CGPoint(x: size.width, y: size.height))
        snow.addLine(to: CGPoint(x: 0, y: size.height))
        context.fill(snow, with: .linearGradient(Gradient(colors: [Color(white: 0.9), .white]),
                                                 startPoint: CGPoint(x: 0, y: size.height * 0.64), endPoint: CGPoint(x: 0, y: size.height)))
    }

    private func drawDim(in context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.38, blue: 0.34), Color(red: 0.2, green: 0.18, blue: 0.17)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let window = CGRect(x: size.width * 0.08, y: size.height * 0.06, width: size.width * 0.42, height: size.height * 0.34)
        context.fill(Path(window), with: .linearGradient(Gradient(colors: [Color(white: 0.95), Color(red: 0.75, green: 0.82, blue: 0.9)]),
                                                         startPoint: CGPoint(x: window.minX, y: window.minY), endPoint: CGPoint(x: window.maxX, y: window.maxY)))
        let lamp = CGRect(x: size.width * 0.6, y: size.height * 0.5, width: size.width * 0.5, height: size.width * 0.5)
        context.fill(Path(ellipseIn: lamp), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.7), .clear]),
                                                                  center: CGPoint(x: lamp.midX, y: lamp.midY), startRadius: 0, endRadius: lamp.width / 2))
        context.fill(Path(CGRect(x: 0, y: size.height * 0.78, width: size.width, height: size.height * 0.22)),
                     with: .color(Color(red: 0.55, green: 0.45, blue: 0.36)))
    }
}

#endif
