//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SpiralTokens
import SwiftUI

struct LoadableAvatarImage: View {
    enum Shape {
        case circle
        case roundedRect
        // AGENT-PLATFORM (Brief 0083, decision 357): a group room's. `roundedRect` stays a space's.
        case roundedSquare
    }
    
    private let url: URL?
    private let name: String?
    private let contentID: String
    private let shape: Shape
    private let avatarSize: Avatars.Size
    private let mediaProvider: MediaProviderProtocol?
    private let onTap: ((URL) -> Void)?
    
    @ScaledMetric private var frameSize: CGFloat
    
    init(url: URL?,
         name: String?,
         contentID: String,
         shape: LoadableAvatarImage.Shape = .circle,
         avatarSize: Avatars.Size,
         mediaProvider: MediaProviderProtocol?,
         onTap: ((URL) -> Void)? = nil) {
        self.url = url
        self.name = name
        self.contentID = contentID
        self.shape = shape
        self.avatarSize = avatarSize
        self.mediaProvider = mediaProvider
        self.onTap = onTap
        
        _frameSize = ScaledMetric(wrappedValue: avatarSize.value)
    }
    
    var body: some View {
        if let onTap, let url {
            Button {
                onTap(url)
            } label: {
                clippedAvatar
            }
            .buttonStyle(.borderless) // Add a button style to stop the whole row being tappable.
        } else {
            clippedAvatar
        }
    }
    
    private var clippedAvatar: some View {
        avatar
            .frame(width: frameSize, height: frameSize)
            .background {
                Color.compound.bgCanvasDefault
                    .allowedDynamicRange(.standard) // Workaround an iOS 27.0 bug where full white goes HDR in a toolbar.
            }
            .avatarShape(shape, scaledSize: _frameSize)
            .allowedDynamicRange(.standard) // Prevent loaded avatars from triggering HDR display.
            .environment(\.shouldAutomaticallyLoadImages, true) // We always load avatars.
    }
    
    @ViewBuilder
    private var avatar: some View {
        if let url {
            LoadableImage(url: url,
                          mediaType: .avatar,
                          size: avatarSize.scaledSize,
                          mediaProvider: mediaProvider) { image in
                image
                    .scaledToFill()
                    // AGENT-PLATFORM (1.0.3): decoration beside the name it stands for, as the Peek is; shown, it was an
                    // image without a description wherever a caller hadn't hidden the avatar.
                    .accessibilityHidden(true)
            } placeholder: {
                fallback
            }
        } else {
            fallback
        }
    }
    
    // AGENT-PLATFORM (question 389): an agent shows the Peek, not its letter; in a colour of its own (390).
    @ViewBuilder
    private var fallback: some View {
        switch AgentAvatar.fallback(contentID: contentID) {
        case .letter:
            PlaceholderAvatarImage(name: name, contentID: contentID)
                // AGENT-PLATFORM (1.0.3): hidden like the loaded picture, so an avatar reads the same before and after it loads.
                .accessibilityHidden(true)
        case .peek:
            PeekAvatarImage(agentID: contentID)
        }
    }
}

extension View {
    func avatarShape(_ shape: LoadableAvatarImage.Shape, size: CGFloat) -> some View {
        modifier(AvatarShapeModifier(shape: shape, size: size))
    }
    
    func avatarShape(_ shape: LoadableAvatarImage.Shape, scaledSize: ScaledMetric<CGFloat>) -> some View {
        modifier(AvatarShapeModifier(shape: shape, scaledSize: scaledSize))
    }
}

private struct AvatarShapeModifier: ViewModifier {
    private let shape: LoadableAvatarImage.Shape
    @ScaledMetric private var scaledSize: CGFloat
    
    init(shape: LoadableAvatarImage.Shape, size: CGFloat) {
        self.shape = shape
        _scaledSize = ScaledMetric(wrappedValue: size)
    }
    
    init(shape: LoadableAvatarImage.Shape, scaledSize: ScaledMetric<CGFloat>) {
        self.shape = shape
        _scaledSize = scaledSize
    }
    
    func body(content: Content) -> some View {
        switch shape {
        case .circle:
            content.clipShape(Circle())
        case .roundedRect:
            let shape = RoundedRectangle(cornerRadius: scaledSize / 4)
            content
                .clipShape(shape)
                .overlay(shape.stroke(.compound.iconQuaternaryAlpha, lineWidth: 1))
        case .roundedSquare:
            content.clipShape(RoundedRectangle(cornerRadius: SpiralRadius.groupAvatar(side: scaledSize), style: .continuous))
        }
    }
}
