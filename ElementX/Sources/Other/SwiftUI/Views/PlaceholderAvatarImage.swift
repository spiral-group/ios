//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct PlaceholderAvatarImage: View {
    @Environment(\.redactionReasons) private var redactionReasons
    
    private let textForImage: String
    // AGENT-PLATFORM (Brief 0083, decision 328): no stored content ID; it only picked Compound's decorative colour.
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                AvatarMonogramBackground(diameter: geometry.size.width) // AGENT-PLATFORM (Brief 0083)
                
                // This text's frame doesn't look right when redacted
                if redactionReasons != .placeholder {
                    Text(textForImage)
                        .foregroundColor(.compound.textOnSolidPrimary) // AGENT-PLATFORM (Brief 0083)
                        .font(.system(size: geometry.size.width * 0.5625, weight: .semibold))
                        .minimumScaleFactor(0.001)
                        .frame(alignment: .center)
                }
            }
        }
        .aspectRatio(1, contentMode: .fill)
    }
    
    init(name: String?, contentID: String) {
        let baseName = name ?? contentID.trimmingCharacters(in: .punctuationCharacters)
        textForImage = baseName.first?.uppercased() ?? ""
    }
}

// AGENT-PLATFORM (Brief 0083, decision 328, critique F4): iOS's monogram under a white initial, not Compound's
// pastel fill under a darker initial of its hue, Element's signature. An agent's Peek sits on it too (question 389).
struct AvatarMonogramBackground: View {
    @Environment(\.redactionReasons) private var redactionReasons
    
    let diameter: CGFloat
    
    var body: some View {
        if redactionReasons.contains(.placeholder) {
            Color(.systemGray4) // matches the default text redaction
        } else {
            LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 328): the initial is 0.5625 of the diameter, small text through 32 pt
    // (18 pt), where it needs the darker stops' 4.5:1; from 52 pt it's large and 3:1 is enough.
    private var stops: [Color] {
        if diameter < SpiralAvatarSize.medium {
            [.spiral.avatarMonogramSmallTop, .spiral.avatarMonogramSmallBottom]
        } else {
            [.spiral.avatarMonogramTop, .spiral.avatarMonogramBottom]
        }
    }
}

struct PlaceholderAvatarImage_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 75) {
            PlaceholderAvatarImage(name: "Xavier", contentID: "@userid1:matrix.org")
                .clipShape(Circle())
                .frame(width: 150, height: 100)
            
            PlaceholderAvatarImage(name: "@*~AmazingName~*@", contentID: "@userid2:matrix.org")
                .clipShape(Circle())
                .frame(width: 150, height: 100)
            
            PlaceholderAvatarImage(name: nil, contentID: "@userid3:matrix.org")
                .clipShape(Circle())
                .frame(width: 150, height: 100)
            
            PlaceholderAvatarImage(name: nil, contentID: "@fooserid:matrix.org")
                .clipShape(Circle())
                .frame(width: 30, height: 30)
        }
        
        // AGENT-PLATFORM (Brief 0083, decision 300b): the six steps, then six people at 52 and at 24 pt.
        // The steps and their spacing take 370 pt, within the narrowest snapshot device.
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 6) {
                ForEach(scale, id: \.self) { avatar(people[2], size: $0) }
            }
            HStack(spacing: 8) {
                ForEach(people, id: \.self) { avatar($0, size: SpiralAvatarSize.medium) }
            }
            HStack(spacing: 8) {
                ForEach(people, id: \.self) { avatar($0, size: SpiralAvatarSize.xSmall) }
            }
        }
        .padding(.vertical, 16)
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Scale")
    }
    
    // AGENT-PLATFORM (Brief 0083)
    private static let scale = [SpiralAvatarSize.xxSmall, SpiralAvatarSize.xSmall, SpiralAvatarSize.small,
                                SpiralAvatarSize.medium, SpiralAvatarSize.large, SpiralAvatarSize.xLarge]
    private static let people = ["carol", "lena", "helena", "maya", "omar", "aiko"]
    
    private static func avatar(_ name: String, size: CGFloat) -> some View {
        PlaceholderAvatarImage(name: name.capitalized, contentID: "@\(name):matrix.org")
            .clipShape(Circle())
            .frame(width: size, height: size)
    }
}
