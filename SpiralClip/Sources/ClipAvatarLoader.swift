//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the App Clip for invite links (Brief 0086).
//

import SwiftUI

protocol ClipAvatarLoaderProtocol {
    func image(at url: URL) async -> UIImage?
}

/// Fetches the inviter's public picture, kept in memory only: an ephemeral session writes nothing to disk.
final class ClipAvatarLoader: ClipAvatarLoaderProtocol {
    private let session = URLSession(configuration: .ephemeral)
    private var cache: [URL: UIImage] = [:]
    
    func image(at url: URL) async -> UIImage? {
        if let image = cache[url] {
            return image
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else {
            return nil
        }
        cache[url] = image
        return image
    }
}
