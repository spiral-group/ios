//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the real timeline in a window, with real rows, for what only it can say.
//

import MatrixRustSDK
@testable import Spiral
import SwiftUI
import Testing

/// A chat on screen, in a window of an iPhone's size.
@MainActor
final class TimelineTestScreen {
    let chat: TimelineTestChat
    let window: UIWindow
    let table: UITableView
    
    var receipts: [String] {
        chat.timelineController.sendReadReceiptForReceivedInvocations.compactMap(\.eventID)
    }
    
    var isDotShowing: Bool {
        chat.viewModel.state.bindings.hasNewMessagesAtBottom
    }
    
    var isAtEnd: Bool {
        chat.viewModel.state.bindings.isScrolledToBottom
    }
    
    init(items: [RoomTimelineItemProtocol],
         unreadMessagesCount: UInt = 0,
         fullyReadEventID: String? = nil,
         focussedEventID: String? = nil,
         isRendered: Bool = false,
         configure: (TimelineTestChat) -> Void = { _ in }) async throws {
        chat = TimelineTestChat(items: items,
                                unreadMessagesCount: unreadMessagesCount,
                                fullyReadEventID: fullyReadEventID,
                                focussedEventID: focussedEventID,
                                isSettled: false)
        configure(chat)
        
        // Only a window in a scene renders: it's what hosted views and animations need.
        if isRendered, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        }
        window.rootViewController = UIHostingController(rootView: TimelineView(timelineContext: chat.viewModel.context))
        window.isHidden = false
        window.layoutIfNeeded()
        table = try #require(Self.tableView(in: window))
        await pump()
    }
    
    deinit {
        // A window in a scene stays there until it's taken out.
        let window = window
        Task { @MainActor in window.isHidden = true }
    }
    
    /// The top of the table in the window, which sits below the status bar.
    var tableTop: CGFloat {
        table.convert(table.bounds, to: window).minY
    }
    
    func tableViewController() throws -> TimelineTableViewController {
        var responder = table.next
        while responder != nil, !(responder is TimelineTableViewController) {
            responder = responder?.next
        }
        return try #require(responder as? TimelineTableViewController)
    }
    
    func deliver(_ items: [RoomTimelineItemProtocol]) async {
        await chat.deliver(items)
        await pump()
    }
    
    func waitForOpening() async throws {
        for _ in 0..<100 where chat.viewModel.state.timelineState.opening != .settled {
            await pump()
        }
        await pump()
        #expect(chat.viewModel.state.timelineState.opening == .settled)
    }
    
    /// The row's frame in the window, if it's on screen.
    func frameOnScreen(of uniqueID: String) -> CGRect? {
        // The table is flipped, so its first row is the newest.
        guard let row = Array(chat.viewModel.state.timelineState.uniqueIDs.reversed()).firstIndex(of: .init(uniqueID)),
              let cell = table.cellForRow(at: IndexPath(row: row, section: 0)) else {
            return nil
        }
        
        let frame = cell.convert(cell.bounds, to: window)
        return frame.intersects(window.bounds) ? frame : nil
    }
    
    /// What the row draws, to tell two of its states apart. Only a screen built with `isRendered` draws.
    func picture(of uniqueID: String) throws -> Data {
        let cell = try #require(table.subviews.compactMap { $0 as? TimelineItemCell }.first { $0.item?.id.value == uniqueID })
        return UIGraphicsImageRenderer(bounds: cell.bounds).pngData { _ in
            cell.drawHierarchy(in: cell.bounds, afterScreenUpdates: true)
        }
    }
    
    func pump() async {
        try? await Task.sleep(for: .milliseconds(50))
    }
    
    /// Which rows' bodies ran during `work`, by unique ID, once the update it caused has landed.
    func bodiesRun(during work: () async -> Void) async -> RowBodies {
        await pump()
        TimelineSignposts.bodyCounts = [:]
        await work()
        await pump()
        await pump()
        return RowBodies(rows: Set((TimelineSignposts.bodyCounts[.row] ?? [:]).keys.map(\.value)),
                         bubbles: Set((TimelineSignposts.bodyCounts[.styler] ?? [:]).keys.map(\.value)))
    }
    
    private static func tableView(in view: UIView) -> UITableView? {
        if let table = view as? UITableView {
            return table
        }
        return view.subviews.lazy.compactMap(tableView).first
    }
}

struct RowBodies: Equatable {
    /// The rows whose `RoomTimelineItemView` ran.
    var rows = Set<String>()
    /// The rows whose bubble ran.
    var bubbles = Set<String>()
    
    var all: Set<String> {
        rows.union(bubbles)
    }
}
