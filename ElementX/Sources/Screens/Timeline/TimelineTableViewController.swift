//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import MatrixRustSDK
import OrderedCollections
import SwiftUI

/// A table view cell that displays a timeline item in a room. The cell is intended
/// to be configured to display a SwiftUI view and not use any UIKit.
class TimelineItemCell: UITableViewCell {
    static let reuseIdentifier = "TimelineItemCell"
    
    var item: RoomTimelineItemViewState?
    
    // AGENT-PLATFORM (Brief 0083, question 359): a bubble's shadow falls past its cell, over the row beside it.
    override class var layerClass: AnyClass {
        UnclippedLayer.self
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): a newer row lies on an older one, so a shadow never lands on the bubble under it.
    // A table stacks its cells in no order of its own. It moves them only through here, those on their way off screen too, and
    // it's flipped, so the newer row is the one with the smaller y. Inside an update's animation block this would animate too.
    override var frame: CGRect {
        didSet {
            UIView.performWithoutAnimation { layer.zPosition = -frame.minY }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): the table animates a row changing size, sliding the rows around it, and most changes
    // come from the network: a quote loading, someone's reaction. Only a row just touched goes there smoothly, and never under Reduce Motion.
    override func invalidateIntrinsicContentSize() {
        let isTouched = (superview as? TimelineTableView)?.rowMotion?.isAnimated == true
        if !UIAccessibility.isReduceMotionEnabled, isTouched {
            super.invalidateIntrinsicContentSize()
        } else {
            UIView.performWithoutAnimation { super.invalidateIntrinsicContentSize() }
        }
    }
    
    override func prepareForReuse() {
        item = nil
        contentView.alpha = 1 // AGENT-PLATFORM (Brief 0083, question 359)
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): for the length of an animated update, a row arriving or changing height, the table
    /// clips every cell to its bounds, which took every shadow but a sliver off the screen. It writes to the layer, not `clipsToBounds`.
    private final nonisolated class UnclippedLayer: CALayer {
        override var masksToBounds: Bool {
            get { false }
            set { }
        }
    }
}

/// AGENT-PLATFORM (Brief 0083, question 359): the table, which sees a touch on a row before any gesture does.
final class TimelineTableView: UITableView {
    var rowMotion: TimelineRowMotion?
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        rowMotion?.noteTouch()
        return super.hitTest(point, with: event)
    }
}

/// A table view controller that displays the timeline of a room.
///
/// This class subclasses `UIViewController` as `UITableViewController` adds some
/// extra keyboard handling magic that wasn't playing well with SwiftUI (as of iOS 16.1).
/// Also this TableViewController uses a **flipped tableview**
class TimelineTableViewController: UIViewController {
    private let coordinator: TimelineViewRepresentable.Coordinator
    private let tableView = TimelineTableView(frame: .zero, style: .plain)
    /// Holds the table so the system's scroll edge effect has an unflipped scroll view to work on.
    private let edgeEffectView = UIScrollView() // AGENT-PLATFORM (Brief 0083, decision 346)
    
    /// AGENT-PLATFORM (Brief 0083, question 359): the build of the rows this table has, from `TimelineState.buildID`.
    var timelineBuildID: Int?
    
    var timelineItemsDictionary = OrderedDictionary<TimelineItemIdentifier.UniqueID, RoomTimelineItemViewState>() {
        didSet {
            // AGENT-PLATFORM (Brief 0083, question 359): the same rows redraw by themselves.
            guard timelineItemsDictionary.keys != oldValue.keys else { return }
            
            guard canApplySnapshot else {
                hasPendingItems = true
                return
            }
            
            applySnapshot()
            
            sendLastVisibleItemReadReceipt()
        }
    }
    
    /// Whether or not it is safe to update the data source with the latest items.
    private var canApplySnapshot: Bool {
        if isLive {
            // Backward pagination jumps if items are inserted whilst actively dragging.
            !isDraggingScrollView
        } else {
            // Forward pagination breaks inertial scrolling when fixing the offset.
            !scrollViewIsScrolling
        }
    }
    
    /// There are pending items in `timelineItemsDictionary` that haven't been applied to the data source.
    private var hasPendingItems = false
    
    /// The scroll view is scrolling either directly with a drag or indirectly with inertia.
    private var scrollViewIsScrolling = false {
        didSet {
            if !scrollViewIsScrolling, hasPendingItems, !isLive {
                hasPendingItems = false
                applySnapshot()
            }
        }
    }
    
    /// The scroll view is being dragged by the user (doesn't include scrolling with inertia)
    private var isDraggingScrollView = false {
        didSet {
            if !isDraggingScrollView, hasPendingItems, isLive {
                hasPendingItems = false
                applySnapshot()
            }
        }
    }
    
    /// Whether or not the current timeline is live or built around an event ID.
    var isLive = true {
        didSet {
            // Update isScrolledToBottom when switching back to a live timeline.
            if isLive {
                scrollViewDidScroll(tableView)
            }
        }
    }
    
    /// The state of pagination (in both directions) of the current timeline.
    var paginationState: TimelinePaginationState = .initial {
        didSet {
            // Paginate again if the threshold hasn't been satisfied.
            paginatePublisher.send(())
        }
    }
    
    /// Whether the table view is about to load items from a new timeline or not.
    var isSwitchingTimelines = false
    
    /// The focussed event if navigating to an event permalink within the room.
    var focussedEvent: TimelineState.FocussedEvent? {
        didSet {
            guard let focussedEvent, focussedEvent.appearance != .hasAppeared else { return }
            heldOpeningRowID = nil // AGENT-PLATFORM (Brief 0083, question 363)
            scrollToItem(eventID: focussedEvent.eventID, animated: focussedEvent.appearance == .animated)
        }
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 363): where the room's live timeline opens.
    var opening = TimelineState.Opening.settled {
        didSet {
            // On its way off screen, as it was.
            guard opening != .abandoned else { return }
            
            tableView.isHidden = opening == .loadingRows
            // The read receipts wait for this, as what's on screen until now says nothing of what you've seen.
            if opening == .settled {
                settledOpeningRowID = nil
                sendLastVisibleItemReadReceipt()
            }
        }
    }
    
    /// The row being settled on, so that a request is settled once however many updates it takes to come back.
    private var settledOpeningRowID: TimelineItemIdentifier.UniqueID?
    /// The row the chat opened at, held under the header until the person moves, as the bars' heights can come after the rows.
    private var heldOpeningRowID: TimelineItemIdentifier.UniqueID?
    
    var hideTimelineMedia = false {
        didSet {
            guard let snapshot = dataSource?.snapshot() else { return }
            dataSource?.applySnapshotUsingReloadData(snapshot)
        }
    }
    
    @Binding private var isScrolledToBottom: Bool
    @Binding private var isReadMarkerVisible: Bool
    @Binding private var hasNewMessagesAtBottom: Bool
    @Binding private var floatingDate: Date?
    
    /// The unique ID of the read marker (NEW banner) currently in the timeline, if any.
    /// Updated by `TimelineViewRepresentable.updateUIViewController` whenever it changes.
    var readMarkerUniqueID: TimelineItemIdentifier.UniqueID?
    
    /// When the floating date badge goes, which each tick of a scroll moves on.
    private var floatingDateHideDate: ContinuousClock.Instant? // AGENT-PLATFORM (Brief 0083, question 359)
    /// Whether the scroll's bindings are to be written on the next turn (`scheduleScrollBindingsUpdate`).
    private var isScrollBindingsUpdateScheduled = false // AGENT-PLATFORM (Brief 0083, question 359)
    /// Whether a tick away from the end asked for the floating date, which that write then reads.
    private var isFloatingDateUpdateDue = false // AGENT-PLATFORM (Brief 0083, question 359)
    
    private var timelineItemsIDs: [TimelineItemIdentifier.UniqueID] {
        timelineItemsDictionary.keys.elements.reversed()
    }
    
    private typealias Snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineItemIdentifier.UniqueID>
    
    /// The table's diffable data source.
    private var dataSource: UITableViewDiffableDataSource<TimelineSection, TimelineItemIdentifier.UniqueID>?
    private var cancellables = Set<AnyCancellable>()
    
    /// A publisher used to throttle back pagination requests.
    ///
    /// Our view actions get wrapped in a `Task` so it is possible that a second call in
    /// quick succession can execute before ``paginationState`` acknowledges that
    /// pagination is in progress.
    private let paginatePublisher = PassthroughSubject<Void, Never>()
    
    /// A value to determine the scroll velocity threshold to detect a change in direction of the scroll view
    private let scrollVelocityThreshold: CGFloat = 50.0
    /// A publisher used to throttle scroll direction changes
    private let scrollDirectionPublisher = PassthroughSubject<ScrollDirection, Never>()
    /// Whether or not the view has been shown on screen yet.
    private var hasAppearedOnce = false
    
    init(coordinator: TimelineViewRepresentable.Coordinator,
         isScrolledToBottom: Binding<Bool>,
         isReadMarkerVisible: Binding<Bool>,
         hasNewMessagesAtBottom: Binding<Bool>,
         floatingDate: Binding<Date?>,
         scrollToBottomPublisher: PassthroughSubject<Void, Never>,
         scrollToFirstItemForDatePublisher: PassthroughSubject<Void, Never>,
         scrollToReadMarkerPublisher: PassthroughSubject<TimelineItemIdentifier.UniqueID, Never>) {
        self.coordinator = coordinator
        _isScrolledToBottom = isScrolledToBottom
        _isReadMarkerVisible = isReadMarkerVisible
        _hasNewMessagesAtBottom = hasNewMessagesAtBottom
        _floatingDate = floatingDate
        
        super.init(nibName: nil, bundle: nil)
        
        tableView.rowMotion = coordinator.context.viewState.rowMotion
        tableView.register(TimelineItemCell.self, forCellReuseIdentifier: TimelineItemCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .onDrag
        // AGENT-PLATFORM (Brief 0083, question 359): the operator's call, no scroll bar over the chat.
        tableView.showsVerticalScrollIndicator = false
        tableView.backgroundColor = .compound.bgCanvasDefault
        
        // The tableview is flipped to display the newest items at the bottom.
        tableView.transform = CGAffineTransform(scaleX: 1, y: -1)
        // AGENT-PLATFORM (Brief 0083, decision 334): the insets come from the view's safe area, flipped
        // (`updateContentInsets`), so the newest message clears the composer's bar while older ones scroll under it.
        // Not `.never`: the table must take up the safe area itself, or each cell overlapping it is told about it and
        // its hosted row grows by that much, so rows change height as they scroll.
        tableView.contentInsetAdjustmentBehavior = .always
        configureEdgeEffect()
        
        // Prevents XCUITest from invoking the diffable dataSource's cellProvider
        // for each possible cell, causing layout issues
        tableView.accessibilityElementsHidden = ProcessInfo.shouldDisableTimelineAccessibility
        
        scrollToBottomPublisher
            .sink { [weak self] _ in
                self?.scrollToNewestItem(animated: true)
            }
            .store(in: &cancellables)
        
        scrollToFirstItemForDatePublisher
            .sink { [weak self] _ in
                self?.scrollToFirstItemForCurrentDate()
            }
            .store(in: &cancellables)
        
        scrollToReadMarkerPublisher
            .sink { [weak self] uniqueID in
                self?.scrollToItem(uniqueID: uniqueID, animated: true)
            }
            .store(in: &cancellables)
        
        paginatePublisher
            .collect(.byTime(DispatchQueue.main, 0.1))
            .sink { [weak self] _ in
                self?.paginateIfNeeded()
            }
            .store(in: &cancellables)
        
        scrollDirectionPublisher
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .removeDuplicates()
            .sink { direction in
                coordinator.send(viewAction: .hasScrolled(direction: direction))
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.sendLastVisibleItemReadReceipt()
            }
            .store(in: &cancellables)
        
        configureDataSource()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available.")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sendLastVisibleItemReadReceipt()
        
        guard !hasAppearedOnce else { return }
        // AGENT-PLATFORM (1.0.2): before Liquid Glass the table stops above the composer, so its safe area may never
        // change and nothing else would set the inset that holds the composer's clearance.
        updateContentInsets()
        tableView.contentOffset.y = bottomOffset - 1 // AGENT-PLATFORM (Brief 0083): from the inset
        hasAppearedOnce = true
        paginatePublisher.send()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        settleOpeningIfNeeded()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        guard tableView.frame.size != view.frame.size else {
            return
        }
        
        edgeEffectView.frame = CGRect(origin: .zero, size: view.frame.size)
        edgeEffectView.contentSize = view.frame.size
        tableView.frame = edgeEffectView.bounds
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 334): on iOS 26+ the timeline runs under the glass composer, which is the
    // bottom of this view's safe area. The table is flipped, so the safe area's bottom is its top inset; a timeline at
    // its newest message stays there when the composer grows or the keyboard comes up.
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateContentInsets()
    }
    
    /// Whether the room's background shows through the table (question 357). The rows take their surfaces from it.
    var isOnChatBackground = false {
        didSet {
            tableView.backgroundColor = isOnChatBackground ? .clear : .compound.bgCanvasDefault
            tableView.reloadData()
        }
    }
    
    /// The height of the composer's bar the table runs under (iOS 26+), which its safe area doesn't include.
    var composerBarHeight: CGFloat = 0 {
        didSet { updateContentInsets() }
    }
    
    /// The height of the block floating under the room's header, which the oldest message clears.
    var headerBlockHeight: CGFloat = 0 { // AGENT-PLATFORM (Brief 0083, decision 345)
        didSet { updateContentInsets() }
    }
    
    private var composerClearance: CGFloat {
        Self.composerClearance(supportsGlass: Compound.supportsGlass,
                               composerBarHeight: composerBarHeight,
                               safeAreaBottom: view.safeAreaInsets.bottom)
    }

    /// How far the newest message stays above the composer's bar.
    ///
    /// With Liquid Glass it clears the system's soft edge effect (question 357). The effect runs on past the bar, and
    /// furthest with the keyboard up, where the bar is short and has no home indicator under it: it blurred the newest
    /// message up to 33 pt above the bar. Measured on iOS 27, at one line.
    ///
    /// AGENT-PLATFORM (1.0.2, operator 2026-11-15): before Liquid Glass the composer is an inset on an opaque bar and the
    /// table stops above it, so the newest message sat 2 pt over the bar, 11 pt from the field. It keeps the 12 pt
    /// Liquid Glass keeps at rest, 23 pt from the field as on iOS 26. There's no edge effect to clear, so the keyboard
    /// doesn't change it.
    nonisolated static func composerClearance(supportsGlass: Bool, composerBarHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        guard supportsGlass else { return 12 }
        guard composerBarHeight > 0 else { return 0 }
        return safeAreaBottom > 0 ? 12 : 32
    }
    
    /// The content offset at the newest message: the top inset, as the table is flipped.
    private var bottomOffset: CGFloat = 0
    
    /// Whether `offset` is at the newest message. The table snaps its offset to device pixels and `bottomOffset` needn't
    /// be on one, as the "Not encrypted" line gives the bar a fractional height: at rest it stops up to half a pixel short.
    nonisolated static func isAtNewestItem(offset: CGFloat, bottomOffset: CGFloat, displayScale: CGFloat) -> Bool {
        offset < bottomOffset + 1 / max(displayScale, 1)
    }
    
    /// Whether the table has come to the newest edge and should step back off it, so the status bar tap still works.
    /// Never under a finger: a slow drag away from the newest message moves through this band, and each step would be undone.
    nonisolated static func shouldStepOffNewestEdge(offset: CGFloat, bottomOffset: CGFloat, displayScale: CGFloat, isTracking: Bool) -> Bool {
        !isTracking
            && isAtNewestItem(offset: offset, bottomOffset: bottomOffset, displayScale: displayScale)
            && offset > bottomOffset - 1 / max(displayScale, 1)
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 364): whether a row has come out from under the composer's bar, the visible rows
    /// otherwise counting one you can't read. The table is flipped, so `rowMinY` is the row's bottom edge on screen.
    nonisolated static func isClearOfComposer(rowMinY: CGFloat, offset: CGFloat, bottomOffset: CGFloat, displayScale: CGFloat) -> Bool {
        rowMinY >= offset - bottomOffset - 1 / max(displayScale, 1)
    }
    
    private var isAtNewestItem: Bool {
        Self.isAtNewestItem(offset: tableView.contentOffset.y, bottomOffset: bottomOffset, displayScale: view.traitCollection.displayScale)
    }
    
    private func updateContentInsets() {
        let safeArea = view.safeAreaInsets
        let top = safeArea.bottom + composerBarHeight + composerClearance
        let bottom = safeArea.top + headerBlockHeight
        // The table adds its safe area to these without flipping it, so they take it off again.
        let insets = UIEdgeInsets(top: top - safeArea.top, left: 0, bottom: bottom - safeArea.bottom, right: 0)
        guard tableView.contentInset != insets || bottomOffset != -top else { return }
        
        let wasAtNewestItem = isAtNewestItem
        bottomOffset = -top
        tableView.contentInset = insets
        if wasAtNewestItem {
            tableView.contentOffset.y = bottomOffset - 1
        } else if let heldOpeningRowID, let indexPath = dataSource?.indexPath(for: heldOpeningRowID) {
            scrollToOpeningRowTop(at: indexPath)
        }
        // The end can come to a table that doesn't move: a bar going down by as much as you'd scrolled up.
        scheduleScrollBindingsUpdate()
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 346): the transform inverts the system's scroll edge effect on the table, so
    // a bar's hard effect blurs everything but the edge. A scroll view that never scrolls, around the table, isn't flipped:
    // its own effect blurs the table under the header and the composer, each bar setting how far.
    private func configureEdgeEffect() {
        edgeEffectView.isScrollEnabled = false
        edgeEffectView.scrollsToTop = false // Two scroll views on screen would disable the status bar's tap.
        edgeEffectView.contentInsetAdjustmentBehavior = .never // The table takes up the safe area (`updateContentInsets`).
        if #available(iOS 26, *) {
            tableView.topEdgeEffect.isHidden = true
            tableView.bottomEdgeEffect.isHidden = true
            edgeEffectView.topEdgeEffect.style = .soft
            edgeEffectView.bottomEdgeEffect.style = .soft
        }
        edgeEffectView.addSubview(tableView)
        view.addSubview(edgeEffectView)
    }
    
    /// Configures a diffable data source for the timeline's table view.
    private func configureDataSource() {
        dataSource = .init(tableView: tableView) { [weak self] tableView, indexPath, id in
            let cell = tableView.dequeueReusableCell(withIdentifier: TimelineItemCell.reuseIdentifier, for: indexPath)
            guard let self, let cell = cell as? TimelineItemCell else { return cell }
            
            let viewState = timelineItemsDictionary[id]
            cell.item = viewState
            guard let viewState else {
                return cell
            }
            
            cell.contentConfiguration = UIHostingConfiguration { [coordinator, hideTimelineMedia, isOnChatBackground] in
                RoomTimelineItemView(viewState: viewState)
                    .id(id)
                    // AGENT-PLATFORM (Brief 0083, question 359): a row's content can be taller than its cell for a moment, and centred
                    // it rose over the older row. From the top it stays in its own row, and passes under the newer one. Without
                    // `minHeight` the frame grows to its content, which the cell then centres all the same.
                    .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.timelineContext, coordinator.context)
                    .environment(\.timelineRowMotion, coordinator.context.viewState.rowMotion)
                    .environment(\.shouldAutomaticallyLoadImages, !hideTimelineMedia)
                    .environment(\.isChatBackgroundDrawn, isOnChatBackground)
            }
            .margins(.all, 0) // Margins are handled in the stylers
            .minSize(height: 1)
            .background(Color.clear)
            
            // Flipping the cell can create some issues with cell resizing, so flip the content View
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
            return cell
        }
        
        // We only animate when there's a new last message, so its safe
        // to animate from the bottom (which is the top as we're flipped).
        dataSource?.defaultRowAnimation = (UIAccessibility.isReduceMotionEnabled ? .none : .top)
        tableView.delegate = self
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityReduceMotionDidChange),
                                               name: UIAccessibility.reduceMotionStatusDidChangeNotification,
                                               object: nil)
    }
    
    @objc private func accessibilityReduceMotionDidChange() {
        dataSource?.defaultRowAnimation = (UIAccessibility.isReduceMotionEnabled ? .none : .top)
    }
    
    /// Updates the table view with the latest items from the ``timelineItems`` array. After
    /// updating the data, the table will be scrolled to the bottom if it was visible otherwise
    /// the scroll position will be updated to maintain the position of the last visible item.
    private func applySnapshot() {
        guard let dataSource else { return }
        
        // AGENT-PLATFORM (Brief 0083, question 359)
        let signpost = TimelineSignposts.beginInterval("Apply snapshot", count: timelineItemsDictionary.count)
        defer { TimelineSignposts.endInterval("Apply snapshot", signpost) }
        
        var snapshot = Snapshot()
        snapshot.appendSections([.main])
        snapshot.appendItems(timelineItemsIDs)
        
        let currentSnapshot = dataSource.snapshot()
        
        // We only animate when new items come at the end of a live timeline, ignoring transitions through empty.
        let newestItemIdentifier = snapshot.mainItemIdentifiers.first
        let currentNewestItemIdentifier = currentSnapshot.mainItemIdentifiers.first
        let newestItemIDChanged = snapshot.numberOfMainItems > 0 && currentSnapshot.numberOfMainItems > 0 && newestItemIdentifier != currentNewestItemIdentifier
        let animated = isLive && !isSwitchingTimelines && newestItemIDChanged
        
        let layout: Layout? = if !isLive, newestItemIDChanged {
            snapshotLayout()
        } else {
            nil
        }
        
        if animated {
            applyAnimated(snapshot, from: currentSnapshot)
        } else {
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        
        if let focussedEvent, focussedEvent.appearance != .hasAppeared {
            scrollToItem(eventID: focussedEvent.eventID, animated: focussedEvent.appearance == .animated)
        } else if let layout {
            restoreLayout(layout)
        } else if isSwitchingTimelines {
            scrollToNewestItem(animated: false)
        }
        
        settleOpeningIfNeeded()
        
        if isSwitchingTimelines {
            coordinator.send(viewAction: .hasSwitchedTimeline)
        }
        
        // Re-evaluate after the snapshot has been applied so the new layout is reflected.
        DispatchQueue.main.async { [weak self] in
            self?.updateReadMarkerVisibility()
            
            // Make sure we paginate with the final timeline geometry
            self?.paginatePublisher.send(())
        }
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359 item 17): rows arriving at the newest end slide in, and nothing else slides.
    private func applyAnimated(_ snapshot: Snapshot, from currentSnapshot: Snapshot) {
        guard let dataSource else { return }
        
        let steps = TimelineSnapshotSteps(current: currentSnapshot.mainItemIdentifiers, new: snapshot.mainItemIdentifiers) { uniqueID in
            if case .virtual = timelineItemsDictionary[uniqueID]?.identifier { true } else { false }
        }
        
        let slide = dataSource.defaultRowAnimation
        if slide != .none {
            dataSource.defaultRowAnimation = .fade
            fadeOutRows(steps.leaving)
        }
        for rows in steps.inPlace {
            var step = Snapshot()
            step.appendSections([.main])
            step.appendItems(rows)
            dataSource.apply(step, animatingDifferences: true)
        }
        dataSource.defaultRowAnimation = slide
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    /// A row on its way out goes quicker than the table closes the gap, so nothing is seen to cross it.
    private func fadeOutRows(_ uniqueIDs: Set<TimelineItemIdentifier.UniqueID>) {
        guard !uniqueIDs.isEmpty else { return }
        
        let cells = tableView.visibleCells.compactMap { $0 as? TimelineItemCell }.filter { cell in
            cell.item.map { uniqueIDs.contains($0.id) } ?? false
        }
        UIView.animate(withDuration: 0.1) {
            cells.forEach { $0.contentView.alpha = 0 }
        }
    }
    
    /// Settles the chat where it opens, in the same pass as the rows so that no frame shows anywhere else. Only once the
    /// table has its size and has the rows: until then its layout says nothing.
    func settleOpeningIfNeeded() {
        guard case .atRow(let uniqueID) = opening, uniqueID != settledOpeningRowID,
              hasAppearedOnce, !tableView.bounds.isEmpty, !hasPendingItems else {
            return
        }
        
        settledOpeningRowID = uniqueID
        let isAwayFromEnd = dataSource?.indexPath(for: uniqueID).map(scrollToOpeningRow) ?? false
        coordinator.send(viewAction: .hasSettledOpening(isAwayFromEnd: isAwayFromEnd))
    }
    
    /// Goes to the row unless it's on screen from the end, and says whether that took it away from there.
    private func scrollToOpeningRow(at indexPath: IndexPath) -> Bool {
        tableView.contentOffset.y = bottomOffset - 1
        tableView.layoutIfNeeded()
        
        guard !isOnScreen(indexPath) else { return false }
        
        heldOpeningRowID = dataSource?.itemIdentifier(for: indexPath)
        scrollToOpeningRowTop(at: indexPath)
        // A row cut by less than the step off the end is shown by a scroll that stays at the end, with nothing below it.
        return !isAtNewestItem
    }
    
    private func scrollToOpeningRowTop(at indexPath: IndexPath) {
        // Rows have estimated heights until they're laid out, so the first pass only gets near.
        for _ in 0..<2 {
            // The table view is flipped, so .bottom aligns the cell to the visual top.
            tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
            tableView.layoutIfNeeded()
        }
    }
    
    /// Whether the whole row shows between the composer's bar and the room's header.
    private func isOnScreen(_ indexPath: IndexPath) -> Bool {
        guard tableView.indexPathsForVisibleRows?.contains(indexPath) == true else { return false }
        return tableView.rectForRow(at: indexPath).maxY <= tableView.contentOffset.y + tableView.bounds.height - tableView.adjustedContentInset.bottom
    }
    
    private var hasRows: Bool {
        tableView.numberOfSections > 0 && tableView.numberOfRows(inSection: 0) > 0
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): goes to the row, cutting most of the way if it's far.
    private func scrollToRow(at indexPath: IndexPath, at position: UITableView.ScrollPosition, animated: Bool) {
        if animated, let visibleRows = tableView.indexPathsForVisibleRows?.map(\.row), let first = visibleRows.min(), let last = visibleRows.max(),
           let cutRow = TimelineJump.cutRow(from: first...last, to: indexPath.row) {
            tableView.scrollToRow(at: IndexPath(row: cutRow, section: indexPath.section), at: position, animated: false)
        }
        tableView.scrollToRow(at: indexPath, at: position, animated: animated)
    }
    
    /// Scrolls to the newest item in the timeline.
    private func scrollToNewestItem(animated: Bool) {
        // The data source can lag behind timelineItemsIDs, so scroll against the table's actual contents.
        guard hasRows else { return }
        scrollToRow(at: IndexPath(item: 0, section: 0), at: .top, animated: animated)
        scrollDirectionPublisher.send(.bottom)
    }
    
    /// Scrolls to the oldest item in the timeline.
    private func scrollToOldestItem(animated: Bool) {
        guard hasRows else { return }
        scrollToRow(at: IndexPath(item: tableView.numberOfRows(inSection: 0) - 1, section: 0), at: .bottom, animated: animated)
        scrollDirectionPublisher.send(.top)
    }
    
    /// Scrolls to the item with the corresponding unique ID. Used to jump to virtual items like
    /// the read marker that have no event ID. Positions the item near the middle of the viewport
    /// so the user can see what's above and below the marker.
    private func scrollToItem(uniqueID: TimelineItemIdentifier.UniqueID, animated: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let indexPath = dataSource?.indexPath(for: uniqueID) else { return }
            scrollToRow(at: indexPath, at: .middle, animated: animated)
        }
    }
    
    /// Scrolls to the item with the corresponding event ID if loaded in the timeline.
    private func scrollToItem(eventID: String, animated: Bool) {
        DispatchQueue.main.async { [weak self] in // Fixes #2805
            guard let self else { return }
            if let kvPair = timelineItemsDictionary.first(where: { $0.value.identifier.eventID == eventID }),
               let indexPath = dataSource?.indexPath(for: kvPair.key) {
                // Scrolling to the middle created a small bump in the timeline
                // Using top, which is bottom in the reversed timeline helps with rendering
                // in full long messages and images
                scrollToRow(at: indexPath, at: .top, animated: animated)
                coordinator.send(viewAction: .scrolledToFocussedItem)
                // Ensure VoiceOver focus happens after the scroll animation (if any)
                DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.5 : 0.0)) {
                    if let cell = self.tableView.cellForRow(at: indexPath) {
                        UIAccessibility.post(notification: .layoutChanged, argument: cell)
                    }
                }
            }
        }
    }
    
    /// Checks whether or not pagination is needed in either direction and requests one if so.
    ///
    /// **Note:** Prefer not to call this directly, instead using ``paginatePublisher`` to throttle requests.
    private func paginateIfNeeded() {
        guard !hasPendingItems else { return }
        
        if paginationState.backward == .idle,
           tableView.contentOffset.y > tableView.contentSize.height - tableView.visibleSize.height * 2.0 {
            coordinator.send(viewAction: .paginateBackwards)
        }
        if !isLive,
           paginationState.forward == .idle,
           tableView.contentOffset.y < tableView.visibleSize.height {
            coordinator.send(viewAction: .paginateForwards)
        }
    }
    
    /// Updates the `isReadMarkerVisible` binding based on whether the read marker is currently
    /// on screen or below the viewport (already scrolled past).
    ///
    /// In the flipped table view, "above the viewport" means a higher index path. The marker is
    /// considered "visible or below" iff its index path ≤ the maximum visible index path.
    ///
    /// Writes the binding, so never during a view update: it runs on a turn of its own.
    private func updateReadMarkerVisibility() {
        let isVisible: Bool = {
            guard let readMarkerUniqueID,
                  let readMarkerIndexPath = dataSource?.indexPath(for: readMarkerUniqueID),
                  let visibleIndexPaths = tableView.indexPathsForVisibleRows,
                  let maxVisibleIndexPath = visibleIndexPaths.max() else {
                return false
            }
            return readMarkerIndexPath <= maxVisibleIndexPath
        }()
        
        if isReadMarkerVisible != isVisible {
            isReadMarkerVisible = isVisible
        }
    }
    
    private func sendLastVisibleItemReadReceipt() {
        // Find the last visible timeline item and send a read receipt for it
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows else {
            return
        }
        
        // These are already in reverse order because the table view is flipped
        for indexPath in visibleIndexPaths {
            // AGENT-PLATFORM (Brief 0083, question 364): what you've seen, so a row you can read and has an event to name.
            guard Self.isClearOfComposer(rowMinY: tableView.rectForRow(at: indexPath).minY,
                                         offset: tableView.contentOffset.y,
                                         bottomOffset: bottomOffset,
                                         displayScale: view.traitCollection.displayScale),
                let visibleItemUniqueID = dataSource?.itemIdentifier(for: indexPath),
                let visibleItemID = timelineItemsDictionary[visibleItemUniqueID]?.newestEventItemID else {
                continue
            }
            
            coordinator.send(viewAction: .sendReadReceiptIfNeeded(visibleItemID))
            return
        }
    }
}

// MARK: - UITableViewDelegate

extension TimelineTableViewController: UITableViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        paginatePublisher.send(())
        
        updateScrollState()
        
        stepOffNewestEdge(scrollView, isTracking: scrollView.isTracking)
        
        let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView.superview).y
        if velocity > scrollVelocityThreshold {
            scrollDirectionPublisher.send(.top)
        } else if velocity < -scrollVelocityThreshold {
            scrollDirectionPublisher.send(.bottom)
        }
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): runs on every tick of a scroll, so the bindings wait for one block a turn.
    private func updateScrollState() {
        // AGENT-PLATFORM (Brief 0083): from the inset. Only your own scroll, a drag and the glide after it, shows the date;
        // the app's scrolls (the opening at "New", the jumps, rows changing size) leave it alone.
        if !isAtNewestItem, scrollViewIsScrolling {
            // The badge stays while the scroll goes on; its day is read with the bindings, so the last tick's day wins.
            scheduleFloatingDateHide()
            isFloatingDateUpdateDue = true
        }
        scheduleScrollBindingsUpdate()
    }
    
    /// Dispatch to fix runtime warning about making changes during a view update. AGENT-PLATFORM (Brief 0083,
    /// question 359): one write for any number of ticks in a turn, read from the table when it runs, as Element does. Read
    /// in the tick, a tick back to the end could be lost behind one away from it, and the jump button stay up at the end.
    private func scheduleScrollBindingsUpdate() {
        guard !isScrollBindingsUpdateScheduled else { return }
        isScrollBindingsUpdateScheduled = true
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isScrollBindingsUpdateScheduled = false
            updateScrollBindings()
        }
    }
    
    private func updateScrollBindings() {
        let isScrolledToBottom = isAtNewestItem // AGENT-PLATFORM (Brief 0083): from the inset
        
        // Only update the binding on changes to avoid needlessly recomputing the hierarchy when scrolling.
        if self.isScrolledToBottom != isScrolledToBottom {
            self.isScrolledToBottom = isScrolledToBottom
        }
        // AGENT-PLATFORM (Brief 0083): at the end, not only on reaching it, as a dot set there points at nothing.
        if isScrolledToBottom, hasNewMessagesAtBottom {
            hasNewMessagesAtBottom = false
        }
        
        if isFloatingDateUpdateDue {
            isFloatingDateUpdateDue = false
            if !isScrolledToBottom {
                updateFloatingDate()
            }
        }
        
        updateReadMarkerVisibility()
    }
    
    /// We never want the table view to be fully at the bottom to allow the status bar tap to work properly
    /// AGENT-PLATFORM (Brief 0083): measured from the inset under the composer.
    private func stepOffNewestEdge(_ scrollView: UIScrollView, isTracking: Bool) {
        if Self.shouldStepOffNewestEdge(offset: scrollView.contentOffset.y,
                                        bottomOffset: bottomOffset,
                                        displayScale: view.traitCollection.displayScale,
                                        isTracking: isTracking) {
            scrollView.contentOffset.y = bottomOffset - 1
        }
    }
    
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        scrollToOldestItem(animated: true)
        return false
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        coordinator.context.viewState.rowMotion.noteDrag()
        heldOpeningRowID = nil
        isDraggingScrollView = true
        scrollViewIsScrolling = true
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        sendLastVisibleItemReadReceipt()
        
        isDraggingScrollView = false
        if !decelerate {
            // Released on the edge: no further scroll event comes, and `isTracking` is still true here.
            stepOffNewestEdge(scrollView, isTracking: false)
            scrollViewIsScrolling = false
            clearFocusIfScrolledAway()
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        sendLastVisibleItemReadReceipt()
        scrollViewIsScrolling = false
        clearFocusIfScrolledAway()
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        heldOpeningRowID = nil
        sendLastVisibleItemReadReceipt()
        clearFocusIfScrolledAway()
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): once a scroll ends with the focussed item off screen, it's done its
    /// job, whether a finger or the jump to the bottom moved it. Checked when a scroll settles rather than when the
    /// cell leaves, as cells also leave on a reload.
    private func clearFocusIfScrolledAway() {
        guard let focussedEvent, focussedEvent.appearance == .hasAppeared,
              let visibleIndexPaths = tableView.indexPathsForVisibleRows, !visibleIndexPaths.isEmpty else {
            return
        }
        let isOnScreen = visibleIndexPaths.contains { indexPath in
            guard let uniqueID = dataSource?.itemIdentifier(for: indexPath) else { return false }
            return timelineItemsDictionary[uniqueID]?.identifier.eventID == focussedEvent.eventID
        }
        if !isOnScreen {
            coordinator.send(viewAction: .scrolledAwayFromFocussedItem)
        }
    }
}

// MARK: - Floating Date Badge

extension TimelineTableViewController {
    private static let floatingDateDuration: Duration = .seconds(2)
    
    /// Computes the timestamp for the topmost visible timeline item
    /// and updates the floating date binding.
    func updateFloatingDate() {
        guard let date = newestVisibleDate() else {
            return
        }
        
        // AGENT-PLATFORM (Brief 0083, question 359): the tick schedules the badge's removal (`updateScrollState`), and this
        // runs with the scroll's bindings, on a turn of its own, reading the rows on screen then.
        
        // Only update when the calendar day changes to avoid needless SwiftUI recomputation.
        if floatingDate.map({ !Calendar.current.isDate($0, inSameDayAs: date) }) ?? true {
            floatingDate = date
        }
    }
    
    /// Schedules the floating date badge to be hidden after a delay.
    func scheduleFloatingDateHide() {
        let isScheduled = floatingDateHideDate != nil
        floatingDateHideDate = .now + Self.floatingDateDuration
        if !isScheduled {
            hideFloatingDateWhenDue()
        }
    }
    
    /// One wait at a time, however often the date moves: it looks again when it's over.
    private func hideFloatingDateWhenDue() {
        guard let floatingDateHideDate else { return }
        
        let wait = ContinuousClock.now.duration(to: floatingDateHideDate)
        guard wait > .zero else {
            self.floatingDateHideDate = nil
            floatingDate = nil
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait.seconds) { [weak self] in
            self?.hideFloatingDateWhenDue()
        }
    }
    
    /// Scrolls to the first (oldest) item on the same calendar day as the current floating date.
    private func scrollToFirstItemForCurrentDate() {
        guard let floatingDate else { return }
        // timelineItemsDictionary is ordered oldest-first; the first match is the earliest item for that day.
        for uniqueID in timelineItemsDictionary.keys {
            if let timestamp = timelineItemsDictionary[uniqueID]?.timestamp,
               Calendar.current.isDate(timestamp, inSameDayAs: floatingDate),
               let indexPath = dataSource?.indexPath(for: uniqueID) {
                // The table view is flipped, so .bottom aligns the cell to the visual top.
                scrollToRow(at: indexPath, at: .bottom, animated: true)
                return
            }
        }
    }
    
    /// Returns the timestamp of the newest visible timeline item.
    ///
    /// The table view is flipped, so the "newest" visible cell on screen is
    /// actually the *last* index path in `indexPathsForVisibleRows`.
    private func newestVisibleDate() -> Date? {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
              !visibleIndexPaths.isEmpty else {
            return nil
        }
        
        // In a flipped table view the last index path is the topmost item on screen.
        let orderedPaths = visibleIndexPaths.reversed()
        
        // Walk from topmost downward and return the timestamp of the first item that has one.
        for indexPath in orderedPaths {
            if let uniqueID = dataSource?.itemIdentifier(for: indexPath),
               let timestamp = timelineItemsDictionary[uniqueID]?.timestamp {
                return timestamp
            }
        }
        
        return nil
    }
}

// MARK: - Layout

extension TimelineTableViewController {
    /// The sections of the table view used in the diffable data source.
    nonisolated enum TimelineSection {
        case main
    }
    
    /// A representation of the table's layout based on a particular item.
    private struct Layout {
        let id: TimelineItemIdentifier
        let frame: CGRect
    }
    
    /// The current layout of the table, based on the newest timeline item.
    private func snapshotLayout() -> Layout? {
        guard let newestItemID = newestVisibleItemID(),
              let newestCellFrame = cellFrame(for: newestItemID.uniqueID) else {
            return nil
        }
        return Layout(id: newestItemID, frame: newestCellFrame)
    }
    
    /// Restores the timeline's layout from an old snapshot.
    private func restoreLayout(_ layout: Layout) {
        if let indexPath = dataSource?.indexPath(for: layout.id.uniqueID) {
            // Scroll the item into view.
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
            
            // Remove any unwanted offset that was added by scrollToRow.
            if let frame = cellFrame(for: layout.id.uniqueID) {
                let deltaY = frame.maxY - layout.frame.maxY
                if deltaY != 0 {
                    tableView.contentOffset.y -= deltaY
                }
            }
        }
    }
    
    /// Returns the frame of the row for a particular timeline item.
    private func cellFrame(for uniqueID: TimelineItemIdentifier.UniqueID) -> CGRect? {
        guard let indexPath = dataSource?.indexPath(for: uniqueID) else { return nil }
        return tableView.convert(tableView.rectForRow(at: indexPath), to: tableView.superview)
    }
    
    /// The item ID of the newest visible item in the timeline.
    private func newestVisibleItemID() -> TimelineItemIdentifier? {
        guard let timelineCell = tableView.visibleCells.first(where: {
            guard let cell = $0 as? TimelineItemCell else { return false }
            return !(cell.item?.type is PaginationIndicatorRoomTimelineItem)
        }) else {
            return nil
        }
        return (timelineCell as? TimelineItemCell)?.item?.identifier
    }
}

private extension NSDiffableDataSourceSnapshot<TimelineTableViewController.TimelineSection, TimelineItemIdentifier.UniqueID> {
    var numberOfMainItems: Int {
        guard sectionIdentifiers.contains(.main) else { return 0 }
        return numberOfItems(inSection: .main)
    }
    
    var mainItemIdentifiers: [TimelineItemIdentifier.UniqueID] {
        guard sectionIdentifiers.contains(.main) else { return [] }
        return itemIdentifiers(inSection: .main)
    }
}
