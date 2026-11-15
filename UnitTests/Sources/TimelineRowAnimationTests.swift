//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 items 16 and 17): what moves on screen when rows change, read from the layers
// mid-animation in a real window.
//

import MatrixRustSDK
@testable import Spiral
import SwiftUI
import Testing

@MainActor
struct TimelineRowAnimationTests {
    private static let them = "@alice:spiral.test"
    private static let marker = ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init("marker")))
    
    @Test
    func theNewDividerFadesWhereItIsAsYourMessageArrives() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20) + [Self.marker, row(20)], isRendered: true)
        let before = try #require(screen.frameOnScreen(of: "marker"))
        
        update(screen, to: rows(0..<21) + [row(21, from: RoomMemberProxyMock.mockMe.userID)])
        let frames = await frames(of: "marker", on: screen)
        
        let moves = frames.map { abs($0.y - before.minY) }
        #expect(!frames.isEmpty)
        #expect(moves.allSatisfy { $0 < 1 })
        #expect(frames.last.map { $0.opacity < 0.05 } ?? true)
    }
    
    @Test
    func yourMessageStillSlidesInFromTheEnd() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<20), isRendered: true)
        
        update(screen, to: rows(0..<20) + [row(20, from: RoomMemberProxyMock.mockMe.userID)])
        let frames = await frames(of: "20", on: screen)
        
        let places = Set(frames.map { Int($0.y) })
        #expect(places.count > 2)
    }
    
    @Test
    func aRowGrowsAtOnceWithNobodyTouchingIt() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<30), isRendered: true)
        
        update(screen, to: grown(rows(0..<30), at: 28))
        let frames = await frames(of: "28", on: screen)
        
        #expect(!frames.isEmpty)
        #expect(frames.allSatisfy { !$0.isAnimating })
    }
    
    @Test
    func aRowJustTouchedGrowsSmoothly() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<30), isRendered: true)
        
        _ = screen.table.hitTest(CGPoint(x: 100, y: 100), with: nil)
        update(screen, to: grown(rows(0..<30), at: 28))
        let frames = await frames(of: "28", on: screen)
        
        #expect(frames.contains { $0.isAnimating })
    }
    
    @Test
    func aDragIsNoTouchOnARow() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<30), isRendered: true)
        let controller = try screen.tableViewController()
        
        _ = screen.table.hitTest(CGPoint(x: 100, y: 100), with: nil)
        controller.scrollViewWillBeginDragging(screen.table)
        controller.scrollViewDidEndDragging(screen.table, willDecelerate: false)
        update(screen, to: grown(rows(0..<30), at: 28))
        let frames = await frames(of: "28", on: screen)
        
        #expect(!frames.isEmpty)
        #expect(frames.allSatisfy { !$0.isAnimating })
    }
    
    @Test
    func theRowsBesideANewOneRegroupSmoothly() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<30), isRendered: true)
        let rowMotion = screen.chat.viewModel.state.rowMotion
        #expect(!rowMotion.isAnimated)
        
        update(screen, to: rows(0..<31))
        await screen.pump()
        #expect(rowMotion.isAnimated)
        
        try await Task.sleep(for: .milliseconds(450))
        #expect(!rowMotion.isAnimated)
    }
    
    @Test
    func aRowChangingIsNoArrival() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<30), isRendered: true)
        
        update(screen, to: grown(rows(0..<30), at: 28))
        await screen.pump()
        
        #expect(!screen.chat.viewModel.state.rowMotion.isAnimated)
    }
    
    @Test
    func aRowAnimatesOnlyWhileItsMotionSaysSo() {
        let rowMotion = TimelineRowMotion()
        #expect(rowMotion.animation == nil)
        
        rowMotion.noteTouch()
        #expect(rowMotion.animation != nil)
        
        rowMotion.noteDrag()
        #expect(rowMotion.animation == nil)
    }
    
    @Test
    func anArrivalDoesntCutATouchShort() async throws {
        let rowMotion = TimelineRowMotion()
        
        rowMotion.noteTouch()
        rowMotion.noteArrival()
        try await Task.sleep(for: .milliseconds(450))
        
        #expect(rowMotion.isAnimated)
    }
    
    @Test
    func theJumpToTheNewestPassesFewRows() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<300), isRendered: true)
        screen.table.scrollToRow(at: IndexPath(row: 280, section: 0), at: .middle, animated: false)
        screen.table.layoutIfNeeded()
        await screen.pump()
        
        let bodies = await screen.bodiesRun {
            screen.chat.viewModel.state.timelineState.scrollToBottomPublisher.send()
            try? await Task.sleep(for: .milliseconds(600))
        }
        
        #expect(screen.table.indexPathsForVisibleRows?.contains(IndexPath(row: 0, section: 0)) == true)
        #expect(bodies.rows.count < 40)
    }
    
    @Test
    func theFloatingDateStaysForTwoSecondsAfterTheLastScroll() async throws {
        let screen = try await TimelineTestScreen(items: rows(0..<60), isRendered: true)
        let controller = try screen.tableViewController()
        var floatingDate: Date? { screen.chat.viewModel.state.bindings.floatingDate }
        controller.scrollViewWillBeginDragging(screen.table)
        
        screen.table.contentOffset.y += 600
        controller.scrollViewDidScroll(screen.table)
        await screen.pump()
        #expect(floatingDate != nil)
        
        try await Task.sleep(for: .seconds(1.2))
        screen.table.contentOffset.y += 50
        controller.scrollViewDidScroll(screen.table)
        try await Task.sleep(for: .seconds(1.2))
        #expect(floatingDate != nil)
        
        try await Task.sleep(for: .seconds(1.2))
        #expect(floatingDate == nil)
    }
    
    // MARK: - Helpers
    
    private struct Frame {
        let y: CGFloat
        let opacity: Float
        let isAnimating: Bool
    }
    
    /// A row's place on screen and how much of it shows, for as long as the table's animations last.
    private func frames(of uniqueID: String, on screen: TimelineTestScreen) async -> [Frame] {
        var frames = [Frame]()
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(16))
            guard let cell = screen.table.subviews.compactMap({ $0 as? TimelineItemCell }).first(where: { $0.item?.id.value == uniqueID }) else {
                continue
            }
            let layer = cell.layer.presentation() ?? cell.layer
            let content = cell.contentView.layer.presentation() ?? cell.contentView.layer
            let table = screen.table.layer.presentation() ?? screen.table.layer
            // The table is flipped, so a row's top on screen is its far edge in the table.
            frames.append(Frame(y: screen.tableTop + screen.table.bounds.height - (layer.frame.maxY - table.bounds.minY),
                                opacity: layer.opacity * content.opacity,
                                isAnimating: !(cell.layer.animationKeys() ?? []).isEmpty))
        }
        return frames
    }
    
    private func update(_ screen: TimelineTestScreen, to items: [RoomTimelineItemProtocol]) {
        screen.chat.timelineController.timelineItems = items
        screen.chat.timelineController.callbacks.send(.updatedTimelineItems(timelineItems: items, isSwitchingTimelines: false))
    }
    
    private func rows(_ range: Range<Int>) -> [RoomTimelineItemProtocol] {
        range.map { row($0) }
    }
    
    /// The rows with a quote loaded in one of them.
    private func grown(_ rows: [RoomTimelineItemProtocol], at index: Int) -> [RoomTimelineItemProtocol] {
        var rows = rows
        rows[index] = row(index, replyDetails: .loaded(sender: .init(id: Self.them, displayName: "Alice"),
                                                       eventID: "$quoted",
                                                       eventContent: .message(.text(.init(body: "A quote loaded late")))))
        return rows
    }
    
    private func row(_ index: Int, from sender: String = them, replyDetails: TimelineItemReplyDetails? = nil) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: .event(uniqueID: .init("\(index)"), eventOrTransactionID: .eventID("$\(index)")),
                             timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 600),
                             isOutgoing: sender == RoomMemberProxyMock.mockMe.userID,
                             isEditable: false,
                             canBeRepliedTo: true,
                             sender: .init(id: sender, displayName: sender == Self.them ? "Alice" : "Me"),
                             content: .init(body: "Message \(index)"),
                             properties: .init(replyDetails: replyDetails))
    }
}
