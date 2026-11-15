//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

// AGENT-PLATFORM (Brief 0083, question 357): Telegram's ticks beside the time, in every own bubble. One when the server
// has the message, two when it's read. Matrix has no "delivered to a device", so one tick means the server.
struct TimelineDeliveryStatusView: View {
    enum Status {
        case sending
        case sent
        case read
        
        var accessibilityLabel: String {
            switch self {
            case .sending: L10n.commonSending
            case .sent: L10n.commonSent
            case .read: UntranslatedL10n.a11yMessageRead
            }
        }
    }
    
    /// The width of two ticks, kept for one as well, so a message doesn't move when it's read.
    /// Text sizes scale it, as `EventBasedTimelineItemProtocol.trailingReservedSize` does.
    nonisolated static let slotWidth: CGFloat = 15
    
    let deliveryStatus: Status
    
    @ScaledMetric(relativeTo: .caption) private var width = Self.slotWidth
    @ScaledMetric(relativeTo: .caption) private var height = 10
    @ScaledMetric(relativeTo: .caption) private var lineWidth = 1.3
    
    var body: some View {
        icon
            .frame(width: width, alignment: .trailing)
            .accessibilityElement()
            .accessibilityLabel(deliveryStatus.accessibilityLabel)
    }
    
    @ViewBuilder
    private var icon: some View {
        switch deliveryStatus {
        case .sending:
            CompoundIcon(\.circle, size: .custom(12), relativeTo: .compound.bodyXS)
        case .sent:
            ticks(count: 1, width: height)
        case .read:
            ticks(count: 2, width: width)
        }
    }
    
    private func ticks(count: Int, width: CGFloat) -> some View {
        TimelineTicksShape(count: count)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: width, height: height)
    }
}

/// Drawn, as Compound has one check of a size for a list and no double one.
private nonisolated struct TimelineTicksShape: Shape {
    let count: Int
    
    /// A shape mirrors in RTL by default, and a tick isn't an arrow.
    var layoutDirectionBehavior: LayoutDirectionBehavior {
        .fixed
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let unit = rect.height / 10
        
        // The tick nearest the corner, drawn from its right so that one tick and two end at the same place.
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.maxX - (9.5 - x) * unit, y: rect.minY + y * unit)
        }
        // With a tick behind it, its foot stops at that tick's stroke.
        path.move(to: count > 1 ? point(1.6, 6.5) : point(0.5, 5.2))
        path.addLine(to: point(3.4, 8.6))
        path.addLine(to: point(9.2, 1.2))
        
        if count > 1 {
            func behind(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.maxX - (14.5 - x) * unit, y: rect.minY + y * unit)
            }
            path.move(to: behind(0.5, 5.2))
            path.addLine(to: behind(3.4, 8.6))
            path.addLine(to: behind(9.2, 1.2))
        }
        
        return path
    }
}

struct TimelineDeliveryStatusView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 8) {
            TimelineDeliveryStatusView(deliveryStatus: .sending)
            TimelineDeliveryStatusView(deliveryStatus: .sent)
            TimelineDeliveryStatusView(deliveryStatus: .read)
        }
    }
}
