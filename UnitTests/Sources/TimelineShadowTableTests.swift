//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the real table with real rows, in a window of the app's scene so that it draws, as what
// made a shadow vanish is what UIKit does to its cells in an animated update, and only a table can say so.
//

import MatrixRustSDK
@testable import Spiral
import SpiralTokens
import SwiftUI
import Testing

@MainActor
@Suite(AccessibilityTree())
struct TimelineShadowTableTests {
    // MARK: - What UIKit does in an update
    
    @Test
    func aRowArrivingLeavesEveryCellUnclipped() async throws {
        let screen = try await ShadowScreen(items: rows(0..<40))
        
        await screen.chat.deliver(rows(0..<41))
        let watch = await screen.watchTheUpdate()
        
        #expect(watch.didAnimate)
        #expect(watch.clippedCells == 0)
    }
    
    @Test
    func aRowChangingHeightLeavesEveryCellUnclipped() async throws {
        let screen = try await ShadowScreen(items: rows(0..<40))
        
        // Only a row just touched animates its resize (question 359).
        _ = screen.table.hitTest(CGPoint(x: 100, y: 100), with: nil)
        await screen.chat.deliver(rows(0..<40, long: [37]))
        let watch = await screen.watchTheUpdate()
        
        #expect(watch.didAnimate)
        #expect(watch.clippedCells == 0)
    }
    
    @Test
    func aShadowIsStillThereHalfWayThroughAnInsert() async throws {
        let screen = try await ShadowScreen(items: rows(0..<40))
        // The last bubble of a group, with a new group's gap under it. Clipped, all it keeps is the 1 pt of its own row.
        let atRest = try screen.pointsOfShadowUnderTheBubble(of: "34")
        
        await screen.chat.deliver(rows(0..<41))
        try await Task.sleep(for: .milliseconds(120))
        let halfWay = try screen.pointsOfShadowUnderTheBubble(of: "34", afterScreenUpdates: false)
        
        #expect(atRest >= 8)
        #expect(halfWay >= atRest - 2)
    }
    
    // MARK: - Which row lies on which
    
    @Test
    func aNewerRowLiesOnAnOlderOneThroughAnInsert() async throws {
        let screen = try await ShadowScreen(items: rows(0..<40))
        
        await screen.chat.deliver(rows(0..<41))
        let watch = await screen.watchTheUpdate()
        
        #expect(watch.didAnimate)
        #expect(watch.misorderedCells == 0)
    }
    
    @Test
    func noCellSlidesThroughTheStack() async throws {
        let screen = try await ShadowScreen(items: rows(0..<40))
        
        await screen.chat.deliver(rows(0..<41))
        let watch = await screen.watchTheUpdate()
        
        #expect(watch.didAnimate)
        #expect(watch.cellsAnimatingTheirPlace == 0)
    }
    
    @Test
    func aNewerRowLiesOnAnOlderOneThroughAnAnimatedResize() async throws {
        let screen = try await ShadowScreen(items: rows(0..<40))
        
        // Only a row just touched animates its resize (question 359).
        _ = screen.table.hitTest(CGPoint(x: 100, y: 100), with: nil)
        await screen.chat.deliver(rows(0..<40, long: [37]))
        var watch = await screen.watchTheUpdate()
        #expect(watch.didAnimate)
        #expect(watch.misorderedCells == 0)
        
        await screen.chat.deliver(rows(0..<40))
        watch = await screen.watchTheUpdate()
        #expect(watch.misorderedCells == 0)
    }
    
    @Test
    func aNewerRowLiesOnAnOlderOneThroughAReload() async throws {
        let screen = try await ShadowScreen(items: rows(0..<40))
        
        try screen.tableViewController().hideTimelineMedia = true
        let watch = await screen.watchTheUpdate()
        
        #expect(watch.misorderedCells == 0)
    }
    
    @Test
    func aNewerRowLiesOnAnOlderOneThroughAScroll() async throws {
        let screen = try await ShadowScreen(items: rows(0..<80))
        
        for step in 0..<25 {
            screen.table.contentOffset.y = CGFloat(step) * 60
            await screen.nextFrame()
            #expect(screen.misorderedCells() == 0)
        }
    }
    
    @Test
    func rowsLoadedAtTheOlderEndStackBehind() async throws {
        let screen = try await ShadowScreen(items: rows(30..<60))
        
        await screen.chat.deliver(rows(0..<60))
        let watch = await screen.watchTheUpdate()
        
        #expect(watch.misorderedCells == 0)
    }
    
    @Test
    func noCellSharesItsPlaceInTheStack() async throws {
        let screen = try await ShadowScreen(items: rows(0..<40))
        
        let positions = screen.cells.map(\.layer.zPosition)
        
        #expect(Set(positions).count == positions.count)
    }
    
    // MARK: - What a row owns
    
    @Test
    func noShadowRisesOutOfItsRow() async throws {
        let screen = try await ShadowScreen(items: everyKindOfRow())
        
        var shadows = 0
        for cell in screen.cells {
            let row = cell.convert(cell.bounds, to: screen.window)
            for layer in screen.shadowLayers(in: cell) {
                let shadow = layer.convert(layer.bounds, to: screen.window.layer)
                shadows += 1
                #expect(shadow.minY >= row.minY - 0.5, "\(cell.item?.identifier.uniqueID.value ?? "?") rises \(row.minY - shadow.minY) pt")
            }
        }
        
        #expect(shadows > 10)
    }
    
    @Test
    func aBubbleInAGroupStillCastsItsShadowDown() async throws {
        let screen = try await ShadowScreen(items: rows(0..<10))
        
        for cell in screen.cells {
            let row = cell.convert(cell.bounds, to: screen.window)
            for layer in screen.shadowLayers(in: cell) {
                #expect(layer.convert(layer.bounds, to: screen.window.layer).maxY > row.maxY + 10)
            }
        }
    }
    
    @Test
    func noLayerCastsAShadowOfItsOwn() async throws {
        let screen = try await ShadowScreen(items: everyKindOfRow())
        
        for cell in screen.cells {
            #expect(screen.liveShadows(in: cell.layer) == 0)
        }
    }
    
    // MARK: - A group of room changes
    
    @Test
    func aGroupOpensInsideItsRow() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        
        let watch = try await screen.pressTheGroup()
        
        #expect(watch.didMoveRows)
        #expect(watch.didShowRows)
        #expect(watch.riseAboveTheRow < 1, "Rises \(watch.riseAboveTheRow) pt")
        #expect(watch.fallBelowTheRow < 1, "Falls \(watch.fallBelowTheRow) pt")
    }
    
    @Test
    func aGroupClosesInsideItsRow() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        try await screen.pressTheGroup()
        
        let watch = try await screen.pressTheGroup()
        
        #expect(watch.didMoveRows)
        #expect(watch.didShowRows)
        #expect(watch.riseAboveTheRow < 1, "Rises \(watch.riseAboveTheRow) pt")
        #expect(watch.fallBelowTheRow < 1, "Falls \(watch.fallBelowTheRow) pt")
    }
    
    @Test
    func aGroupsRowsAppearAndGoInPlace() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        
        let opening = try await screen.pressTheGroup()
        let closing = try await screen.pressTheGroup()
        
        #expect(opening.driftOfTheRows < 4, "Opening moves them \(opening.driftOfTheRows) pt")
        #expect(closing.driftOfTheRows < 4, "Closing moves them \(closing.driftOfTheRows) pt")
    }
    
    @Test
    func aGroupEndsAtTheHeightItStartedFrom() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        let closed = try screen.groupCell().frame.height
        
        try await screen.pressTheGroup()
        let open = try screen.groupCell().frame.height
        try await screen.pressTheGroup()
        
        #expect(open > closed + 100)
        #expect(try screen.groupCell().frame.height == closed)
    }
    
    @Test
    func aGroupPressedAgainWhileClosingEndsOpen() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        try await screen.pressTheGroup()
        let open = try screen.groupCell().frame.height
        
        try screen.pressGroupButton()
        try await Task.sleep(for: .milliseconds(50))
        try screen.pressGroupButton()
        try await Task.sleep(for: .milliseconds(250))
        
        // The row never closed, so the rows come back without waiting for it.
        #expect(try screen.opacityOfTheGroupsRows() > 0.9)
        #expect(try screen.groupCell().frame.height == open)
    }
    
    @Test
    func aGroupPressedAgainWhileOpeningEndsClosed() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        let closed = try screen.groupCell().frame.height
        
        try screen.pressGroupButton()
        try await Task.sleep(for: .milliseconds(100))
        try await screen.pressTheGroup()
        
        #expect(try screen.groupCell().frame.height == closed)
    }
    
    @Test
    func aShadowIsStillThereHalfWayThroughAGroupOpening() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        // The newest bubble above the group. Clipped, all it keeps is the 1 pt of its own row. Looked at late in the update, which
        // clips for all of its length: early on the row moves further than this can follow between reading it and drawing it.
        let atRest = try screen.pointsOfShadowUnderTheBubble(of: "29")
        
        try screen.pressGroupButton()
        try await Task.sleep(for: .milliseconds(250))
        let halfWay = try screen.pointsOfShadowUnderTheBubble(of: "29", afterScreenUpdates: false)
        
        #expect(atRest >= 8)
        #expect(halfWay >= atRest - 2, "\(halfWay) of \(atRest) points")
    }
    
    @Test
    func theLastRowOfAnOpenGroupKeepsItsShadow() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        
        try await screen.pressTheGroup()
        
        let row = try screen.groupCell().convert(screen.groupCell().bounds, to: screen.window)
        #expect(try screen.isShaded(x: row.midX, y: row.maxY + 1))
    }
    
    @Test
    func theChevronTurnsAsTheGroupIsPressed() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        
        let watch = try await screen.pressTheGroup()
        
        #expect(watch.didTurnTheChevron)
    }
    
    @Test
    func reduceMotionMovesNothing() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        Switches.setReduceMotion(true)
        defer { Switches.setReduceMotion(false) }
        await screen.nextFrame()
        
        let opening = try await screen.pressTheGroup()
        let closing = try await screen.pressTheGroup()
        
        #expect(!opening.didMoveRows)
        #expect(!closing.didMoveRows)
        #expect(opening.opacityOfTheRowsAtTheEnd > 0.95)
    }
    
    @Test
    func reduceMotionOpensAndClosesAGroupAtOnce() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        let closed = try screen.groupCell().frame.height
        Switches.setReduceMotion(true)
        defer { Switches.setReduceMotion(false) }
        await screen.nextFrame()
        
        try screen.pressGroupButton()
        try await Task.sleep(for: .milliseconds(50))
        #expect(try screen.opacityOfTheGroupsRows() > 0.95)
        
        try screen.pressGroupButton()
        try await Task.sleep(for: .milliseconds(50))
        #expect(try screen.groupCell().frame.height == closed)
    }
    
    @Test
    func voiceOverOpensAGroupAtOnce() async throws {
        let screen = try await ShadowScreen(items: chatWithAGroup())
        Switches.setVoiceOver(true)
        defer { Switches.setVoiceOver(false) }
        await screen.nextFrame()
        #expect(UIAccessibility.isVoiceOverRunning)
        
        try screen.pressGroupButton()
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(try screen.opacityOfTheGroupsRows() > 0.95)
    }
    
    // MARK: - A row that changes height
    
    @Test
    func aShrinkingRowStaysOffTheOlderRow() async throws {
        let screen = try await ShadowScreen(items: rows(0..<40, long: [37]))
        
        // Only a row just touched animates its resize (question 359).
        _ = screen.table.hitTest(CGPoint(x: 100, y: 100), with: nil)
        let watch = await screen.watchARowChange(of: "37") { await screen.chat.deliver(rows(0..<40)) }
        
        #expect(watch.didMoveRows)
        #expect(watch.riseAboveTheRow < 1, "Rises \(watch.riseAboveTheRow) pt")
    }
    
    // MARK: - Helpers
    
    private func rows(_ range: Range<Int>, long: Set<Int> = []) -> [RoomTimelineItemProtocol] {
        range.map { index in
            // Two of yours, then three of theirs, so groups of every style and of different widths.
            let isOutgoing = index % 5 < 2
            return TextRoomTimelineItem(id: .event(uniqueID: .init("\(index)"), eventOrTransactionID: .eventID("$\(index)")),
                                        timestamp: Date(timeIntervalSince1970: 1000 + Double(index)),
                                        isOutgoing: isOutgoing,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: .init(id: isOutgoing ? RoomMemberProxyMock.mockMe.userID : "@alice:spiral.test"),
                                        content: .init(body: long.contains(index) ? String(repeating: "A message over several lines. ", count: 8) : "Message \(index)"))
        }
    }
    
    private func chatWithAGroup() -> [RoomTimelineItemProtocol] {
        let date = Date(timeIntervalSince1970: 1000)
        let group = CollapsibleTimelineItem(items: (0..<5).map { index in
            StateRoomTimelineItem(id: .event(uniqueID: .init("change \(index)"), eventOrTransactionID: .eventID("$change\(index)")),
                                  body: "Alice changed the room name",
                                  timestamp: date,
                                  isOutgoing: false,
                                  isEditable: false,
                                  canBeRepliedTo: false,
                                  sender: .init(id: "@alice:spiral.test"))
        })
        return rows(0..<30) + [group] + rows(30..<33)
    }
    
    private func everyKindOfRow() -> [RoomTimelineItemProtocol] {
        let date = Date(timeIntervalSince1970: 1000)
        return [
            SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("day")), timestamp: date),
            StateRoomTimelineItem(id: .event(uniqueID: .init("joined"), eventOrTransactionID: .eventID("$joined")),
                                  body: "Alice joined the room",
                                  timestamp: date,
                                  isOutgoing: false,
                                  isEditable: false,
                                  canBeRepliedTo: false,
                                  sender: .init(id: "@alice:spiral.test"))
        ] + rows(0..<4) + [
            CallNotificationRoomTimelineItem(id: .event(uniqueID: .init("call"), eventOrTransactionID: .eventID("$call")),
                                             timestamp: date,
                                             sender: .init(id: "@alice:spiral.test"),
                                             isDM: false,
                                             isVoiceCall: true,
                                             callState: .tombstoned(outcome: .groupCall(duration: 310, ownUserJoined: true))),
            ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init("marker")))
        ] + rows(4..<8)
    }
}

/// A chat on the room's background in a window of the scene.
@MainActor
private final class ShadowScreen {
    /// What an update did to the cells while it animated.
    struct Watch {
        var didAnimate = false
        var clippedCells = 0
        var misorderedCells = 0
        var cellsAnimatingTheirPlace = 0
    }
    
    /// What a row's content did while its height animated, as drawn. Its shadow isn't counted: that reaches past the row by design.
    struct RowWatch {
        var didMoveRows = false
        var didShowRows = false
        var didTurnTheChevron = false
        var riseAboveTheRow: CGFloat = 0
        var fallBelowTheRow: CGFloat = 0
        var driftOfTheRows: CGFloat = 0
        var opacityOfTheRowsAtTheEnd: Float = 0
    }
    
    private struct DrawnLayer {
        let frame: CGRect
        let opacity: Float
        let isShape: Bool
    }
    
    let chat: TimelineTestChat
    let window: UIWindow
    let table: UITableView
    
    var cells: [TimelineItemCell] {
        table.subviews.compactMap { $0 as? TimelineItemCell }.filter { !$0.isHidden }
    }
    
    init(items: [RoomTimelineItemProtocol]) async throws {
        Switches.reset()
        chat = TimelineTestChat(items: items, isSettled: false)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.windowLevel = .alert + 1
        window.backgroundColor = .white
        window.isHidden = false
        window.rootViewController = UIHostingController(rootView: TimelineView(timelineContext: chat.viewModel.context)
            .environment(\.isChatBackgroundDrawn, true))
        window.layoutIfNeeded()
        table = try #require(Self.tableView(in: window))
        try await Task.sleep(for: .milliseconds(400))
        // Left on, it stops every animation these tests watch and they'd fail, or pass, for the wrong reason.
        #expect(!UIAccessibility.isReduceMotionEnabled)
    }
    
    deinit {
        // A window left on screen would cover the next test's.
        MainActor.assumeIsolated { [window] in
            window.isHidden = true
            Switches.setRealAnimations(false)
        }
    }
    
    func tableViewController() throws -> TimelineTableViewController {
        var responder = table.next
        while responder != nil, !(responder is TimelineTableViewController) {
            responder = responder?.next
        }
        return try #require(responder as? TimelineTableViewController)
    }
    
    /// Looks at every cell on every frame while what's animating runs out, UIKit's being 0.3 to 0.4 s.
    func watchTheUpdate() async -> Watch {
        var watch = Watch()
        let end = Date().addingTimeInterval(0.6)
        while Date() < end {
            watch.didAnimate = watch.didAnimate || cells.contains { $0.layer.animationKeys()?.contains("position") == true }
            watch.clippedCells += cells.count(where: \.clipsToBounds)
            watch.misorderedCells += misorderedCells()
            watch.cellsAnimatingTheirPlace += cells.count { $0.layer.animationKeys()?.contains("zPosition") == true }
            await nextFrame()
        }
        return watch
    }
    
    func groupCell() throws -> TimelineItemCell {
        try #require(cells.first { if case .group = $0.item?.type { true } else { false } })
    }
    
    /// Presses the group's button with the app's real animations, which tests otherwise turn off, and watches them run out.
    @discardableResult
    func pressTheGroup() async throws -> RowWatch {
        let cell = try groupCell()
        return await watchARowChange(in: cell) {
            try? self.pressGroupButton()
        }
    }
    
    /// Through the rows' accessibility tree, the one way a test has to press a button in a hosted row. See `AccessibilityTree`.
    func pressGroupButton() throws {
        let cell = try groupCell()
        let button = try #require(Self.button(in: cell))
        Switches.setRealAnimations(true) // Until the watch ends or the screen goes, as bodies read it when they next run.
        _ = table.hitTest(cell.center, with: nil) // Activating skips the touch a finger makes first, which is what lets a row animate.
        #expect(button.accessibilityActivate())
    }
    
    func opacityOfTheGroupsRows() throws -> Float {
        let content = try drawnContent(of: groupCell())
        return content.dropFirst(chipLayers).map(\.opacity).min() ?? 0
    }
    
    func watchARowChange(of uniqueID: String, change: () async -> Void) async -> RowWatch {
        guard let cell = cells.first(where: { $0.item?.identifier.uniqueID.value == uniqueID }) else {
            Issue.record("No row \(uniqueID)")
            return RowWatch()
        }
        return await watchARowChange(in: cell, change: change)
    }
    
    private func watchARowChange(in cell: TimelineItemCell, change: () async -> Void) async -> RowWatch {
        var watch = RowWatch()
        var lowestRow: ClosedRange<CGFloat>?
        var widestChevron: CGFloat = 0
        
        Switches.setRealAnimations(true)
        defer { Switches.setRealAnimations(false) }
        await change()
        
        let end = Date().addingTimeInterval(1)
        while Date() < end {
            let row = onScreen(cell.layer)
            let content = drawnContent(of: cell)
            
            watch.didMoveRows = watch.didMoveRows || cells.contains { $0.layer.animationKeys()?.contains("position") == true }
            for layer in content where layer.opacity > 0.02 {
                watch.riseAboveTheRow = max(watch.riseAboveTheRow, row.minY - layer.frame.minY)
                watch.fallBelowTheRow = max(watch.fallBelowTheRow, layer.frame.maxY - row.maxY)
            }
            
            let rows = content.filter { $0.opacity > 0.15 }.dropFirst(chipLayers)
            watch.didShowRows = watch.didShowRows || !rows.isEmpty
            if let lowest = rows.map(\.frame.maxY).max() {
                lowestRow = min(lowestRow?.lowerBound ?? lowest, lowest)...max(lowestRow?.upperBound ?? lowest, lowest)
            }
            
            // Turning, its box is wider than it is at either end: 7.7 pt closed, 13.7 pt open.
            if let chevron = content.prefix(chipLayers).first(where: \.isShape) {
                widestChevron = max(widestChevron, chevron.frame.width)
            }
            await nextFrame()
        }
        
        watch.didTurnTheChevron = widestChevron > 14.5
        watch.driftOfTheRows = lowestRow.map { $0.upperBound - $0.lowerBound } ?? 0
        watch.opacityOfTheRowsAtTheEnd = drawnContent(of: cell).dropFirst(chipLayers).map(\.opacity).min() ?? 0
        return watch
    }
    
    /// A group's own line: its surface, title and chevron.
    private let chipLayers = 3
    
    /// What's drawn in a row, top to bottom, where it is on screen at this moment and how see-through.
    private func drawnContent(of cell: UITableViewCell) -> [DrawnLayer] {
        var content: [DrawnLayer] = []
        func visit(_ layer: CALayer, opacity: Float) {
            let current = layer.presentation() ?? layer
            let opacity = opacity * current.opacity
            guard !layer.isHidden else { return }
            let isShadow = layer.contents != nil && layer.contentsCenter != CGRect(x: 0, y: 0, width: 1, height: 1)
            let isSurface = (layer.backgroundColor?.alpha ?? 0) > 0
            let isShape = String(describing: type(of: layer)).contains("ShapeLayer")
            if !isShadow, layer.contents != nil || isSurface || isShape {
                content.append(DrawnLayer(frame: onScreen(layer), opacity: opacity, isShape: isShape))
            }
            (layer.sublayers ?? []).forEach { visit($0, opacity: opacity) }
        }
        visit(cell.contentView.layer, opacity: 1)
        return content.sorted { $0.frame.minY < $1.frame.minY }
    }
    
    private func onScreen(_ layer: CALayer) -> CGRect {
        let current = layer.presentation() ?? layer
        return current.convert(current.bounds, to: window.layer.presentation() ?? window.layer)
    }
    
    /// Pairs of neighbours on screen, as they are at this moment, where the newer isn't in front. The table is flipped, so it's the
    /// one with the smaller y.
    func misorderedCells() -> Int {
        let stack = cells.map { (y: $0.layer.presentation()?.frame.minY ?? $0.frame.minY, z: $0.layer.zPosition) }.sorted { $0.y < $1.y }
        return zip(stack, stack.dropFirst()).count { newer, older in newer.z <= older.z }
    }
    
    func nextFrame() async {
        try? await Task.sleep(for: .milliseconds(8))
    }
    
    /// The layers drawing a shadow's picture: nothing else in these rows stretches an image by its middle.
    func shadowLayers(in cell: UITableViewCell) -> [CALayer] {
        allLayers(of: cell.layer).filter { $0.contents != nil && $0.contentsCenter != CGRect(x: 0, y: 0, width: 1, height: 1) }
    }
    
    /// A layer shadow you could see. Press feedback keeps its own at a clear colour until a bubble's pressed.
    func liveShadows(in layer: CALayer) -> Int {
        allLayers(of: layer).count { $0.shadowOpacity > 0 && ($0.shadowColor?.alpha ?? 0) > 0 }
    }
    
    /// How far a shadow can be seen under the bubble of a row, as things stand on screen, on the white of the window and a bubble.
    func pointsOfShadowUnderTheBubble(of uniqueID: String, afterScreenUpdates: Bool = true) throws -> Int {
        let row = try #require(Array(chat.viewModel.state.timelineState.uniqueIDs.reversed()).firstIndex(of: .init(uniqueID)))
        let cell = try #require(table.cellForRow(at: IndexPath(row: row, section: 0)))
        let shadow = try #require(shadowLayers(in: cell).first)
        let frame = shadow.convert(shadow.bounds, to: window.layer)
        // The table is flipped, so what's still on its way up has more y in it than its model.
        let onItsWay = (cell.layer.presentation()?.position.y ?? cell.layer.position.y) - cell.layer.position.y
        let bubbleBottom = frame.maxY - ChatShadowTexture.reach - ChatShadowTexture.offset - onItsWay
        
        let (cgImage, data) = try picture(afterScreenUpdates: afterScreenUpdates)
        // Down the bubble's leading padding, which has no text in it, as the row is still moving while this draws.
        let column = Int(frame.minX + ChatShadowTexture.reach + 5)
        return (Int(bubbleBottom) - 20..<Int(bubbleBottom) + 34).count { y in
            data[y * cgImage.bytesPerRow + column * cgImage.bitsPerPixel / 8 + 1] < 253 // Green, wherever the channels are.
        }
    }
    
    /// Whether a point of the window's white has a shadow on it.
    func isShaded(x: CGFloat, y: CGFloat) throws -> Bool {
        let (cgImage, data) = try picture(afterScreenUpdates: true)
        return data[Int(y) * cgImage.bytesPerRow + Int(x) * cgImage.bitsPerPixel / 8 + 1] < 253 // Green, wherever the channels are.
    }
    
    private func picture(afterScreenUpdates: Bool) throws -> (CGImage, Data) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: afterScreenUpdates)
        }
        let cgImage = try #require(image.cgImage)
        return try (cgImage, #require(cgImage.dataProvider?.data as Data?))
    }
    
    private func allLayers(of layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap(allLayers)
    }
    
    private static func button(in object: NSObject) -> NSObject? {
        if object.accessibilityTraits.contains(.button) {
            return object
        }
        let count = object.accessibilityElementCount()
        let elements = count == NSNotFound ? [] : (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
        let views = (object as? UIView)?.subviews ?? []
        return (elements + views).lazy.compactMap(button).first
    }
    
    private static func tableView(in view: UIView) -> UITableView? {
        if let table = view as? UITableView {
            return table
        }
        return view.subviews.lazy.compactMap(tableView).first
    }
}

/// The rows' accessibility tree, on for the whole suite as a row built without it never gets one. The switch is the simulator's own
/// and outlives the run, and a screen's `deinit` proved too late to turn it off, so this does, however the tests end.
nonisolated struct AccessibilityTree: SuiteTrait, TestScoping {
    func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        await Switches.setAutomation(true)
        do {
            try await function()
        } catch {
            await Switches.setAutomation(false)
            throw error
        }
        await Switches.setAutomation(false)
    }
}

/// What a test can't reach from the app's API. `libAccessibility` is the switch AccessibilitySnapshot uses for the same tree.
@MainActor
enum Switches {
    private typealias Setter = @convention(c) (Bool) -> Void
    private static let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW)
    private static let unitTestsFlag = "IS_RUNNING_UNIT_TESTS"
    
    /// These are the simulator's own settings, so they outlive a run and a test can't count on finding them off.
    static func reset() {
        setReduceMotion(false)
        setVoiceOver(false)
    }
    
    static func setAutomation(_ isEnabled: Bool) {
        set("_AXSSetAutomationEnabled", to: isEnabled)
    }
    
    static func setReduceMotion(_ isEnabled: Bool) {
        set("_AXSSetReduceMotionEnabled", to: isEnabled)
    }
    
    static func setVoiceOver(_ isEnabled: Bool) {
        set("_AXSVoiceOverTouchSetEnabled", to: isEnabled)
    }
    
    /// `Animation.disabledDuringTests()` reads this each time, so taking it away gives a test what a person sees.
    static func setRealAnimations(_ isEnabled: Bool) {
        if isEnabled {
            unsetenv(unitTestsFlag)
        } else {
            setenv(unitTestsFlag, "1", 1)
        }
    }
    
    private static func set(_ name: String, to isEnabled: Bool) {
        guard let symbol = dlsym(library, name) else {
            Issue.record("No \(name)")
            return
        }
        unsafeBitCast(symbol, to: Setter.self)(isEnabled)
    }
}
