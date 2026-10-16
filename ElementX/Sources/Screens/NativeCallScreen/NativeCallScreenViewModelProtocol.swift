//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

// AGENT-PLATFORM (Brief 0063)

@MainActor
protocol NativeCallScreenViewModelProtocol {
    var actions: AnyPublisher<NativeCallScreenViewModelAction, Never> { get }
    var context: NativeCallScreenViewModelType.Context { get }
    
    /// The CallKit call this screen ends when it stops (follow-up N1).
    var callKitID: UUID? { get }
    
    /// The screen shows its call's end, or is stopping: a call route to its
    /// room gets a fresh screen, not this one.
    var hasCallEnded: Bool { get }
    
    /// An answer of this screen's room landed on this screen: the screen
    /// ends that call from now on.
    func bind(toCallKitID callKitID: UUID)
    
    /// Start the call. Called by the coordinator once the screen is presented.
    func start()
    
    /// Tear the call down, e.g. when the screen is dismissed.
    func stop()
    
    /// The callee refused the ring (MSC4310 decline).
    func remoteDeclined()
}
