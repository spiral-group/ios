//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 item 16): what the timeline benchmark reads while the real table runs: a frame
// log, the main thread's busy time, the cost of each row kind and how many rows re-render.
// Compiled only with SPIRAL_TIMELINE_BENCH, which Tools/Scripts/run-timeline-bench.sh passes and no project file sets.
//

#if SPIRAL_TIMELINE_BENCH

import SwiftUI

enum TimelineBenchClock {
    /// Nanoseconds of wall time.
    static var wall: UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    /// Nanoseconds of this thread's CPU time. Other work on the Mac slows the wall clock down and leaves this one alone,
    /// which is what makes two runs comparable.
    static var cpu: UInt64 {
        clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }
}

/// How long the main thread works, from the run loop waking until it goes back to sleep. Core Animation commits on the way
/// to sleep, so this holds the layout and the commit of a frame as well.
final class TimelineBenchRunLoopMeter {
    private(set) var busyWall: UInt64 = 0
    private(set) var busyCPU: UInt64 = 0
    private(set) var turns = 0
    /// Runs just before the main thread sleeps, once Core Animation has committed.
    var onSleep: (() -> Void)?

    private var wakeWall = TimelineBenchClock.wall
    private var wakeCPU = TimelineBenchClock.cpu
    private var observers: [CFRunLoopObserver] = []

    func start() {
        let wake = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { [unowned self] _, _ in
            wakeWall = TimelineBenchClock.wall
            wakeCPU = TimelineBenchClock.cpu
        }
        let sleep = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [unowned self] _, _ in
            let wall = TimelineBenchClock.wall
            let cpu = TimelineBenchClock.cpu
            busyWall += wall - wakeWall
            busyCPU += cpu - wakeCPU
            wakeWall = wall
            wakeCPU = cpu
            turns += 1
            onSleep?()
        }
        guard let wake, let sleep else { fatalError("No run loop observer") }
        CFRunLoopAddObserver(CFRunLoopGetMain(), wake, .commonModes)
        CFRunLoopAddObserver(CFRunLoopGetMain(), sleep, .commonModes)
        observers = [wake, sleep]
    }
}

/// One tick of the display link: what was on screen, and the main thread's work since the tick before.
struct TimelineBenchFrame {
    let timestamp: CFTimeInterval
    let period: CFTimeInterval
    let busyWall: UInt64
    let busyCPU: UInt64
    /// How far a row on screen moved from where the scroll put it, in points.
    var jump: CGFloat = 0
}

/// A `CADisplayLink` on the main run loop, which is the thread a hitch comes from: a frame the app hands in late shows here
/// as a gap between ticks. What the render server does after the commit doesn't.
final class TimelineBenchFrameLog: NSObject {
    private let meter: TimelineBenchRunLoopMeter
    private var link: CADisplayLink?
    private var lastBusyWall: UInt64 = 0
    private var lastBusyCPU: UInt64 = 0
    private var isRecording = false

    private(set) var frames: [TimelineBenchFrame] = []
    /// Runs on each tick, before the frame's work.
    var onTick: ((CADisplayLink) -> CGFloat)?

    init(meter: TimelineBenchRunLoopMeter) {
        self.meter = meter
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func beginRecording() {
        frames.removeAll(keepingCapacity: true)
        lastBusyWall = meter.busyWall
        lastBusyCPU = meter.busyCPU
        isRecording = true
    }

    @discardableResult
    func endRecording() -> [TimelineBenchFrame] {
        isRecording = false
        return frames
    }

    @objc private func tick(_ link: CADisplayLink) {
        let jump = onTick?(link) ?? 0
        guard isRecording else { return }
        frames.append(TimelineBenchFrame(timestamp: link.timestamp,
                                         period: link.targetTimestamp - link.timestamp,
                                         busyWall: meter.busyWall - lastBusyWall,
                                         busyCPU: meter.busyCPU - lastBusyCPU,
                                         jump: jump))
        lastBusyWall = meter.busyWall
        lastBusyCPU = meter.busyCPU
    }
}

// MARK: - Rows

/// Samples of one row kind's cell work, in nanoseconds.
struct TimelineBenchRowCost {
    var configureWall: [UInt64] = []
    var configureCPU: [UInt64] = []
    var sizeWall: [UInt64] = []
    var sizeCPU: [UInt64] = []
    /// The first sizing after a configuration, as the table sizes every row twice.
    var firstSizeCPU: [UInt64] = []
    var layoutWall: [UInt64] = []
    var layoutCPU: [UInt64] = []
}

@MainActor
final class TimelineBenchProbe {
    static let shared = TimelineBenchProbe()

    /// A row's kind in the fixture, by its unique ID. New rows that aren't in it are "incoming".
    var kinds: [String: String] = [:]
    private(set) var rowCosts: [String: TimelineBenchRowCost] = [:]

    private(set) var rowBodies = 0
    private(set) var stylerBodies = 0
    private(set) var rowBodyIDs = Set<String>()
    private(set) var stylerBodyIDs = Set<String>()
    private(set) var configurations = 0
    private(set) var configurationUpdates = 0
    private(set) var sizings = 0
    private(set) var nestedSizings = 0
    fileprivate var sizingDepth = 0
    private var isNextSizingFirst = false
    private(set) var cellIDs = Set<ObjectIdentifier>()
    /// What each post's row watches, which says when its app has drawn.
    private(set) var postSlots: [String: SpiralAppSlot] = [:]
    /// Web views made and apps mounted so far, which a scroll shouldn't add to.
    var webViewsMade = 0
    var mounts = 0

    func resetCounts() {
        rowBodies = 0
        stylerBodies = 0
        rowBodyIDs.removeAll(keepingCapacity: true)
        stylerBodyIDs.removeAll(keepingCapacity: true)
        configurations = 0
        configurationUpdates = 0
        sizings = 0
        nestedSizings = 0
    }

    func resetCosts() {
        rowCosts.removeAll(keepingCapacity: true)
    }

    func noteRowBody(_ id: TimelineItemIdentifier.UniqueID) {
        rowBodies += 1
        rowBodyIDs.insert(id.value)
    }

    func noteStylerBody(_ id: TimelineItemIdentifier.UniqueID) {
        stylerBodies += 1
        stylerBodyIDs.insert(id.value)
    }
    
    func notePost(_ id: TimelineItemIdentifier.UniqueID, slot: SpiralAppSlot) {
        postSlots[id.value] = slot
    }

    fileprivate func kind(of cell: AnyObject) -> String {
        guard let id = (cell as? TimelineItemCell)?.item?.identifier.uniqueID.value else { return "unknown" }
        return kinds[id] ?? "incoming"
    }

    fileprivate func noteConfiguration(of cell: AnyObject, wall: UInt64, cpu: UInt64) {
        configurations += 1
        isNextSizingFirst = true
        cellIDs.insert(ObjectIdentifier(cell))
        let kind = kind(of: cell)
        rowCosts[kind, default: .init()].configureWall.append(wall)
        rowCosts[kind, default: .init()].configureCPU.append(cpu)
    }

    fileprivate func noteSizing(of cell: AnyObject, wall: UInt64, cpu: UInt64) {
        // UIKit's sizing may call itself: only the outermost call is the sizing's cost.
        guard sizingDepth == 0 else {
            nestedSizings += 1
            return
        }
        sizings += 1
        let kind = kind(of: cell)
        rowCosts[kind, default: .init()].sizeWall.append(wall)
        rowCosts[kind, default: .init()].sizeCPU.append(cpu)
        if isNextSizingFirst {
            isNextSizingFirst = false
            rowCosts[kind, default: .init()].firstSizeCPU.append(cpu)
        }
    }

    fileprivate func noteLayout(of cell: AnyObject, wall: UInt64, cpu: UInt64) {
        let kind = kind(of: cell)
        rowCosts[kind, default: .init()].layoutWall.append(wall)
        rowCosts[kind, default: .init()].layoutCPU.append(cpu)
    }

    fileprivate func noteConfigurationUpdate() {
        configurationUpdates += 1
    }
}

/// Times the real cell from outside: these add overrides to `TimelineItemCell` at run time, so the table runs its own code
/// with nothing changed in the cell or in its data source.
enum TimelineBenchCellHooks {
    private typealias Configure = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    private typealias Fit = @convention(c) (AnyObject, Selector, CGSize, Float, Float) -> CGSize
    private typealias Layout = @convention(c) (AnyObject, Selector) -> Void
    private typealias Update = @convention(c) (AnyObject, Selector, AnyObject) -> Void

    @MainActor
    static func install() {
        let probe = TimelineBenchProbe.shared

        let configure = NSSelectorFromString("setContentConfiguration:")
        let superConfigure = unsafeBitCast(superMethod(configure), to: Configure.self)
        let configureBlock: @convention(block) (AnyObject, AnyObject?) -> Void = { cell, configuration in
            let wall = TimelineBenchClock.wall
            let cpu = TimelineBenchClock.cpu
            superConfigure(cell, configure, configuration)
            probe.noteConfiguration(of: cell, wall: TimelineBenchClock.wall - wall, cpu: TimelineBenchClock.cpu - cpu)
        }
        add(configure, block: configureBlock)

        let fit = NSSelectorFromString("systemLayoutSizeFittingSize:withHorizontalFittingPriority:verticalFittingPriority:")
        let superFit = unsafeBitCast(superMethod(fit), to: Fit.self)
        let fitBlock: @convention(block) (AnyObject, CGSize, Float, Float) -> CGSize = { cell, size, horizontal, vertical in
            let wall = TimelineBenchClock.wall
            let cpu = TimelineBenchClock.cpu
            probe.sizingDepth += 1
            let result = superFit(cell, fit, size, horizontal, vertical)
            probe.sizingDepth -= 1
            probe.noteSizing(of: cell, wall: TimelineBenchClock.wall - wall, cpu: TimelineBenchClock.cpu - cpu)
            return result
        }
        add(fit, block: fitBlock)

        let layout = NSSelectorFromString("layoutSubviews")
        let superLayout = unsafeBitCast(superMethod(layout), to: Layout.self)
        let layoutBlock: @convention(block) (AnyObject) -> Void = { cell in
            let wall = TimelineBenchClock.wall
            let cpu = TimelineBenchClock.cpu
            superLayout(cell, layout)
            probe.noteLayout(of: cell, wall: TimelineBenchClock.wall - wall, cpu: TimelineBenchClock.cpu - cpu)
        }
        add(layout, block: layoutBlock)

        let update = NSSelectorFromString("updateConfigurationUsingState:")
        let superUpdate = unsafeBitCast(superMethod(update), to: Update.self)
        let updateBlock: @convention(block) (AnyObject, AnyObject) -> Void = { cell, state in
            probe.noteConfigurationUpdate()
            superUpdate(cell, update, state)
        }
        add(update, block: updateBlock)
    }

    private static func superMethod(_ selector: Selector) -> IMP {
        guard let implementation = class_getMethodImplementation(UITableViewCell.self, selector) else {
            fatalError("UITableViewCell has no \(selector)")
        }
        return implementation
    }

    private static func add(_ selector: Selector, block: Any) {
        guard let method = class_getInstanceMethod(UITableViewCell.self, selector),
              class_addMethod(TimelineItemCell.self, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method)) else {
            fatalError("Couldn't add \(selector) to TimelineItemCell")
        }
    }
}

// MARK: - Memory

enum TimelineBenchMemory {
    /// The footprint in bytes, the number the system judges an app by.
    static var footprint: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) : 0
    }
}

#endif
