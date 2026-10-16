//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

/// Just for API sanity checking, they're already properly tested in the SDK/Ruma
///
/// AGENT-PLATFORM (Brief 0060 / ADR-0072): the matrix.to *generation*
/// coverage was removed together with its last product call site — we
/// only ever build `spiral.md` links now (`SpiralLinkTests`). Inbound
/// matrix.to *parsing* stays covered below because the mautrix bridges
/// keep emitting matrix.to links inside message HTML.
struct PermalinkTests {
    @Test
    func permalinkDetection() {
        var url: URL = "https://www.matrix.org"
        #expect(parseMatrixEntityFrom(uri: url.absoluteString) == nil)
        
        url = "https://matrix.to/#/@bob:matrix.org?via=matrix.org"
        #expect(parseMatrixEntityFrom(uri: url.absoluteString) ==
            MatrixEntity(id: .user(id: "@bob:matrix.org"),
                         via: ["matrix.org"]))
        
        url = "https://matrix.to/#/!roomidentifier:matrix.org?via=matrix.org"
        #expect(parseMatrixEntityFrom(uri: url.absoluteString) ==
            MatrixEntity(id: .room(id: "!roomidentifier:matrix.org"),
                         via: ["matrix.org"]))
        
        url = "https://matrix.to/#/%23roomalias:matrix.org?via=matrix.org"
        #expect(parseMatrixEntityFrom(uri: url.absoluteString) ==
            MatrixEntity(id: .roomAlias(alias: "#roomalias:matrix.org"),
                         via: ["matrix.org"]))
        
        url = "https://matrix.to/#/!roomidentifier:matrix.org/$eventidentifier?via=matrix.org"
        #expect(parseMatrixEntityFrom(uri: url.absoluteString) ==
            MatrixEntity(id: .eventOnRoomId(roomId: "!roomidentifier:matrix.org", eventId: "$eventidentifier"),
                         via: ["matrix.org"]))
        
        url = "https://matrix.to/#/#roomalias:matrix.org/$eventidentifier?via=matrix.org"
        #expect(parseMatrixEntityFrom(uri: url.absoluteString) ==
            MatrixEntity(id: .eventOnRoomAlias(alias: "#roomalias:matrix.org", eventId: "$eventidentifier"),
                         via: ["matrix.org"]))
    }
}
