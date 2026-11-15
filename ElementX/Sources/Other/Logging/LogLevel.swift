//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

nonisolated enum LogLevel: String, Codable, Hashable {
    case error, warn, info, debug, trace
    
    var title: String {
        switch self {
        case .error:
            return "Error"
        case .warn:
            return "Warning"
        case .info:
            return "Info"
        case .debug:
            return "Debug"
        case .trace:
            return "Trace"
        }
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 359): whether a log set to this level writes what's logged at `level`.
    func includes(_ level: LogLevel) -> Bool {
        level.verbosity <= verbosity
    }
    
    private var verbosity: Int {
        switch self {
        case .error: 0
        case .warn: 1
        case .info: 2
        case .debug: 3
        case .trace: 4
        }
    }
    
    var rustLogLevel: MatrixRustSDK.LogLevel {
        switch self {
        case .error:
            .error
        case .warn:
            .warn
        case .info:
            .info
        case .debug:
            .debug
        case .trace:
            .trace
        }
    }
}
