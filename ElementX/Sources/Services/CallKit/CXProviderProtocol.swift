//
// Copyright 2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import CallKit

// sourcery: AutoMockable
protocol CXProviderProtocol {
    func setDelegate(_ delegate: CXProviderDelegate?, queue: DispatchQueue?)
    func reportNewIncomingCall(with uuid: UUID, update: CXCallUpdate, completion: @escaping @Sendable (Error?) -> Void)
    func reportCall(with uuid: UUID, endedAt: Date?, reason: CXCallEndedReason)
    func reportCall(with uuid: UUID, updated update: CXCallUpdate)
    // AGENT-PLATFORM (Brief 0063): the native path reports its outgoing calls
    // so that CallKit activates the audio session for the in-process media.
    func reportOutgoingCall(with UUID: UUID, startedConnectingAt dateStartedConnecting: Date?)
    func reportOutgoingCall(with UUID: UUID, connectedAt dateConnected: Date?)
}

extension CXProvider: CXProviderProtocol { }
