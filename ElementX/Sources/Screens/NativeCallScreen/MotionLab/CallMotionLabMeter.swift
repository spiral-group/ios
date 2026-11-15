//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): what the lab's drawings cost. The bar draws over the timeline, the app's
// first priority, so each variant reports its own Canvas time per frame and the process's CPU while it runs.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import SwiftUI

@Observable
final class CallMotionLabMeter {
    struct Reading: Equatable {
        /// Frames the measured drawings rendered in the last second.
        var framesPerSecond = 0
        /// Main-thread CPU spent inside the drawings' Canvas closures, per frame.
        var drawMicroseconds = 0.0
        /// The main thread's CPU over the last second, % of one core.
        var mainThreadPercent = 0.0
        /// The whole app's CPU over the last second, % of one core.
        var processPercent = 0.0
    }

    static let shared = CallMotionLabMeter()

    private(set) var reading = Reading()

    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var drawNanoseconds: UInt64 = 0
    @ObservationIgnored private var lastWall = CallMotionLabMeter.wallSeconds
    @ObservationIgnored private var lastProcessCPU = CallMotionLabMeter.processCPUSeconds
    @ObservationIgnored private var lastMainCPU = CallMotionLabMeter.threadCPUNanoseconds
    @ObservationIgnored private var sampler: Task<Void, Never>?

    /// Times one drawing's Canvas closure on the main thread's CPU clock.
    func measure<Result>(_ draw: () -> Result) -> Result {
        let start = Self.threadCPUNanoseconds
        defer {
            drawNanoseconds += Self.threadCPUNanoseconds - start
            frames += 1
        }
        return draw()
    }

    func start() {
        guard sampler == nil else { return }
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.sample()
            }
        }
    }

    func stop() {
        sampler?.cancel()
        sampler = nil
    }

    private func sample() {
        let wall = Self.wallSeconds
        let processCPU = Self.processCPUSeconds
        let mainCPU = Self.threadCPUNanoseconds
        let elapsed = max(wall - lastWall, 0.001)

        reading = Reading(framesPerSecond: Int((Double(frames) / elapsed).rounded()),
                          drawMicroseconds: frames > 0 ? Double(drawNanoseconds) / Double(frames) / 1000 : 0,
                          mainThreadPercent: Double(mainCPU - lastMainCPU) / 1e9 / elapsed * 100,
                          processPercent: (processCPU - lastProcessCPU) / elapsed * 100)

        if Self.logsCost {
            // Read by the lane's measurement script through `simctl launch --stdout`; MXLog doesn't write to stdout.
            // swiftlint:disable:next print_deprecation
            print(String(format: "cost fps=%d draw_us=%.1f main=%.2f%% app=%.2f%%",
                         reading.framesPerSecond, reading.drawMicroseconds, reading.mainThreadPercent, reading.processPercent))
        }

        frames = 0
        drawNanoseconds = 0
        lastWall = wall
        lastProcessCPU = processCPU
        lastMainCPU = mainCPU
    }

    /// `-SpiralCallMotionLabLogCost YES` prints each second's reading.
    private static let logsCost = UserDefaults.standard.bool(forKey: "SpiralCallMotionLabLogCost")

    private static var wallSeconds: Double {
        Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
    }

    /// The calling thread's CPU time; the meter is used on the main thread only.
    private static var threadCPUNanoseconds: UInt64 {
        clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }

    private static var processCPUSeconds: Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return user + system
    }
}

#endif
