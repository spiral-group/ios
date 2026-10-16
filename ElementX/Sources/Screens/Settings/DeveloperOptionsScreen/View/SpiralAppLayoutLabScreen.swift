//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066 step 6.11): the LAYOUT LAB.
//
// A generated chess board came out with collapsed ranks and nothing in the
// pipeline could see it (2026-09-18). This screen mounts an artifact in the
// REAL post frame — the row's width, the aspect's box — and then the SAME
// instance in the viewer's box (402×758) with the viewport push the
// full-screen cover sends, while the runtime's ruler reports into the app
// log. Two sources: the shell's gallery of reference patterns (`lab`), and
// the clipboard (`xcrun simctl pbcopy <udid> < bundle.jsx`), which may carry
// MANY modules separated by `// ===== <id> <aspect>` lines. "Run all" walks
// them unattended: row, full, next. The log is the result.
//

import SpiralAppShell
import SwiftUI

struct SpiralAppLayoutLabScreen: View {
    enum Source: String, CaseIterable {
        case gallery
        case clipboard
    }

    enum Box: String, CaseIterable {
        case row
        case full
    }

    struct Module: Identifiable {
        let id: String
        let aspect: String
        let source: String
    }

    @AppStorage("spiralLabSource") private var source = Source.gallery.rawValue
    @AppStorage("spiralLabAspect") private var aspect = "4:3"
    @StateObject private var preview = DraftPreview()
    @State private var status = "Pick a source, then Mount."
    @State private var reclaimCount = 0
    @State private var box = Box.row
    @State private var modules: [Module] = []
    @State private var index = 0
    @State private var mounted: Module?
    @State private var run: Task<Void, Never>?

    private let aspects = ["4:3", "1:1", "3:4", "16:9", "3:2"]
    /// The bubble's width in a thread; the viewer's box on this phone.
    ///
    /// 724, not 758: the viewer stops above the home indicator since
    /// 763f1bfbc, and the lab measuring the old box let a post that fitted
    /// 758 but not 724 pass here and fail in the viewer.
    private let rowWidth: CGFloat = 322
    private let fullSize = CGSize(width: 402, height: 724)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                controls
                if let mounted {
                    Text("\(mounted.id) · \(mounted.aspect) · \(box.rawValue)")
                        .font(.compound.bodySMSemibold)
                    surfaceBox(for: mounted)
                }
            }
            .padding(16)
        }
        .navigationTitle("Layout lab")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            run?.cancel()
            preview.stop()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Source", selection: $source) {
                Text("Gallery").tag(Source.gallery.rawValue)
                Text("Bundle").tag(Source.clipboard.rawValue)
            }
            .pickerStyle(.segmented)

            HStack {
                Picker("Aspect", selection: $aspect) {
                    ForEach(aspects, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                Spacer()
                Picker("Box", selection: $box) {
                    ForEach(Box.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .onChange(of: box) { _, new in
                    preview.setViewport(new == .full ? .expanded : .row)
                }
            }

            HStack {
                Button("Mount") { load(); mount(at: 0) }
                Spacer()
                Button("Prev") { mount(at: index - 1) }.disabled(modules.count < 2)
                Button("Next") { mount(at: index + 1) }.disabled(modules.count < 2)
                Spacer()
                Button(run == nil ? "Run all" : "Stop") { toggleRun() }
            }
            .buttonStyle(.borderedProminent)
            .font(.compound.bodySM)

            Text(status)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        }
    }

    @ViewBuilder
    private func surfaceBox(for module: Module) -> some View {
        let ratio = Self.ratio(module.aspect)
        let size = box == .row
            ? CGSize(width: ratio < 1 ? min(rowWidth, 300 * ratio) : rowWidth,
                     height: ratio < 1 ? min(300, rowWidth / ratio) : rowWidth / ratio)
            : fullSize
        ZStack {
            Color.compound.bgSubtleSecondary
            if let instance = preview.instance {
                DraftPreviewSurface(container: instance.containerView, reclaimCount: reclaimCount)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func load() {
        switch Source(rawValue: source) ?? .gallery {
        case .gallery:
            guard let packed = SpiralAppShell.labArtifact,
                  let container = SpiralAppContainer.unpack(packed.bytes) else {
                status = "The lab artifact is not in the bundle."
                modules = []
                return
            }
            modules = [Module(id: "lab", aspect: aspect, source: String(decoding: container.source, as: UTF8.self))]
        case .clipboard:
            // The clipboard, or — because the simulator's pasteboard sync is
            // unreliable — `Documents/lab-bundle.jsx` in the app container:
            //   cp bundle.jsx "$(xcrun simctl get_app_container <udid> <bundle-id> data)/Documents/"
            // The FILE wins over the clipboard. Both are ways in, but the
            // file is a deliberate act (`cp bundle.jsx …/Documents/`) while
            // the pasteboard is ambient: a bundle copied an hour ago went on
            // being served after the file had been replaced, and the lab
            // silently measured yesterday's modules (2026-09-19).
            let file = URL.documentsDirectory.appending(path: "lab-bundle.jsx")
            let text = (try? String(contentsOf: file, encoding: .utf8))
                ?? UIPasteboard.general.string.flatMap { $0.isEmpty ? nil : $0 }
            guard let text, !text.isEmpty else {
                status = "Nothing on the clipboard and no Documents/lab-bundle.jsx."
                modules = []
                return
            }
            modules = Self.split(text, defaultAspect: aspect)
        }
        status = "\(modules.count) module(s)."
    }

    private static func split(_ text: String, defaultAspect: String) -> [Module] {
        var out: [Module] = []
        var id = "clipboard"
        var aspect = defaultAspect
        var lines: [Substring] = []
        func flush() {
            let body = lines.joined(separator: "\n")
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(Module(id: id, aspect: aspect, source: body))
            }
            lines = []
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("// ===== ") {
                flush()
                let parts = line.dropFirst(9).split(separator: " ")
                id = parts.first.map(String.init) ?? "module"
                aspect = parts.count > 1 ? String(parts[1]) : defaultAspect
            } else if line.hasPrefix("// spiral-aspect:") {
                aspect = line.replacingOccurrences(of: "// spiral-aspect:", with: "").trimmingCharacters(in: .whitespaces)
            } else {
                lines.append(line)
            }
        }
        flush()
        return out
    }

    private func mount(at target: Int) {
        Task { await mountNow(at: target) }
    }

    @MainActor
    private func mountNow(at target: Int) async {
        guard !modules.isEmpty else { return }
        index = ((target % modules.count) + modules.count) % modules.count
        let module = modules[index]
        await preview.stopAndWait()
        mounted = nil

        let manifest = #"{"app_id":"lab-\#(module.id)","runtime":"1","entry":"app.jsx","aspect":"\#(module.aspect)","state_channel":"matrix","capabilities":["app.context.read","members.basic.read","state.shared.read","state.shared.write","time.read","ui.haptic","ui.expand"],"limits":{"max_state_bytes":16384}}"#
        let packed = SpiralAppContainer.pack(manifestJSON: manifest, entry: "app.jsx", source: module.source)
        guard let artifact = SpiralAppArtifact.verified(packed: packed, claimedDigest: SpiralAppArtifact.digest(of: packed)) else {
            status = "\(module.id): could not build the artifact."
            return
        }
        mounted = module
        status = "\(index + 1)/\(modules.count) \(module.id) at \(module.aspect)"
        // The lab has no full-screen cover; "give me the screen" switches the
        // box instead, which is the same question answered with what is here.
        preview.instance?.onExpandRequested = { [self] in
            box = .full
            preview.setViewport(.expanded)
        }
        MXLog.info("[SpiralApp/lab] module \(module.id) aspect \(module.aspect) box \(box.rawValue)")
        preview.start(artifact, viewerID: "@lab:spiral.md")
        if box == .full {
            // The viewport mark must follow the box; a freshly mounted app
            // starts in "row" until told otherwise.
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                preview.setViewport(.expanded)
            }
        }
    }

    private func toggleRun() {
        if let run {
            run.cancel()
            self.run = nil
            status = "Stopped."
            return
        }
        load()
        guard !modules.isEmpty else { return }
        run = Task { @MainActor in
            for i in 0..<modules.count {
                guard !Task.isCancelled else { break }
                box = .row
                await mountNow(at: i)
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                box = .full
                MXLog.info("[SpiralApp/lab] module \(modules[i].id) aspect \(modules[i].aspect) box full")
                preview.setViewport(.expanded)
                try? await Task.sleep(for: .seconds(2))
            }
            status = "Run finished: \(modules.count) module(s)."
            run = nil
        }
    }

    private static func ratio(_ aspect: String) -> CGFloat {
        let parts = aspect.split(separator: ":").compactMap { Double($0) }
        return parts.count == 2 && parts[1] > 0 ? CGFloat(parts[0] / parts[1]) : 4 / 3
    }
}
