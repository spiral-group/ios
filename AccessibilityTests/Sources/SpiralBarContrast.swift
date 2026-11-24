//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import XCTest

// AGENT-PLATFORM (Brief 0083): on iOS 26 and later the app hides navigation bars and toolbars from the
// contrast audit, which misreads their Liquid Glass (`SpiralContrastExemptions` in the app). Their elements
// are measured here instead, from the screen's pixels, and so are the tab bars', which the audit may not
// reach at all: a reading that can't tell an element's text from what surrounds it fails too.

/// What a state's bars hold, from `checkBarContrast`.
struct BarFrames {
    /// The frames of everything the bars hold, to compare with what the app hides for the recheck.
    var all = [CGRect]()
    /// Where the lowest navigation bar ends, for contrast triage J (`isExemptContrastIssue`).
    var headerBottom: CGFloat?
}

extension AccessibilityTests {
    /// How the failures of `checkBarContrast` begin; the bar's kind follows ("… a toolbar"), so a state that
    /// must fail can expect a failure in each bar.
    nonisolated static let barContrastFailure = "Contrast failed in a"
    nonisolated static let barReadingFailure = "Couldn't read the contrast of an element in a"

    /// Fails each enabled, labelled element of the navigation bars, toolbars and tab bars whose pixels read
    /// under the ratio WCAG asks of it, and each that can't be read. Each reading is an `A11Y BAR` line.
    /// - Parameter keyboardFrame: Read only when a bar has an element: one under the keyboard can't be seen.
    /// - Returns: The frames of everything the bars hold, to compare with what the app hides for the recheck, and where
    ///   the navigation bars end.
    func checkBarContrast(stateNamed name: String, keyboardFrame: () -> CGRect) -> BarFrames {
        guard #available(iOS 26, *) else { return BarFrames() }

        let bars = barSnapshots()
        let elements = bars.flatMap { BarElement.elements(of: $0.snapshot, in: $0.kind) }
        if !elements.isEmpty {
            let hiddenByKeyboard = keyboardFrame()
            let screenshot = XCUIScreen.main.screenshot().image
            for element in elements where !hiddenByKeyboard.contains(element.frame) {
                guard element.isEnabled else {
                    // swiftlint:disable:next print_deprecation
                    print("🔍 A11Y BAR [\(name)] not measured, disabled (exempt under WCAG 1.4.3) \(element)")
                    continue
                }
                check(element, in: screenshot, stateNamed: name)
            }
        }
        return BarFrames(all: bars.flatMap { Self.frames(in: $0.snapshot) },
                         headerBottom: bars.filter { $0.kind == .navigationBar }.map(\.snapshot.frame.maxY).max())
    }

    private func check(_ element: BarElement, in screenshot: UIImage, stateNamed name: String) {
        if element.isTab {
            checkTab(element, in: screenshot, stateNamed: name)
            return
        }
        report(BarReading(of: element, in: screenshot, stateNamed: name), for: element, stateNamed: name)
    }

    /// A tab shows its icon over its title, and maybe a badge at the icon's corner, and each has its own colours: since
    /// question 399 the icon is drawn in its own palette (a darker glyph over a lighter layer), and a badge is a small
    /// capsule of its own fill with its count in white. So a tab is read in parts (`TabParts`): its title as text, its
    /// icon as a graphic by its strongest layer, and its badge's count on the badge's fill, each against what is behind
    /// it. A tab whose parts can't be told apart fails as unreadable.
    private func checkTab(_ tab: BarElement, in screenshot: UIImage, stateNamed name: String) {
        let parts = TabParts(of: tab.frame, iconFrame: tab.iconFrame, in: screenshot)
        if let badge = parts.badge {
            report(BarReading(badge: badge, in: screenshot), for: tab.part("the badge of", type: .staticText, frame: badge.frame), stateNamed: name)
        }
        switch parts {
        case .unreadable(let reason, _):
            report(.unreadable(reason), for: tab, stateNamed: name)
        case .parts(let parts):
            // swiftlint:disable:next print_deprecation
            print("🔍 A11Y BAR [\(name)] \(tab) read in parts: \(parts)")
            let title = tab.part("the title of", type: .staticText, frame: parts.title)
            report(BarReading(of: parts.title, in: screenshot, readsLeadingSpoke: false, excluding: parts.badgeMask), for: title, stateNamed: name)
            let icon = tab.part("the icon of", type: .image, frame: parts.icon)
            report(BarReading(of: parts.icon, in: screenshot, readsLeadingSpoke: true, excluding: parts.badgeMask), for: icon, stateNamed: name)
        }
    }

    private func report(_ reading: BarReading, for element: BarElement, stateNamed name: String) {
        switch reading {
        case .unreadable(let reason):
            // swiftlint:disable:next print_deprecation
            print("🔍 A11Y ISSUE [\(name)] type=barContrast desc=\(reason) element=\(element)")
            XCTFail("\(Self.barReadingFailure) \(element.kind): \(reason), \(element)")
        case .contrast(let contrast):
            let minimum = element.minimumRatio(for: contrast)
            // swiftlint:disable:next print_deprecation
            print("🔍 A11Y BAR [\(name)] \(contrast), needs \(minimum) \(element)")
            if contrast.ratio < minimum.ratio {
                // swiftlint:disable:next print_deprecation
                print("🔍 A11Y ISSUE [\(name)] type=barContrast desc=\(contrast), under \(minimum) element=\(element)")
                XCTFail("\(Self.barContrastFailure) \(element.kind): \(contrast), under \(minimum), \(element)")
            }
        }
    }

    /// An element of the content read by its pixels on the screen now, for contrast triage K (`ownPixelsPass`).
    ///
    /// K never relaxes text (Opus review, 2026-11-14): only an image and a monogram avatar (one letter in a frame of its own,
    /// about square and 20 pt across) need 3:1, and everything else is text at 4.5:1, whatever its size or its frame's
    /// shape. The ratio is taken against the background's shade nearest the text, and must pass by a tenth more.
    static func ownPixelsReading(of element: XCUIElement, stateNamed name: String) -> (passes: Bool, description: String) {
        let content = BarElement(kind: .content, type: element.elementType, label: element.label, frame: element.frame, isEnabled: element.isEnabled)
        switch BarReading(of: content, in: XCUIScreen.main.screenshot().image, stateNamed: name) {
        case .unreadable(let reason):
            return (false, "\(reason), \(content)")
        case .contrast(let contrast):
            let minimum = content.type == .image || content.isAvatarMonogram ? MinimumRatio(ratio: 3, of: "a graphic") : MinimumRatio(ratio: 4.5, of: "text")
            let ratio = contrast.ratioAgainstNearestBackground
            let measured = String(format: "%.2f:1 against the nearest shade #%06X", ratio, contrast.nearestBackground ?? contrast.background)
            return (ratio >= minimum.ratio * 1.1, "\(contrast), \(measured), needs \(minimum) and a tenth more, \(content)")
        }
    }

    private func barSnapshots() -> [(kind: BarElement.Kind, snapshot: XCUIElementSnapshot)] {
        let queries: [(BarElement.Kind, XCUIElementQuery)] = [(.navigationBar, app.navigationBars), (.toolbar, app.toolbars), (.tabBar, app.tabBars)]
        return queries.flatMap { kind, query in
            query.allElementsBoundByIndex.compactMap { bar in
                do {
                    return try (kind, bar.snapshot())
                } catch {
                    XCTFail("Couldn't read a \(kind) to check its contrast: \(error)")
                    return nil
                }
            }
        }
    }

    private static func frames(in element: XCUIElementSnapshot) -> [CGRect] {
        [element.frame] + element.children.flatMap(frames(in:))
    }
}

/// An element of a bar that shows something of its own.
private struct BarElement: CustomStringConvertible {
    enum Kind: String, CustomStringConvertible {
        case navigationBar = "navigation bar"
        case toolbar
        case tabBar = "tab bar"
        /// An element of the screen's content, read for the contrast recheck (`ownPixelsPass`).
        case content

        var description: String {
            rawValue
        }
    }

    let kind: Kind
    let type: XCUIElement.ElementType
    let label: String
    let frame: CGRect
    /// A disabled control is exempt (WCAG 1.4.3); it is printed, not measured.
    let isEnabled: Bool
    /// A control read whole because its children show no text: icons only, except in a tab bar, where a tab's
    /// title under its icon is no child of its own.
    var showsNoChildText = false
    /// A part of a tab (`checkTab`), such as "the badge of": read on its own, and named after its tab.
    var partOf: String?
    /// The frame of its icon when the icon is a child element of its own, as the Settings tab's is.
    var iconFrame: CGRect?

    var description: String {
        let name = label.isEmpty ? "an unlabelled \(type == .image ? "image" : "element")" : "'\(label)'"
        return "\(partOf.map { "\($0) " } ?? "")\(name) at \(frame)"
    }

    /// A tab of a tab bar, read in parts (`checkTab`).
    var isTab: Bool {
        kind == .tabBar && type == .button && partOf == nil
    }

    func part(_ partOf: String, type: XCUIElement.ElementType, frame: CGRect) -> BarElement {
        BarElement(kind: kind, type: type, label: label, frame: frame, isEnabled: isEnabled, partOf: partOf)
    }

    /// Types that only hold other elements, the bars themselves included.
    private static let containerTypes: Set<XCUIElement.ElementType> = [.other, .group, .staticText, .navigationBar, .toolbar, .tabBar]

    /// What shows something of its own: a leaf, or a labelled control whose children show no text, such as a tab,
    /// whose only child is its icon, or a menu whose label is its icons. A container shows nothing of its own. An
    /// image or a spinner is measured without a label too.
    static func elements(of element: XCUIElementSnapshot, in kind: Kind) -> [BarElement] {
        let readsWhole = !element.label.isEmpty && !containerTypes.contains(element.elementType) && !holdsText(element.children)
        guard element.children.isEmpty || readsWhole else {
            return element.children.flatMap { elements(of: $0, in: kind) }
        }
        let barElement = BarElement(kind: kind, type: element.elementType, label: element.label, frame: element.frame,
                                    isEnabled: element.isEnabled, showsNoChildText: !element.children.isEmpty,
                                    iconFrame: element.children.first { $0.elementType == .image }?.frame)
        guard !element.label.isEmpty || barElement.isSpinner || element.elementType == .image, !element.frame.isEmpty else {
            return []
        }
        return [barElement]
    }

    /// What WCAG asks: 3:1 for a graphic (1.4.11) and for large text, 4.5:1 for other text (1.4.3).
    func minimumRatio(for contrast: BarContrast) -> MinimumRatio {
        if isGraphicOnlyByShape {
            let ink = String(format: "ink %.1f by %.1f pt", contrast.inkWidth, contrast.tallestLine)
            // A button's frame holds its padding as well as its lines, so its text needs 4.5:1 whatever its size.
            return contrast.inkSpellsOut(label) ? MinimumRatio(ratio: 4.5, of: "text in a near-square control, \(ink)")
                : MinimumRatio(ratio: 3, of: "a graphic in a near-square control, \(ink)")
        }
        if isGraphic {
            return MinimumRatio(ratio: 3, of: "a graphic")
        }
        if isMonogram {
            return MinimumRatio(ratio: 3, of: "a monogram, a graphic")
        }
        guard type == .staticText else {
            // A button's frame holds its padding as well as its lines, so it needs 4.5:1 whatever its size.
            return MinimumRatio(ratio: 4.5, of: "text")
        }
        // Large text is 18 pt, or 14 pt bold. The frame's height per line counts its padding (gates-3 review), and a line's
        // ink counts an accented capital (Й, Ї), parentheses or a glyph of the text's colour beside it, which take 17 pt
        // text past 20 pt. So text counts as large only when its shortest line's ink is 24 pt tall, which no 17 pt line
        // reaches (Opus review, 2026-11-14): 18–23 pt text is held to 4.5:1, stricter than WCAG. The pixels don't show the
        // weight, so bold text under 18 pt needs 4.5:1 too.
        let lines = contrast.lineCount == 1 ? "1 line" : "\(contrast.lineCount) lines"
        guard contrast.lineCount > 0, contrast.shortestLine >= 24 else {
            let ink = contrast.shortestLine > 0 ? String(format: ", ink %.1f pt", contrast.shortestLine) : ""
            return MinimumRatio(ratio: 4.5, of: "text, \(lines)\(ink)")
        }
        return MinimumRatio(ratio: 3, of: String(format: "large text, %@, ink %.1f pt", lines, contrast.shortestLine))
    }

    /// A monogram avatar: one letter, read as a graphic. In a bar it may be a labelled image, or a letter in a frame about
    /// as wide as it is tall and at least 20 pt across: the avatar's own frame, like the Feed's own-posts 'U'.
    var isMonogram: Bool {
        guard label.count == 1, label.first?.isLetter == true else { return false }
        return isGraphic || (type == .staticText && isAvatarFrame)
    }

    /// One letter in a frame of its own, about square and 20 pt across: a monogram avatar, whatever its type.
    var isAvatarMonogram: Bool {
        label.count == 1 && label.first?.isLetter == true && isAvatarFrame
    }

    private var isAvatarFrame: Bool {
        min(frame.width, frame.height) >= 20 && abs(frame.width - frame.height) <= 0.2 * max(frame.width, frame.height)
    }

    var isSpinner: Bool {
        type == .activityIndicator || type == .progressIndicator
    }

    /// An image, an icon, an avatar or a spinner: a control about as wide as it is tall shows one glyph, not a word,
    /// and so does one whose children are icons, such as a call menu (outside a tab bar).
    var isGraphic: Bool {
        isSpinner || type == .image || (showsNoChildText && kind != .tabBar) || isNearSquareControl
    }

    /// A control about as wide as it is tall, which usually shows a glyph: 'Join call' is a camera, an avatar a disc.
    private var isNearSquareControl: Bool {
        type != .staticText && frame.width <= frame.height * 1.25
    }

    /// A graphic only by its frame's shape (bar-reader rule 2): short text such as 'OK' fits a near-square capsule too,
    /// so its reading decides (`BarContrast.inkSpellsOut(_:)`). A one-letter label stays a graphic: a monogram.
    private var isGraphicOnlyByShape: Bool {
        isNearSquareControl && !isSpinner && type != .image && !(showsNoChildText && kind != .tabBar) && label.count >= 2
    }

    private static func holdsText(_ elements: [XCUIElementSnapshot]) -> Bool {
        elements.contains { $0.elementType == .staticText || holdsText($0.children) }
    }
}

private struct MinimumRatio: CustomStringConvertible {
    let ratio: Double
    let of: String

    var description: String {
        String(format: "%g:1 (%@)", ratio, of)
    }
}

/// What an element's pixels say about its contrast. WCAG's ratio depends only on luminance, so the reading groups
/// colours into bands of luminance 1.1:1 wide. The background is the densest band of the element's middle, and
/// the text the densest band apart from it; each is read as its band's most common colour. Other pixels within
/// 2/3 pt of the text are its anti-aliasing. A reading fails rather than guess when no band holds a third of the
/// element, or when pixels that are neither background, text nor anti-aliasing reach a tenth of the text's: a
/// second colour of text, an icon or a varied backdrop. A spinner's spokes are one colour at several opacities,
/// so it is read by its leading spoke, the band farthest from the background, and so is a tab's icon, whose glyph
/// is its darkest layer over a lighter one.
private enum BarReading {
    case contrast(BarContrast)
    case unreadable(String)

    private static let binCount = 256
    /// Bins of `log(luminance + 0.05)`, whose differences are contrast ratios; 8 bins are 1.1:1.
    private static let binsPerBand = 8
    private static let logLuminanceRange = log(0.05)...log(1.05)

    /// An element's reading. A monogram avatar's letter sits on the avatar's two-stop gradient, which in dark spans more
    /// shades than one band (#575368 to #312649), maybe inside a ring of glass: no one background. It is read by its glyph
    /// against its gradient (`init(monogramOf:in:)`).
    init(of element: BarElement, in screenshot: UIImage, stateNamed name: String) {
        self = BarReading(of: element.frame, in: screenshot, readsLeadingSpoke: element.isSpinner)
        if case .unreadable(let reason) = self, element.isMonogram {
            // swiftlint:disable:next print_deprecation
            print("🔍 A11Y BAR [\(name)] a monogram on its gradient (\(reason)), read by its glyph \(element)")
            self = BarReading(monogramOf: element.frame, in: screenshot)
        }
    }

    /// - Parameter excluding: Frames on the screen whose pixels the reading leaves out, such as a tab's badge.
    init(of frame: CGRect, in screenshot: UIImage, readsLeadingSpoke: Bool, excluding: [CGRect] = []) {
        guard let image = screenshot.cgImage, let pixels = Pixels(of: frame, scale: screenshot.scale, in: image, excluding: excluding) else {
            self = .unreadable("nothing to measure: it isn't on the screen")
            return
        }
        // The middle of the element: its text, without a glass capsule's edge or an avatar's corners.
        let middle = pixels.indices(of: pixels.middle)
        var bins = [Int](repeating: 0, count: pixels.colours.count)
        var histogram = [Int](repeating: 0, count: Self.binCount)
        var binOfColour = [UInt32: Int]()
        for index in middle {
            let colour = pixels.colours[index]
            let bin = binOfColour[colour] ?? Self.bin(of: colour)
            binOfColour[colour] = bin
            bins[index] = bin
            histogram[bin] += 1
        }

        let area = middle.count
        let floor = max(4, area / 400)
        guard let background = Self.densestBand(in: histogram, avoiding: []) else {
            self = .unreadable("nothing to measure: it is too small")
            return
        }
        let backgroundZone = Self.zone(around: background)
        let ink = readsLeadingSpoke ? Self.farthestBand(from: background, in: histogram, avoiding: backgroundZone, floor: floor)
            : Self.densestBand(in: histogram, avoiding: backgroundZone)
        guard let text = ink, text.count >= floor else {
            self = .unreadable("nothing to measure: no colour but its background's covers 1/400 of it")
            return
        }
        let textZone = Self.zone(around: text)

        let backgroundCount = backgroundZone.reduce(0) { $0 + histogram[$1] }
        guard backgroundCount * 3 >= area else {
            self = .unreadable("its background varies: no band of shades covers a third of it")
            return
        }

        let isBackground = { (index: Int) in backgroundZone.contains(bins[index]) }
        let isText = { (index: Int) in textZone.contains(bins[index]) && !isBackground(index) }
        let nearText = pixels.dilated(middle, matching: isText, by: max(1, Int((pixels.scale * 2 / 3).rounded())))
        let unexplained = middle.count { !isBackground($0) && !nearText[$0] }
        let foreground = pixels.mostCommonColour(in: middle) { text.bins.contains(bins[$0]) }
        guard readsLeadingSpoke || unexplained < max(floor, text.count / 10) else {
            self = .unreadable(String(format: "%d px are neither its background's colour nor its text's (#%06X): a second colour or a varied backdrop", unexplained, foreground))
            return
        }

        let backgroundColour = pixels.mostCommonColour(in: middle) { background.bins.contains(bins[$0]) }
        let nearestBackground = Self.nearestShade(of: backgroundZone, to: text.bins, in: middle.filter { isBackground($0) && !nearText[$0] }, bins: bins, pixels: pixels)
        let isInk = { (index: Int) -> Bool in
            let bin = binOfColour[pixels.colours[index]] ?? Self.bin(of: pixels.colours[index])
            return textZone.contains(bin) && !backgroundZone.contains(bin)
        }
        let lines = pixels.lineHeights(in: pixels.middle.columns, isText: isInk)
        self = .contrast(BarContrast(foreground: foreground,
                                     background: backgroundColour,
                                     lineCount: lines.count,
                                     shortestLine: CGFloat(lines.min() ?? 0) / pixels.scale,
                                     tallestLine: CGFloat(lines.max() ?? 0) / pixels.scale,
                                     inkWidth: CGFloat(pixels.inkColumns(in: pixels.middle, isText: isInk).count) / pixels.scale,
                                     nearestBackground: nearestBackground))
    }

    /// A monogram avatar (`init(of:in:stateNamed:)`): in the frame's middle its glyph is the band farthest from the
    /// densest one, and its background the band nearest the glyph among those that cover a tenth of the middle, so the
    /// reading takes the gradient's end that is hardest on the glyph, and leaves out a ring of glass round the avatar,
    /// which is farther from the glyph. No band need cover a third, and no pixel need be explained.
    init(monogramOf frame: CGRect, in screenshot: UIImage) {
        guard let image = screenshot.cgImage, let pixels = Pixels(of: frame, scale: screenshot.scale, in: image) else {
            self = .unreadable("nothing to measure: it isn't on the screen")
            return
        }
        let square = pixels.indices(of: pixels.middle)
        var bins = [Int](repeating: 0, count: pixels.colours.count)
        var histogram = [Int](repeating: 0, count: Self.binCount)
        for index in square {
            let bin = Self.bin(of: pixels.colours[index])
            bins[index] = bin
            histogram[bin] += 1
        }
        let floor = max(4, square.count / 400)
        guard let densest = Self.densestBand(in: histogram, avoiding: []),
              let glyph = Self.farthestBand(from: densest, in: histogram, avoiding: Self.zone(around: densest), floor: floor) else {
            self = .unreadable("nothing to measure: no glyph apart from its disc")
            return
        }
        let glyphZone = Self.zone(around: glyph)
        var nearest: Range<Int>?
        for start in 0...(Self.binCount - Self.binsPerBand) {
            let band = start..<(start + Self.binsPerBand)
            let count = band.reduce(0) { $0 + histogram[$1] }
            guard count * 10 >= square.count, !band.contains(where: glyphZone.contains) else { continue }
            if abs(start - glyph.bins.lowerBound) < abs((nearest?.lowerBound ?? Int.max / 2) - glyph.bins.lowerBound) {
                nearest = band
            }
        }
        guard let fill = nearest else {
            self = .unreadable("nothing to measure: no band of its disc covers a tenth of it")
            return
        }
        let foreground = pixels.mostCommonColour(in: square) { glyph.bins.contains(bins[$0]) }
        let background = pixels.mostCommonColour(in: square) { fill.contains(bins[$0]) }
        self = .contrast(BarContrast(foreground: foreground, background: background, lineCount: 1, shortestLine: 0))
    }

    /// A badge's count on the badge's fill (`TabParts.Badge`): the count is what the fill holds of another band.
    init(badge: TabParts.Badge, in screenshot: UIImage) {
        guard let image = screenshot.cgImage, let pixels = Pixels(of: badge.frame, scale: screenshot.scale, in: image) else {
            self = .unreadable("nothing to measure: it isn't on the screen")
            return
        }
        let inside = pixels.indices(of: pixels.middle)
        let fillZone = Self.zone(around: (Self.bin(of: badge.fill) - Self.binsPerBand / 2)..<(Self.bin(of: badge.fill) + Self.binsPerBand / 2))
        var histogram = [Int](repeating: 0, count: Self.binCount)
        var bins = [Int](repeating: 0, count: pixels.colours.count)
        for index in inside {
            let bin = Self.bin(of: pixels.colours[index])
            bins[index] = bin
            if !fillZone.contains(bin) {
                histogram[bin] += 1
            }
        }
        guard let count = Self.densestBand(in: histogram, avoiding: fillZone), count.count >= max(4, inside.count / 100) else {
            self = .unreadable("nothing to measure: its badge shows no count")
            return
        }
        let foreground = pixels.mostCommonColour(in: inside) { count.bins.contains(bins[$0]) }
        self = .contrast(BarContrast(foreground: foreground, background: badge.fill, lineCount: 1, shortestLine: 0))
    }

    /// The band inside `zone` nearest `text` that holds a twentieth of `indices`, read as its most common colour.
    private static func nearestShade(of zone: Set<Int>, to text: Range<Int>, in indices: [Int], bins: [Int], pixels: Pixels) -> UInt32? {
        guard let lower = zone.min(), let upper = zone.max(), !indices.isEmpty else { return nil }
        var histogram = [Int](repeating: 0, count: binCount)
        for index in indices {
            histogram[bins[index]] += 1
        }
        var nearest: Range<Int>?
        for start in lower...max(lower, upper + 1 - binsPerBand) {
            let band = start..<(start + binsPerBand)
            guard band.reduce(0, { $0 + histogram[$1] }) * 20 >= indices.count else { continue }
            if abs(start - text.lowerBound) < abs((nearest?.lowerBound ?? Int.max / 2) - text.lowerBound) {
                nearest = band
            }
        }
        return nearest.map { band in pixels.mostCommonColour(in: indices) { band.contains(bins[$0]) } }
    }

    fileprivate static func bin(of colour: UInt32) -> Int {
        let position = (log(BarContrast.luminance(of: colour) + 0.05) - logLuminanceRange.lowerBound) / (logLuminanceRange.upperBound - logLuminanceRange.lowerBound)
        return min(binCount - 1, max(0, Int(position * Double(binCount))))
    }

    /// The band of `binsPerBand` bins that holds the most pixels, among those clear of `avoiding`.
    fileprivate static func densestBand(in histogram: [Int], avoiding: Set<Int>) -> (bins: Range<Int>, count: Int)? {
        var best: (bins: Range<Int>, count: Int)?
        for start in 0...(binCount - binsPerBand) {
            let bins = start..<(start + binsPerBand)
            guard !bins.contains(where: avoiding.contains) else { continue }
            let count = bins.reduce(0) { $0 + histogram[$1] }
            if count > 0, count > best?.count ?? 0 {
                best = (bins, count)
            }
        }
        return best
    }

    /// The band of `binsPerBand` bins farthest from `background` that holds `floor` pixels, among those clear of `avoiding`.
    private static func farthestBand(from background: (bins: Range<Int>, count: Int), in histogram: [Int], avoiding: Set<Int>, floor: Int) -> (bins: Range<Int>, count: Int)? {
        var best: (bins: Range<Int>, count: Int)?
        for start in 0...(binCount - binsPerBand) {
            let bins = start..<(start + binsPerBand)
            let count = bins.reduce(0) { $0 + histogram[$1] }
            guard !bins.contains(where: avoiding.contains), count >= floor else { continue }
            let distance = abs(start - background.bins.lowerBound)
            if distance > abs((best?.bins.lowerBound ?? background.bins.lowerBound) - background.bins.lowerBound) {
                best = (bins, count)
            }
        }
        return best
    }

    /// A band and the band on either side: shades of the same colour, such as a glass gradient or a blur.
    fileprivate static func zone(around band: (bins: Range<Int>, count: Int)) -> Set<Int> {
        zone(around: band.bins)
    }

    fileprivate static func zone(around bins: Range<Int>) -> Set<Int> {
        Set(max(0, bins.lowerBound - binsPerBand)..<min(binCount, bins.upperBound + binsPerBand))
    }
}

/// A tab's parts on the screen (`checkTab`): its icon, its title under it, and the badge at the icon's corner. The
/// background is the tab's densest band, and the rows that hold anything else make runs: the last run is the title, the
/// runs above it the icon. The badge is found first, by its pixels, and left out of both.
private enum TabParts: CustomStringConvertible {
    case parts(Parts)
    /// Why its icon and title can't be told apart, and its badge, which is found and read either way.
    case unreadable(String, badge: Badge?)

    struct Parts: CustomStringConvertible {
        let icon: CGRect
        let title: CGRect
        let badge: Badge?

        /// What the icon's and the title's readings leave out: the badge and a point round it.
        var badgeMask: [CGRect] {
            badge.map { [$0.frame.insetBy(dx: -1, dy: -1)] } ?? []
        }

        var description: String {
            "icon \(icon.debugDescription), title \(title.debugDescription)\(badge.map { ", badge \($0.frame.debugDescription) #\(String(format: "%06X", $0.fill))" } ?? "")"
        }
    }

    /// A badge: a capsule of one saturated colour, 11–26 pt tall and up to 3.5 times as wide, whose corners are clear,
    /// in the top 60 % of the tab, with its count inside it. A badge is no element of its own, so it is found by its pixels.
    struct Badge {
        let frame: CGRect
        let fill: UInt32
    }

    var badge: Badge? {
        switch self {
        case .parts(let parts): parts.badge
        case .unreadable(_, let badge): badge
        }
    }

    var description: String {
        switch self {
        case .parts(let parts): parts.description
        case .unreadable(let reason, _): reason
        }
    }

    /// - Parameter iconFrame: The icon's own frame, when it is an element of its own: the title is then the last run under it.
    init(of frame: CGRect, iconFrame: CGRect?, in screenshot: UIImage) {
        guard let image = screenshot.cgImage, let pixels = Pixels(of: frame, scale: screenshot.scale, in: image) else {
            self = .unreadable("nothing to measure: it isn't on the screen", badge: nil)
            return
        }
        let all = pixels.indices(of: Pixels.Region(columns: 0..<pixels.width, rows: 0..<pixels.height))
        var histogram = [Int](repeating: 0, count: 256)
        let bins = pixels.colours.map(BarReading.bin(of:))
        for index in all {
            histogram[bins[index]] += 1
        }
        guard let background = BarReading.densestBand(in: histogram, avoiding: []) else {
            self = .unreadable("nothing to measure: it is too small", badge: nil)
            return
        }
        let backgroundZone = BarReading.zone(around: background)
        let badge = Self.badge(in: pixels, frame: frame, isBackground: { backgroundZone.contains(bins[$0]) })
        let mask = badge.map { $0.region.expanded(by: Int(pixels.scale.rounded()), within: pixels) }

        // Rows that hold two pixels or more of anything but the background and the badge, in runs a point apart, across the
        // middle columns, clear of a selected tab's capsule's sides. With the icon's own frame, only the rows under it.
        let gap = max(1, Int(pixels.scale.rounded()))
        let firstRow = iconFrame.map { Int((($0.maxY - pixels.frame.minY) * pixels.scale).rounded()) } ?? 0
        var runs = [Range<Int>]()
        var start: Int?
        var end = 0
        for row in 0..<(pixels.height + gap) {
            let holdsInk = row >= firstRow && row < pixels.height && pixels.middle.columns.count { column in
                let index = row * pixels.width + column
                return !backgroundZone.contains(bins[index]) && !(mask?.contains(column: column, row: row) ?? false)
            } >= 2
            if holdsInk {
                start = start ?? row
                end = row
            } else if let runStart = start, row - end >= gap {
                runs.append(runStart..<(end + 1))
                start = nil
            }
        }
        // A run under 4 pt is no glyph or line of text (a 10 pt title's x-height is 5 pt) but an edge, such as a selected tab's capsule's.
        runs.removeAll { Double($0.count) < 4 * pixels.scale }
        let pad = Int((pixels.scale * 2).rounded())
        let badgeFrame = badge.map { Badge(frame: pixels.frame(of: $0.region), fill: $0.fill) }
        if let iconFrame {
            guard let titleRows = runs.last else {
                self = .unreadable("its title doesn't show under its icon", badge: badgeFrame)
                return
            }
            self = .parts(Parts(icon: iconFrame.insetBy(dx: -2, dy: -2), title: pixels.frame(ofRows: titleRows, padding: pad), badge: badgeFrame))
            return
        }
        guard runs.count >= 2, let titleRows = runs.last, let iconTop = runs.first?.lowerBound else {
            self = .unreadable("its icon and its title can't be told apart: \(runs.count) runs of rows show anything but its background", badge: badgeFrame)
            return
        }
        let iconRows = iconTop..<runs[runs.count - 2].upperBound
        self = .parts(Parts(icon: pixels.frame(ofRows: iconRows, padding: pad), title: pixels.frame(ofRows: titleRows, padding: pad), badge: badgeFrame))
    }

    private static func badge(in pixels: Pixels, frame: CGRect, isBackground: (Int) -> Bool) -> (region: Pixels.Region, fill: UInt32)? {
        var visited = [Bool](repeating: false, count: pixels.colours.count)
        var best: (component: Pixels.Component, fill: UInt32)?
        let scale = pixels.scale
        for seed in pixels.colours.indices where !visited[seed] && !isBackground(seed) && Self.chroma(pixels.colours[seed]) >= 80 {
            let fill = pixels.colours[seed]
            let component = pixels.component(from: seed, visited: &visited) { Self.distance(pixels.colours[$0], fill) <= 48 }
            let rows = component.rows, columns = component.columns
            let (height, width) = (Double(rows.count), Double(columns.count))
            guard height >= 11 * scale, height <= 26 * scale, width >= 0.8 * height, width <= 3.5 * height,
                  Double(component.members.count) >= 0.5 * height * width,
                  Double(rows.lowerBound + rows.upperBound) / 2 <= Double(pixels.height) * 0.6,
                  component.cornersAreClear(side: max(1, Int(0.12 * height)), width: pixels.width) else {
                continue
            }
            if component.members.count > best?.component.members.count ?? 0 {
                best = (component, pixels.mostCommonColour(in: component.members) { _ in true })
            }
        }
        return best.map { (Pixels.Region(columns: $0.component.columns, rows: $0.component.rows), $0.fill) }
    }

    private static func chroma(_ colour: UInt32) -> Int {
        let channels = [Int(colour >> 16 & 0xFF), Int(colour >> 8 & 0xFF), Int(colour & 0xFF)]
        return (channels.max() ?? 0) - (channels.min() ?? 0)
    }

    private static func distance(_ first: UInt32, _ second: UInt32) -> Int {
        [16, 8, 0].map { abs(Int(first >> $0 & 0xFF) - Int(second >> $0 & 0xFF)) }.max() ?? 0
    }
}

private struct BarContrast: CustomStringConvertible {
    let foreground: UInt32
    let background: UInt32
    /// The lines of text the element shows, counted from the rows its text's colour fills.
    let lineCount: Int
    /// The ink height of its shortest line, in points.
    let shortestLine: CGFloat
    /// The ink height of its tallest line, in points.
    var tallestLine: CGFloat = 0
    /// How wide its ink spreads across the middle of the element, in points.
    var inkWidth: CGFloat = 0
    /// The shade of its background's band and the bands beside it that lies nearest its text and covers a twentieth
    /// of the background clear of the text; on a gradient or glass, the end that is hardest on the text.
    var nearestBackground: UInt32?

    /// The ratio against `nearestBackground`, or against the background where there is none.
    var ratioAgainstNearestBackground: Double {
        BarContrast(foreground: foreground, background: nearestBackground ?? background, lineCount: lineCount, shortestLine: shortestLine).ratio
    }

    var ratio: Double {
        let (lighter, darker) = (max(Self.luminance(of: foreground), Self.luminance(of: background)),
                                 min(Self.luminance(of: foreground), Self.luminance(of: background)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    var description: String {
        String(format: "%.2f:1 fg #%06X bg #%06X", ratio, foreground, background)
    }

    /// Whether the ink is as wide as the label's words would be (bar-reader rule 2), which an SF Symbol of one or a few
    /// parts isn't. Text at least 8 pt tall spreads over about 0.5–0.7 of its line's height per character; a word's ink
    /// counts at 0.45, a little under. 'OK' in a 48×44 capsule (24 pt of ink, 12 pt tall) is text, while 'Join call'
    /// (a camera, about 22 by 15 pt), a tombstoned room's "!" avatar under the room's name, a "More" ellipsis (4 pt
    /// tall) and a "Back" chevron stay graphics.
    func inkSpellsOut(_ label: String) -> Bool {
        tallestLine >= 8 && inkWidth >= 0.45 * CGFloat(label.count) * tallestLine
    }

    static func luminance(of colour: UInt32) -> Double {
        func linear(_ channel: UInt32) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour >> 16 & 0xFF) + 0.7152 * linear(colour >> 8 & 0xFF) + 0.0722 * linear(colour & 0xFF)
    }
}

/// The sRGB colours of a frame's pixels, row by row.
private struct Pixels {
    /// A rectangle of pixel coordinates.
    struct Region {
        let columns: Range<Int>
        let rows: Range<Int>

        var count: Int {
            columns.count * rows.count
        }

        func contains(column: Int, row: Int) -> Bool {
            columns.contains(column) && rows.contains(row)
        }

        func expanded(by amount: Int, within pixels: Pixels) -> Region {
            Region(columns: max(0, columns.lowerBound - amount)..<min(pixels.width, columns.upperBound + amount),
                   rows: max(0, rows.lowerBound - amount)..<min(pixels.height, rows.upperBound + amount))
        }
    }

    /// Pixels joined by their sides (`component(from:visited:matching:)`).
    struct Component {
        let members: [Int]
        let columns: Range<Int>
        let rows: Range<Int>

        /// Whether a square of `side` pixels at each corner of its bounds holds under a fifth of its pixels.
        func cornersAreClear(side: Int, width: Int) -> Bool {
            let corners = [(columns.lowerBound, rows.lowerBound), (columns.upperBound - side, rows.lowerBound),
                           (columns.lowerBound, rows.upperBound - side), (columns.upperBound - side, rows.upperBound - side)]
            let set = Set(members)
            return corners.allSatisfy { column, row in
                let inside = (row..<(row + side)).reduce(0) { sum, y in sum + (column..<(column + side)).count { set.contains(y * width + $0) } }
                return inside * 5 < side * side
            }
        }
    }

    let width: Int
    let height: Int
    let scale: CGFloat
    let colours: [UInt32]
    /// The frame on the screen, in points.
    let frame: CGRect
    /// Pixels the readings leave out (`init(of:scale:in:excluding:)`).
    private let excluded: [Bool]

    /// The middle 70 % of each side.
    var middle: Region {
        let (insetX, insetY) = (Int(Double(width) * 0.15), Int(Double(height) * 0.15))
        return Region(columns: insetX..<(width - insetX), rows: insetY..<(height - insetY))
    }

    /// `nil` when the frame (in points) holds fewer than 2 by 2 pixels on the screen.
    /// - Parameter excluding: Frames on the screen (in points) whose pixels `indices(of:)` leaves out.
    init?(of frame: CGRect, scale: CGFloat, in image: CGImage, excluding: [CGRect] = []) {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
            .integral
            .intersection(bounds)
        guard rect.width >= 2, rect.height >= 2,
              let crop = image.cropping(to: rect),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        let (width, height) = (crop.width, crop.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                return false
            }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        self.width = width
        self.height = height
        self.scale = scale
        self.frame = CGRect(x: rect.minX / scale, y: rect.minY / scale, width: rect.width / scale, height: rect.height / scale)
        colours = stride(from: 0, to: bytes.count, by: 4).map { index in
            UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2])
        }
        let excludedRects = excluding.map { CGRect(x: ($0.minX - rect.minX / scale) * scale, y: ($0.minY - rect.minY / scale) * scale,
                                                   width: $0.width * scale, height: $0.height * scale) }
        excluded = (0..<(width * height)).map { index in
            let point = CGPoint(x: Double(index % width) + 0.5, y: Double(index / width) + 0.5)
            return excludedRects.contains { $0.contains(point) }
        }
    }

    /// The pixels of a region, row by row, without the excluded ones.
    func indices(of region: Region) -> [Int] {
        region.rows.flatMap { row in region.columns.map { row * width + $0 } }.filter { !excluded[$0] }
    }

    /// A region's frame on the screen, in points.
    func frame(of region: Region) -> CGRect {
        CGRect(x: frame.minX + Double(region.columns.lowerBound) / scale, y: frame.minY + Double(region.rows.lowerBound) / scale,
               width: Double(region.columns.count) / scale, height: Double(region.rows.count) / scale)
    }

    /// The frame of some rows across the whole width, `padding` pixels taller at each end.
    func frame(ofRows rows: Range<Int>, padding: Int) -> CGRect {
        frame(of: Region(columns: 0..<width, rows: max(0, rows.lowerBound - padding)..<min(height, rows.upperBound + padding)))
    }

    func mostCommonColour(in indices: [Int], where included: (Int) -> Bool) -> UInt32 {
        var counts = [UInt32: Int]()
        for index in indices where included(index) {
            counts[colours[index], default: 0] += 1
        }
        // Ties go to the smaller colour, so a run reads the same as the last one.
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? 0
    }

    /// Whether each pixel of `indices` is within `radius` pixels of one that matches.
    func dilated(_ indices: [Int], matching matches: (Int) -> Bool, by radius: Int) -> [Bool] {
        var near = [Bool](repeating: false, count: colours.count)
        for index in indices where matches(index) {
            let (row, column) = (index / width, index % width)
            for nearRow in max(0, row - radius)..<min(height, row + radius + 1) {
                for nearColumn in max(0, column - radius)..<min(width, column + radius + 1) {
                    near[nearRow * width + nearColumn] = true
                }
            }
        }
        return near
    }

    /// The heights in pixels of the runs of rows that hold the text, from top to bottom of the given columns (the
    /// middle's, clear of a capsule's or a ring's sides). A gap of a point or more parts two runs, and a run under 0.4 of
    /// the tallest is an accent or a dot, not a line.
    func lineHeights(in columns: Range<Int>, isText: (Int) -> Bool) -> [Int] {
        let gap = max(1, Int(scale.rounded()))
        var runs = [Int]()
        var start: Int?
        var end = 0
        for row in 0..<(height + gap) {
            if row < height, columns.count(where: { !excluded[row * width + $0] && isText(row * width + $0) }) >= 2 {
                start = start ?? row
                end = row
            } else if let runStart = start, row - end >= gap {
                runs.append(end - runStart + 1)
                start = nil
            }
        }
        let tallest = runs.max() ?? 0
        return runs.filter { Double($0) >= Double(tallest) * 0.4 }
    }

    /// The columns from the first that holds the text in a region to the last, the gaps between words included.
    func inkColumns(in region: Region, isText: (Int) -> Bool) -> Range<Int> {
        let inked = region.columns.filter { column in
            region.rows.contains { row in !excluded[row * width + column] && isText(row * width + column) }
        }
        guard let first = inked.first, let last = inked.last else { return 0..<0 }
        return first..<(last + 1)
    }

    /// The pixels joined to `seed` by their sides that match, each marked visited.
    func component(from seed: Int, visited: inout [Bool], matching matches: (Int) -> Bool) -> Component {
        var members = [Int]()
        var stack = [seed]
        visited[seed] = true
        var columns = (lower: width, upper: 0)
        var rows = (lower: height, upper: 0)
        while let index = stack.popLast() {
            members.append(index)
            let (row, column) = (index / width, index % width)
            columns = (min(columns.lower, column), max(columns.upper, column))
            rows = (min(rows.lower, row), max(rows.upper, row))
            for (nearRow, nearColumn) in [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)]
                where nearRow >= 0 && nearRow < height && nearColumn >= 0 && nearColumn < width {
                let near = nearRow * width + nearColumn
                if !visited[near], matches(near) {
                    visited[near] = true
                    stack.append(near)
                }
            }
        }
        return Component(members: members, columns: columns.lower..<(columns.upper + 1), rows: rows.lower..<(rows.upper + 1))
    }
}
