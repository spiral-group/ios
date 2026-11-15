//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 357, reversing 331 (b)): a person's colour in a group.
//

import SpiralTokens
import SwiftUI

/// A person's hue: the same on every device and in every room, as it comes from their ID alone.
enum SenderHue: Int, CaseIterable {
    case coral, amber, green, teal, azure, violet, magenta
    
    init(userID: String) {
        // `hashValue` changes on every launch, so a small hash of our own.
        let hash = userID.utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) }
        self = Self.allCases[Int(hash % UInt32(Self.allCases.count))]
    }
    
    var color: Color {
        switch self {
        case .coral: .spiral.senderCoral
        case .amber: .spiral.senderAmber
        case .green: .spiral.senderGreen
        case .teal: .spiral.senderTeal
        case .azure: .spiral.senderAzure
        case .violet: .spiral.senderViolet
        case .magenta: .spiral.senderMagenta
        }
    }
}
