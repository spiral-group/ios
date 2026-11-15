//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import SwiftUI

// AGENT-PLATFORM (Brief 0083, decision 320): Spiral draws Compound's icon keys as SF Symbols,
// behind the same `CompoundIcons` key paths, so no call site changes. The table and its reasons:
// `DESIGNS/sf-symbols-mapping-2026-11-03.md` in the workspace docs.

/// What Spiral draws for one of Compound's icon keys.
enum SpiralSymbol: Equatable {
    /// An SF Symbol: outline, or its `.fill` for a `…Solid` key.
    case system(String)
    /// Compound's own glyph: the video call family keeps it until the designer's land (decision 320).
    case compound
}

enum SpiralSymbols {
    /// What a `CompoundIcon` draws.
    enum Drawing: Equatable {
        /// An SF Symbol, with the asset's name as its VoiceOver label, as the asset had.
        case symbol(name: String, label: String)
        /// Compound's asset.
        case asset
    }
    
    struct Row {
        /// The `CompoundIcons` property, which is also its asset's name.
        let name: String
        let keyPath: KeyPath<CompoundIcons, Image>
        let symbol: SpiralSymbol
        
        init(_ name: String, _ keyPath: KeyPath<CompoundIcons, Image>, _ symbol: SpiralSymbol) {
            self.name = name
            self.keyPath = keyPath
            self.symbol = symbol
        }
    }
    
    private static var drawings: [KeyPath<CompoundIcons, Image>: Drawing] = [:]
    private static let rowsByKeyPath = Dictionary(rows.map { ($0.keyPath, $0) }) { first, _ in first }
    
    /// Resolved once per key.
    static func drawing(for keyPath: KeyPath<CompoundIcons, Image>) -> Drawing {
        if let cached = drawings[keyPath] {
            return cached
        }
        let resolved = drawing(for: rowsByKeyPath[keyPath])
        drawings[keyPath] = resolved
        return resolved
    }
    
    /// A key without a row (a newer tokens release) or a symbol this OS lacks keeps Compound's asset:
    /// `Image(systemName:)` would draw nothing.
    static func drawing(for row: Row?) -> Drawing {
        guard let row, case let .system(name) = row.symbol, UIImage(systemName: name) != nil else {
            return .asset
        }
        return .symbol(name: name, label: row.name)
    }
}

extension SpiralSymbols {
    /// The image `CompoundIcon` draws: the SF Symbol, or the resizable asset.
    static func image(for drawing: Drawing, asset: Image) -> Image {
        switch drawing {
        case .symbol(let name, _):
            // Without it a symbol's preferred mode can draw a grey second layer.
            Image(systemName: name).symbolRenderingMode(.monochrome)
        case .asset:
            asset.resizable()
        }
    }
}

/// Sizes an SF Symbol at 0.8 × Compound's frame, centred and smaller where its ink would leave the
/// frame, regular unless an outer `fontWeight` says otherwise, and keeps the asset's baseline and
/// VoiceOver label. An asset or a custom image draws exactly as upstream's `CompoundIcon` drew it.
///
/// A symbol and an asset share this one modifier chain, whose values differ instead: a `CompoundIcon`
/// whose body switched between them crashed SwiftUI as a menu's label inside a `ViewThatFits`
/// ("accessing attribute in a different namespace"), the Feed's post cards among them.
struct SpiralSymbolStyle: ViewModifier {
    private let symbol: (name: String, label: String)?
    @ScaledMetric private var size: CGFloat
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.locale) private var locale
    
    /// The variant iOS draws here decides whether the symbol's ink would leave its frame.
    private var fit: SpiralSymbols.Fit {
        guard let symbol else { return .init() }
        return SpiralSymbols.fit(for: .init(name: symbol.name,
                                            layoutDirection: layoutDirection,
                                            isBold: legibilityWeight == .bold,
                                            localeIdentifier: locale.identifier))
    }
    
    init(drawing: SpiralSymbols.Drawing, size: CGFloat, textStyle: Font.TextStyle) {
        if case let .symbol(name, label) = drawing {
            symbol = (name, label)
        } else {
            symbol = nil
        }
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }
    
    func body(content: Content) -> some View {
        let isSymbol = symbol != nil
        let placement = fit
        let pointSize = size * SpiralSymbols.pointSizeShare * placement.scale
        content
            .transformEnvironment(\.font) { font in
                if isSymbol { font = .system(size: pointSize) }
            }
            .transformEnvironment(\.imageScale) { scale in
                if isSymbol { scale = .medium }
            }
            // Moves only the drawing: the frame, and the baseline it gives a row of text, stay.
            .offset(x: placement.offset.width * pointSize, y: placement.offset.height * pointSize)
            // An asset's baseline is its bottom edge; the stacks aligned on text baselines rely on it.
            .alignmentGuide(.firstTextBaseline) { isSymbol ? $0[.bottom] : $0[.firstTextBaseline] }
            .alignmentGuide(.lastTextBaseline) { isSymbol ? $0[.bottom] : $0[.lastTextBaseline] }
            .accessibilityLabel(Text(verbatim: symbol?.label ?? ""), isEnabled: isSymbol)
    }
}

extension SpiralSymbols {
    /// A symbol's point size is this share of Compound's frame (decision 320).
    static let pointSizeShare: CGFloat = 0.8
    
    /// What iOS draws for a name depends on more than the name: it picks a right-to-left variant by
    /// direction, a script variant by language (`textformat` in Hindi is half again as wide as in
    /// English) and, with Bold Text, a heavier weight.
    struct Variant: Hashable {
        let name: String
        let layoutDirection: LayoutDirection
        let isBold: Bool
        let localeIdentifier: String
    }
    
    /// How a symbol draws in its frame, which `ListRowLabel` clips to on iOS 26 and later. A symbol that
    /// fits stays where SwiftUI puts it. One whose ink would leave the frame moves so its ink is centred,
    /// and shrinks only as far as it must.
    struct Fit: Equatable {
        /// The share of the symbol's point size.
        var scale: CGFloat = 1
        /// How far the drawing moves, as a share of the point size it draws at.
        var offset = CGSize.zero
    }
    
    private static var fits: [Variant: Fit] = [:]
    
    /// Measured once per variant. The ink grows with the point size, so one fit holds at every text size.
    static func fit(for variant: Variant) -> Fit {
        if let cached = fits[variant] {
            return cached
        }
        let measured = measuredFit(for: variant)
        fits[variant] = measured
        return measured
    }
    
    /// SwiftUI centres a symbol's layout box in the frame: the width of its alignment rectangle, which
    /// a badge may overhang, and the full height of its image. The ink lies inside the image, so a
    /// symbol whose image fits needs no drawing.
    private static func measuredFit(for variant: Variant) -> Fit {
        let pointSize: CGFloat = 100
        let traits = UITraitCollection(layoutDirection: variant.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            .modifyingTraits { $0.legibilityWeight = variant.isBold ? .bold : .regular }
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium)
            .applying(UIImage.SymbolConfiguration.preferringMonochrome())
            .withTraitCollection(traits)
            .withLocale(Locale(identifier: variant.localeIdentifier))
        guard let image = UIImage(systemName: variant.name, withConfiguration: configuration) else { return Fit() }
        
        var insets = image.alignmentRectInsets
        if image.imageOrientation == .upMirrored {
            swap(&insets.left, &insets.right) // A mirrored image reports its insets unmirrored; SwiftUI mirrors them.
        }
        let centre = CGPoint(x: (insets.left + image.size.width - insets.right) / 2, y: image.size.height / 2)
        let halfFrame = pointSize / pointSizeShare / 2
        guard reach(of: CGRect(origin: .zero, size: image.size), from: centre) > halfFrame,
              let ink = inkBounds(of: image),
              reach(of: ink, from: centre) > halfFrame else {
            return Fit()
        }
        let mirroring: CGFloat = variant.layoutDirection == .rightToLeft ? -1 : 1 // SwiftUI mirrors an offset right to left.
        return Fit(scale: min(1, 2 * halfFrame / max(ink.width, ink.height)),
                   offset: CGSize(width: mirroring * (centre.x - ink.midX) / pointSize, height: (centre.y - ink.midY) / pointSize))
    }
    
    private static func reach(of rect: CGRect, from centre: CGPoint) -> CGFloat {
        max(centre.x - rect.minX, rect.maxX - centre.x, centre.y - rect.minY, rect.maxY - centre.y)
    }
    
    /// The pixels the image covers at least half, drawn at 2 ×.
    private static func inkBounds(of image: UIImage) -> CGRect? {
        let scale: CGFloat = 2
        let width = Int((image.size.width * scale).rounded(.up))
        let height = Int((image.size.height * scale).rounded(.up))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else {
            return nil
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        image.draw(at: .zero)
        UIGraphicsPopContext()
        guard let alpha = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        
        var minX = width, maxX = -1, minY = -1, maxY = -1
        for y in 0..<height {
            let row = alpha + y * width
            var left = 0
            while left < width, row[left] < 128 {
                left += 1
            }
            guard left < width else { continue }
            var right = width - 1
            while row[right] < 128 {
                right -= 1
            }
            minX = min(minX, left)
            maxX = max(maxX, right)
            if minY < 0 { minY = y }
            maxY = y
        }
        guard minY >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }
}

extension SpiralSymbols {
    /// One row per `CompoundIcons` key. `SpiralSymbolsTests` fails on a key without one.
    ///
    /// Traps the table guards against:
    /// - `chevronRight` stays `chevron.right`: `ListRowAccessory` flips it in right to left,
    ///   and `chevron.forward` would flip twice. Left and right names never mirror, as before.
    /// - `reply`, `forward`, `signOut`, `popOut` and `backspace…` take SF's `forward`/`backward`
    ///   names, so they mirror in right to left.
    /// - Apple reserves every `video.*` camera for FaceTime, so the video call family keeps
    ///   Compound's glyph until the designer's. Until theirs, `translate` takes `character.bubble`
    ///   (`translate` is Apple's), `reactionAdd` `face.smiling` and `host` (Agents) `sparkles`.
    static let rows: [Row] = [
        .init("admin", \.admin, .system("shield")),
        .init("advancedSettings", \.advancedSettings, .system("wrench.adjustable")),
        .init("arrowDown", \.arrowDown, .system("arrow.down")),
        .init("arrowLeft", \.arrowLeft, .system("arrow.left")),
        .init("arrowRight", \.arrowRight, .system("arrow.right")),
        .init("arrowUp", \.arrowUp, .system("arrow.up")),
        .init("arrowUpRight", \.arrowUpRight, .system("arrow.up.right")),
        .init("askToJoin", \.askToJoin, .system("person.badge.clock")),
        .init("askToJoinSolid", \.askToJoinSolid, .system("person.badge.clock.fill")),
        .init("attachment", \.attachment, .system("paperclip")),
        .init("audio", \.audio, .system("waveform")),
        .init("backspace", \.backspace, .system("delete.backward")),
        .init("backspaceSolid", \.backspaceSolid, .system("delete.backward.fill")),
        .init("block", \.block, .system("nosign")),
        .init("bluetoothOutput", \.bluetoothOutput, .system("hifispeaker")),
        .init("blur", \.blur, .system("person.and.background.dotted")),
        .init("bold", \.bold, .system("bold")),
        .init("bug", \.bug, .system("ladybug")),
        .init("calendar", \.calendar, .system("calendar")),
        .init("captions", \.captions, .system("captions.bubble")),
        .init("captionsSolid", \.captionsSolid, .system("captions.bubble.fill")),
        .init("chart", \.chart, .system("chart.bar")),
        .init("chat", \.chat, .system("bubble.left")),
        .init("chatNew", \.chatNew, .system("plus.bubble")),
        .init("chatProblem", \.chatProblem, .system("exclamationmark.bubble")),
        .init("chatSolid", \.chatSolid, .system("bubble.left.fill")),
        .init("check", \.check, .system("checkmark")),
        .init("checkCircle", \.checkCircle, .system("checkmark.circle")),
        .init("checkCircleSolid", \.checkCircleSolid, .system("checkmark.circle.fill")),
        .init("chevronDown", \.chevronDown, .system("chevron.down")),
        .init("chevronLeft", \.chevronLeft, .system("chevron.left")),
        .init("chevronRight", \.chevronRight, .system("chevron.right")),
        .init("chevronUp", \.chevronUp, .system("chevron.up")),
        .init("chevronUpDown", \.chevronUpDown, .system("chevron.up.chevron.down")),
        .init("circle", \.circle, .system("circle")),
        .init("close", \.close, .system("xmark")),
        .init("cloud", \.cloud, .system("cloud")),
        .init("cloudSolid", \.cloudSolid, .system("cloud.fill")),
        .init("code", \.code, .system("curlybraces.square")),
        .init("collapse", \.collapse, .system("arrow.down.right.and.arrow.up.left")),
        .init("collapseAll", \.collapseAll, .system("arrow.down.and.line.horizontal.and.arrow.up")),
        .init("company", \.company, .system("building.2")),
        .init("compose", \.compose, .system("square.and.pencil")),
        .init("computer", \.computer, .system("laptopcomputer")),
        .init("copy", \.copy, .system("doc.on.doc")),
        .init("crop", \.crop, .system("crop")),
        .init("darkMode", \.darkMode, .system("moon")),
        .init("delete", \.delete, .system("trash")),
        .init("devicePasskey", \.devicePasskey, .system("rectangle.and.pencil.and.ellipsis")),
        .init("devices", \.devices, .system("laptopcomputer.and.iphone")),
        .init("dialPad", \.dialPad, .system("circle.grid.3x3")),
        .init("document", \.document, .system("doc.text")),
        .init("download", \.download, .system("square.and.arrow.down")),
        .init("downloadIos", \.downloadIos, .system("square.and.arrow.down")),
        .init("dragGrid", \.dragGrid, .system("circle.grid.2x2")),
        .init("dragList", \.dragList, .system("line.3.horizontal")),
        .init("earpiece", \.earpiece, .system("ear")),
        .init("edit", \.edit, .system("pencil")),
        .init("editSolid", \.editSolid, .system("pencil")),
        .init("email", \.email, .system("envelope")),
        .init("emailSolid", \.emailSolid, .system("envelope.fill")),
        .init("endCall", \.endCall, .system("phone.down.fill")),
        .init("error", \.error, .system("exclamationmark.circle")),
        .init("errorSolid", \.errorSolid, .system("exclamationmark.circle.fill")),
        .init("exitFullScreen", \.exitFullScreen, .system("arrow.down.right.and.arrow.up.left")),
        .init("expand", \.expand, .system("arrow.up.left.and.arrow.down.right")),
        .init("expandAll", \.expandAll, .system("arrow.up.and.line.horizontal.and.arrow.down")),
        .init("explore", \.explore, .system("binoculars")),
        .init("exportArchive", \.exportArchive, .system("archivebox")),
        .init("extensions", \.extensions, .system("puzzlepiece.extension")),
        .init("extensionsSolid", \.extensionsSolid, .system("puzzlepiece.extension.fill")),
        .init("favourite", \.favourite, .system("star")),
        .init("favouriteSolid", \.favouriteSolid, .system("star.fill")),
        .init("fileError", \.fileError, .system("text.page.slash")),
        .init("files", \.files, .system("doc")),
        .init("filter", \.filter, .system("line.3.horizontal.decrease")),
        .init("flipHorizontal", \.flipHorizontal, .system("arrow.left.and.right.righttriangle.left.righttriangle.right")),
        .init("flipVertical", \.flipVertical, .system("arrow.up.and.down.righttriangle.up.righttriangle.down")),
        .init("folder", \.folder, .system("folder")),
        .init("forward", \.forward, .system("arrowshape.turn.up.forward")),
        .init("fullScreen", \.fullScreen, .system("arrow.up.left.and.arrow.down.right")),
        .init("grid", \.grid, .system("square.grid.2x2")),
        .init("group", \.group, .system("person.2")),
        .init("guest", \.guest, .system("person.crop.circle.badge.questionmark")),
        .init("guestSolid", \.guestSolid, .system("person.crop.circle.badge.questionmark.fill")),
        .init("headphonesOffSolid", \.headphonesOffSolid, .system("headphones.slash")),
        .init("headphonesSolid", \.headphonesSolid, .system("headphones")),
        .init("help", \.help, .system("questionmark.circle")),
        .init("helpSolid", \.helpSolid, .system("questionmark.circle.fill")),
        .init("history", \.history, .system("clock.arrow.circlepath")),
        .init("home", \.home, .system("house")),
        .init("homeSolid", \.homeSolid, .system("house.fill")),
        .init("host", \.host, .system("sparkles")),
        .init("hourglass", \.hourglass, .system("hourglass")),
        .init("hourglassSolid", \.hourglassSolid, .system("hourglass.tophalf.filled")),
        .init("image", \.image, .system("photo")),
        .init("imageError", \.imageError, .system("photo.badge.exclamationmark")),
        .init("indentDecrease", \.indentDecrease, .system("decrease.indent")),
        .init("indentIncrease", \.indentIncrease, .system("increase.indent")),
        .init("info", \.info, .system("info.circle")),
        .init("infoSolid", \.infoSolid, .system("info.circle.fill")),
        .init("inlineCode", \.inlineCode, .system("chevron.left.forwardslash.chevron.right")),
        .init("italic", \.italic, .system("italic")),
        .init("key", \.key, .system("key.horizontal")),
        .init("keyboard", \.keyboard, .system("keyboard")),
        .init("keyOff", \.keyOff, .system("key.slash")),
        .init("keyOffSolid", \.keyOffSolid, .system("key.slash.fill")),
        .init("keySolid", \.keySolid, .system("key.horizontal.fill")),
        .init("labs", \.labs, .system("lightbulb.max")),
        .init("leave", \.leave, .system("door.left.hand.open")),
        .init("leftPanelClose", \.leftPanelClose, .system("sidebar.left")),
        .init("leftPanelOpen", \.leftPanelOpen, .system("sidebar.left")),
        .init("link", \.link, .system("link")),
        .init("linux", \.linux, .system("pc")),
        .init("listBulleted", \.listBulleted, .system("list.bullet")),
        .init("listNumbered", \.listNumbered, .system("list.number")),
        .init("listView", \.listView, .system("list.bullet.rectangle")),
        .init("locationNavigator", \.locationNavigator, .system("location")),
        .init("locationNavigatorCentred", \.locationNavigatorCentred, .system("location.fill")),
        .init("locationPin", \.locationPin, .system("mappin.and.ellipse")),
        .init("locationPinSolid", \.locationPinSolid, .system("mappin.circle.fill")),
        .init("lock", \.lock, .system("lock")),
        .init("lockOff", \.lockOff, .system("lock.slash.fill")),
        .init("lockSolid", \.lockSolid, .system("lock.fill")),
        .init("mac", \.mac, .system("desktopcomputer")),
        .init("markAsRead", \.markAsRead, .system("envelope.open")),
        .init("markAsUnread", \.markAsUnread, .system("envelope.badge")),
        .init("markerReadReceipts", \.markerReadReceipts, .system("checkmark.bubble")),
        .init("markThreadsAsRead", \.markThreadsAsRead, .system("text.badge.checkmark")),
        .init("mention", \.mention, .system("at")),
        .init("menu", \.menu, .system("line.3.horizontal")),
        .init("micOff", \.micOff, .system("mic.slash")),
        .init("micOffSolid", \.micOffSolid, .system("mic.slash.fill")),
        .init("micOn", \.micOn, .system("mic")),
        .init("micOnSolid", \.micOnSolid, .system("mic.fill")),
        .init("minus", \.minus, .system("minus")),
        .init("mobile", \.mobile, .system("smartphone")),
        .init("notifications", \.notifications, .system("bell")),
        .init("notificationsOff", \.notificationsOff, .system("bell.slash")),
        .init("notificationsOffSolid", \.notificationsOffSolid, .system("bell.slash.fill")),
        .init("notificationsSolid", \.notificationsSolid, .system("bell.fill")),
        .init("offline", \.offline, .system("wifi.slash")),
        .init("overflowHorizontal", \.overflowHorizontal, .system("ellipsis")),
        .init("overflowVertical", \.overflowVertical, .system("ellipsis")),
        .init("pause", \.pause, .system("pause")),
        .init("pauseSolid", \.pauseSolid, .system("pause.fill")),
        .init("pin", \.pin, .system("pin")),
        .init("pinSolid", \.pinSolid, .system("pin.fill")),
        .init("play", \.play, .system("play")),
        .init("playSolid", \.playSolid, .system("play.fill")),
        .init("plus", \.plus, .system("plus")),
        .init("polls", \.polls, .system("checklist")),
        .init("pollsEnd", \.pollsEnd, .system("checklist.checked")),
        .init("popIn", \.popIn, .system("arrow.down.left.square")),
        .init("popOut", \.popOut, .system("arrow.up.forward.square")),
        .init("preferences", \.preferences, .system("switch.2")),
        .init("presenceOutline8X8", \.presenceOutline8X8, .system("circle")),
        .init("presenceSolid8X8", \.presenceSolid8X8, .system("circle.fill")),
        .init("presenceStrikethrough8X8", \.presenceStrikethrough8X8, .system("circle.slash")),
        .init("public", \.public, .system("globe")),
        .init("qrCode", \.qrCode, .system("qrcode")),
        .init("quote", \.quote, .system("quote.opening")),
        .init("raisedHandSolid", \.raisedHandSolid, .system("hand.raised.fill")),
        .init("reaction", \.reaction, .system("face.smiling")),
        .init("reactionAdd", \.reactionAdd, .system("face.smiling")),
        .init("reactionSolid", \.reactionSolid, .system("face.smiling.fill")),
        .init("record", \.record, .system("record.circle")),
        .init("recordBorder", \.recordBorder, .system("circle")),
        .init("recordDot", \.recordDot, .system("circlebadge.fill")),
        .init("reOrder", \.reOrder, .system("line.3.horizontal")),
        .init("reply", \.reply, .system("arrowshape.turn.up.backward")),
        .init("restart", \.restart, .system("arrow.counterclockwise")),
        .init("room", \.room, .system("number")),
        .init("rotateLeft", \.rotateLeft, .system("rotate.left")),
        .init("rotateRight", \.rotateRight, .system("rotate.right")),
        .init("save", \.save, .system("bookmark")),
        .init("saveSolid", \.saveSolid, .system("bookmark.fill")),
        .init("search", \.search, .system("magnifyingglass")),
        .init("section", \.section, .system("list.bullet.rectangle")),
        .init("send", \.send, .system("paperplane")),
        .init("sendSolid", \.sendSolid, .system("paperplane.fill")),
        .init("settings", \.settings, .system("gearshape")),
        .init("settingsSolid", \.settingsSolid, .system("gearshape.fill")),
        .init("share", \.share, .system("square.and.arrow.up")),
        .init("shareAndroid", \.shareAndroid, .system("square.and.arrow.up")),
        .init("shareIos", \.shareIos, .system("square.and.arrow.up")),
        .init("shareScreen", \.shareScreen, .system("rectangle.on.rectangle")),
        .init("shareScreenSolid", \.shareScreenSolid, .system("rectangle.fill.on.rectangle.fill")),
        .init("shield", \.shield, .system("checkmark.shield.fill")),
        .init("sidebar", \.sidebar, .system("sidebar.left")),
        .init("signOut", \.signOut, .system("rectangle.portrait.and.arrow.forward")),
        .init("smartTiles", \.smartTiles, .system("rectangle.3.group")),
        .init("space", \.space, .system("point.3.connected.trianglepath.dotted")),
        .init("spaceSolid", \.spaceSolid, .system("point.3.filled.connected.trianglepath.dotted")),
        .init("spinner", \.spinner, .system("progress.indicator")),
        .init("spotlight", \.spotlight, .system("macwindow.badge.plus")),
        .init("spotlightView", \.spotlightView, .system("rectangle")),
        .init("sticker", \.sticker, .system("seal")),
        .init("stop", \.stop, .system("stop")),
        .init("stopSolid", \.stopSolid, .system("stop.fill")),
        .init("strikethrough", \.strikethrough, .system("strikethrough")),
        .init("switchCameraSolid", \.switchCameraSolid, .system("arrow.triangle.2.circlepath.camera.fill")),
        .init("takePhoto", \.takePhoto, .system("camera")),
        .init("takePhotoSolid", \.takePhotoSolid, .system("camera.fill")),
        .init("textFormatting", \.textFormatting, .system("textformat")),
        .init("theme", \.theme, .system("circle.lefthalf.filled")),
        .init("threads", \.threads, .system("text.bubble")),
        .init("threadsSolid", \.threadsSolid, .system("text.bubble.fill")),
        .init("time", \.time, .system("clock")),
        .init("transcribe", \.transcribe, .system("quote.bubble")),
        .init("translate", \.translate, .system("character.bubble")),
        .init("tree", \.tree, .system("point.topleft.down.to.point.bottomright.curvepath")),
        .init("underline", \.underline, .system("underline")),
        .init("unknown", \.unknown, .system("questionmark.square")),
        .init("unknownSolid", \.unknownSolid, .system("questionmark.square.fill")),
        .init("unpin", \.unpin, .system("pin.slash")),
        .init("unsave", \.unsave, .system("bookmark.slash")),
        .init("user", \.user, .system("person")),
        .init("userAdd", \.userAdd, .system("person.badge.plus")),
        .init("userAddSolid", \.userAddSolid, .system("person.fill.badge.plus")),
        .init("userProfile", \.userProfile, .system("person.crop.circle")),
        .init("userProfileSolid", \.userProfileSolid, .system("person.crop.circle.fill")),
        .init("userSolid", \.userSolid, .system("person.fill")),
        .init("verified", \.verified, .system("checkmark.seal.fill")),
        .init("videoCall", \.videoCall, .compound),
        .init("videoCallDeclinedSolid", \.videoCallDeclinedSolid, .compound),
        .init("videoCallMissedSolid", \.videoCallMissedSolid, .compound),
        .init("videoCallOff", \.videoCallOff, .compound),
        .init("videoCallOffSolid", \.videoCallOffSolid, .compound),
        .init("videoCallOutgoingSolid", \.videoCallOutgoingSolid, .compound),
        .init("videoCallSolid", \.videoCallSolid, .compound),
        .init("visibilityOff", \.visibilityOff, .system("eye.slash")),
        .init("visibilityOn", \.visibilityOn, .system("eye")),
        .init("voiceCall", \.voiceCall, .system("phone")),
        .init("voiceCallDeclinedSolid", \.voiceCallDeclinedSolid, .system("phone.down.fill")),
        .init("voiceCallMissedSolid", \.voiceCallMissedSolid, .system("phone.arrow.down.left.fill")),
        .init("voiceCallOutgoingSolid", \.voiceCallOutgoingSolid, .system("phone.arrow.up.right.fill")),
        .init("voiceCallSolid", \.voiceCallSolid, .system("phone.fill")),
        .init("volumeOff", \.volumeOff, .system("speaker.slash")),
        .init("volumeOffSolid", \.volumeOffSolid, .system("speaker.slash.fill")),
        .init("volumeOn", \.volumeOn, .system("speaker.wave.2")),
        .init("volumeOnSolid", \.volumeOnSolid, .system("speaker.wave.2.fill")),
        .init("warning", \.warning, .system("exclamationmark.triangle")),
        .init("webBrowser", \.webBrowser, .system("macwindow")),
        .init("windows", \.windows, .system("pc")),
        .init("zoomIn", \.zoomIn, .system("plus.magnifyingglass")),
        .init("zoomOut", \.zoomOut, .system("minus.magnifyingglass"))
    ]
}
