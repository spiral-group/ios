//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Compound
import SwiftUI
import Testing

/// Brief 0083 phase 3, decision 320: Compound's icon keys draw SF Symbols.
struct SpiralSymbolsTests {
    @Test("Every CompoundIcons key has exactly one row, whose key path reads that key")
    func everyKeyHasOneRow() throws {
        let icons = CompoundIcons()
        let keys = try Mirror(reflecting: icons).children.map { child in
            try (name: #require(child.label), image: #require(child.value as? Image))
        }
        #expect(!keys.isEmpty)

        let rows = Dictionary(grouping: SpiralSymbols.rows, by: \.name)
        #expect(Set(rows.keys) == Set(keys.map(\.name)), "a key without a row, or a row without a key")
        #expect(rows.values.allSatisfy { $0.count == 1 }, "a key with two rows")
        for key in keys {
            let row = try #require(rows[key.name]?.first)
            #expect(icons[keyPath: row.keyPath] == key.image, "\(key.name)'s row reads another key")
        }
    }

    @Test("Every SF Symbol in the table exists on this OS")
    func everySymbolExists() {
        for row in SpiralSymbols.rows {
            guard case let .system(name) = row.symbol else { continue }
            #expect(UIImage(systemName: name) != nil, "\(row.name): \(name)")
        }
    }

    @Test("No SF Symbol in the table is one Apple reserves for its own features")
    func noReservedSymbol() throws {
        let reserved = try reservedSymbolNames()
        #expect(reserved.contains("video"), "the restriction list doesn't read as expected")

        let reservedRows = SpiralSymbols.rows.filter { row in
            if case let .system(name) = row.symbol { reserved.contains(name) } else { false }
        }
        #expect(reservedRows.map(\.name) == [])
    }

    @Test("A mapped key draws its SF Symbol, and the video call family keeps Compound's asset")
    func mappedKeysDrawTheirSymbol() throws {
        for row in SpiralSymbols.rows {
            let drawn = try render(CompoundIcon(row.keyPath))
            let asset = try render(upstreamDrawing(of: Image.compound[keyPath: row.keyPath]))
            switch row.symbol {
            case .system: #expect(drawn != asset, "\(row.name) still draws Compound's asset")
            case .compound: #expect(drawn == asset, "\(row.name) should draw Compound's asset as upstream does")
            }
        }
    }

    @Test("A key without a row, a symbol this OS lacks and a custom image keep upstream's drawing")
    func unknownFallsBackToTheAsset() throws {
        #expect(SpiralSymbols.drawing(for: \CompoundIcons.unmappedForTests) == .asset)
        #expect(try render(CompoundIcon(\CompoundIcons.unmappedForTests)) == render(upstreamDrawing(of: Image.compound.chat)))

        let unknownSymbol = SpiralSymbols.Row("chat", \.chat, .system("spiral.no.such.symbol"))
        #expect(SpiralSymbols.drawing(for: unknownSymbol) == .asset)

        #expect(try render(CompoundIcon(customImage: Image(systemName: "star"))) == render(upstreamDrawing(of: Image(systemName: "star"))))
    }

    @Test("An icon as a menu's label inside a ViewThatFits lays out")
    func iconInAMenuInsideViewThatFits() {
        // A conditional `CompoundIcon.body` crashed here, and with it the Feed's post cards.
        let bar = ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { iconsAndMenu }
            VStack(spacing: 12) { iconsAndMenu }
        }
        let controller = UIHostingController(rootView: bar)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        #expect(controller.view.intrinsicContentSize.width > 0)
    }

    @Test("A symbol takes the asset's frame at every size")
    func symbolKeepsTheFrame() {
        let sizes: [(CompoundIcon.Size, Font)] = [(.xSmall, .compound.bodyXS),
                                                  (.small, .compound.bodySM),
                                                  (.medium, .compound.bodyLG),
                                                  (.custom(32), .compound.headingLG)]
        for (size, font) in sizes {
            let symbol = layoutSize(of: CompoundIcon(\.chat, size: size, relativeTo: font))
            let asset = layoutSize(of: CompoundIcon(customImage: Image.compound.chat, size: size, relativeTo: font))
            #expect(symbol == asset)
            #expect(symbol == CGSize(width: size.value, height: size.value))
        }
    }

    @Test("VoiceOver reads a symbol as it read the asset")
    func symbolKeepsTheVoiceOverLabel() {
        for keyPath in [\CompoundIcons.chat, \.lockSolid, \.public] {
            let symbol = voiceOverLabels(of: CompoundIcon(keyPath))
            let asset = voiceOverLabels(of: Image.compound[keyPath: keyPath])
            #expect(!asset.isEmpty, "the asset exposes no element to compare with")
            #expect(symbol == asset)
        }
    }

    @Test("Every SF Symbol in the table was in iOS 18.0, whatever OS the test runs on")
    func everySymbolIsInIOS18() throws {
        let releases = try symbolReleases()
        for row in SpiralSymbols.rows {
            guard case let .system(name) = row.symbol else { continue }
            let release = try #require(releases[name], "\(row.name): \(name) isn't in this runtime's list")
            #expect(release.compare("18.0", options: .numeric) != .orderedDescending, "\(row.name): \(name) needs iOS \(release)")
        }
    }

    @Test("Every symbol's ink stays inside its frame, centred where it had to move: at the largest text size, with Bold Text, right to left and in every script iOS draws it in")
    func everySymbolFitsItsFrame() throws {
        let runtimeNames = try Set(symbolReleases().keys)
        for row in SpiralSymbols.rows {
            guard case let .system(name) = row.symbol else { continue }
            let scripts = Surroundings.scripts.filter { runtimeNames.contains("\(name).\($0.key)") }.map(\.value)
            for surroundings in Surroundings.everywhere + scripts {
                let ink = try inkPlacement(of: row.keyPath, in: surroundings)
                // Antialiasing and pixel snapping reach a quarter point; past half a point the clip shows.
                #expect(ink.overflow <= 0.5, "\(row.name) (\(name)) leaves its frame by \(ink.overflow) pt in \(surroundings.name)")

                let variant = SpiralSymbols.Variant(name: name,
                                                    layoutDirection: surroundings.layoutDirection,
                                                    isBold: surroundings.legibilityWeight == .bold,
                                                    localeIdentifier: surroundings.locale.identifier)
                if SpiralSymbols.fit(for: variant) != .init() {
                    #expect(ink.centreError <= max(0.5, ink.frameSize / 100), "\(row.name) (\(name)) sits \(ink.centreError) pt off centre in \(surroundings.name)")
                }
            }
        }
    }

    // MARK: - Helpers

    /// What changes the symbol iOS draws, its weight or its size.
    private struct Surroundings {
        var name = "the default"
        var size = CompoundIcon.Size.medium
        var dynamicTypeSize = DynamicTypeSize.large
        var legibilityWeight = LegibilityWeight.regular
        var layoutDirection = LayoutDirection.leftToRight
        var locale = Locale(identifier: "en_GB")

        static let everywhere: [Surroundings] = [.init(),
                                                 .init(name: "AX5", dynamicTypeSize: .accessibility5),
                                                 .init(name: "xSmall", size: .xSmall),
                                                 .init(name: "Bold Text", legibilityWeight: .bold),
                                                 .init(name: "Hebrew, right to left", layoutDirection: .rightToLeft, locale: Locale(identifier: "he"))]

        /// SF's script variants by name suffix: a symbol has one where the runtime lists `<name>.<suffix>`.
        static let scripts: [String: Surroundings] = {
            let suffixes = ["ar", "he", "hi", "bn", "gu", "kn", "ml", "mni", "mr", "or", "pa", "sat", "si", "ta", "te", "th", "ja", "ko", "zh", "el", "ru", "km", "my"]
            return Dictionary(uniqueKeysWithValues: suffixes.map { suffix in
                (suffix, Surroundings(name: "the \(suffix) script",
                                      layoutDirection: ["ar", "he"].contains(suffix) ? .rightToLeft : .leftToRight,
                                      locale: Locale(identifier: suffix == "zh" ? "zh-Hans" : suffix)))
            })
        }()
    }

    /// This runtime's own SF Symbols metadata.
    private var coreGlyphs: URL {
        let root = ProcessInfo.processInfo.environment["SIMULATOR_ROOT"] ?? ""
        return URL(fileURLWithPath: root + "/System/Library/CoreServices/CoreGlyphs.bundle")
    }

    /// Apple's list of the symbols that may only refer to its own features, as this runtime ships it.
    private func reservedSymbolNames() throws -> Set<String> {
        let url = coreGlyphs.appendingPathComponent("symbol_restrictions.strings")
        let list = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try Set(#require(list as? [String: String]).keys)
    }

    /// The iOS release that brought each symbol name, script and right-to-left variants included.
    private func symbolReleases() throws -> [String: String] {
        let url = coreGlyphs.appendingPathComponent("name_availability.plist")
        let list = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        let years = try #require(list["symbols"] as? [String: String])
        let releases = try #require(list["year_to_release"] as? [String: [String: String]])
        return try years.mapValues { year in try #require(releases[year]?["iOS"], "no iOS release for \(year)") }
    }

    /// Where an icon's ink sits against its frame, in points.
    private struct InkPlacement {
        /// How far the ink reaches past the frame on its worst side.
        let overflow: CGFloat
        /// How far the ink's centre is from the frame's on its worse axis.
        let centreError: CGFloat
        let frameSize: CGFloat
    }

    private func inkPlacement(of keyPath: KeyPath<CompoundIcons, Image>, in surroundings: Surroundings) throws -> InkPlacement {
        let margin: CGFloat = 8
        let renderer = ImageRenderer(content: CompoundIcon(keyPath, size: surroundings.size, relativeTo: .compound.bodyLG)
            .padding(margin)
            .environment(\.dynamicTypeSize, surroundings.dynamicTypeSize)
            .environment(\.legibilityWeight, surroundings.legibilityWeight)
            .environment(\.layoutDirection, surroundings.layoutDirection)
            .environment(\.locale, surroundings.locale))
        renderer.scale = 4
        let image = try #require(renderer.cgImage)
        let ink = try #require(inkBounds(of: image), "\(keyPath) draws nothing")
        let frame = CGRect(x: 0, y: 0, width: image.width, height: image.height).insetBy(dx: margin * 4, dy: margin * 4)
        return InkPlacement(overflow: max(frame.minX - ink.minX, ink.maxX - frame.maxX, frame.minY - ink.minY, ink.maxY - frame.maxY) / 4,
                            centreError: max(abs(ink.midX - frame.midX), abs(ink.midY - frame.midY)) / 4,
                            frameSize: frame.width / 4)
    }

    /// The pixels the image covers at least half.
    private func inkBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let alpha = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var ink = CGRect.null
        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] >= 128 {
                ink = ink.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ink.isNull ? nil : ink
    }

    private var iconsAndMenu: some View {
        Group {
            Label { Text("3") } icon: { CompoundIcon(\.chat, size: .small, relativeTo: .compound.bodyMDSemibold) }
            Label { Text("1") } icon: { CompoundIcon(\.videoCall, size: .small, relativeTo: .compound.bodyMDSemibold) }
            Menu {
                Button { } label: { Label("Hide", icon: \.visibilityOff) }
            } label: {
                CompoundIcon(\.overflowHorizontal, size: .small, relativeTo: .compound.bodyMDSemibold)
            }
        }
    }

    /// `CompoundIcon`'s body before Spiral: the image resized into the 24 pt frame.
    private func upstreamDrawing(of image: Image) -> some View {
        image.resizable().frame(width: 24, height: 24)
    }

    private func render(_ icon: some View) throws -> Data {
        let renderer = ImageRenderer(content: icon)
        renderer.scale = 2
        return try #require(renderer.uiImage?.pngData())
    }

    private func layoutSize(of icon: CompoundIcon) -> CGSize {
        UIHostingController(rootView: icon).sizeThatFits(in: CGSize(width: 200, height: 200))
    }

    private func voiceOverLabels(of icon: some View) -> [String] {
        // Without an assistive technology on, a hosting view builds no accessibility tree at all.
        let controller = UIHostingController(rootView: icon.environment(\.accessibilityEnabled, true))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        return accessibilityLabels(in: controller.view)
    }

    private func accessibilityLabels(in element: NSObject) -> [String] {
        if element.isAccessibilityElement {
            return [element.accessibilityLabel ?? ""]
        }
        let children = (element.accessibilityElements as? [NSObject]) ?? []
        return children.flatMap(accessibilityLabels)
    }
}

private extension CompoundIcons {
    /// A key the table doesn't know, as a newer tokens release would bring.
    var unmappedForTests: Image {
        chat
    }
}
