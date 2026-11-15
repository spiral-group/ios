//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

enum DeveloperOptionsScreenViewModelAction {
    case clearCache
}

struct DeveloperOptionsScreenViewState: BindableState {
    let screenHook: DeveloperOptionsScreenHookProtocol
    var storeSizes: [StoreSize]?
    let isSignedIn: Bool
    
    var bindings: DeveloperOptionsScreenViewStateBindings
    
    struct StoreSize: Identifiable {
        let name: String
        let size: String
        
        var id: String {
            name + size
        }
    }
}

@dynamicMemberLookup
struct DeveloperOptionsScreenViewStateBindings {
    private let developerOptions: DeveloperOptionsProtocol
    
    init(developerOptions: DeveloperOptionsProtocol) {
        self.developerOptions = developerOptions
    }
    
    subscript<Setting>(dynamicMember keyPath: ReferenceWritableKeyPath<DeveloperOptionsProtocol, Setting>) -> Setting {
        get { developerOptions[keyPath: keyPath] }
        set { developerOptions[keyPath: keyPath] = newValue }
    }
}

enum DeveloperOptionsScreenViewAction {
    case clearCache
    case markAllRoomsAsRead
}

protocol DeveloperOptionsProtocol: AnyObject {
    var logLevel: LogLevel { get set }
    var traceLogPacks: Set<TraceLogPack> { get set }
    
    var enableOnlySignedDeviceIsolationMode: Bool { get set }
    var hideQuietNotificationAlerts: Bool { get set }
    var focusEventOnNotificationTap: Bool { get set }
    
    // AGENT-PLATFORM (Brief 0067): `elementCallBaseURLOverride` removed with the widget (ADR-0079).
    
    var fuzzyRoomListSearchEnabled: Bool { get set }
    var lowPriorityFilterEnabled: Bool { get set }
    var mentionsFilterEnabled: Bool { get set }
    
    var linkPreviewsEnabled: Bool { get set }
    
    var jumpToReadMarkerEnabled: Bool { get set }
    
    var linkNewDeviceEnabled: Bool { get set }
    // AGENT-PLATFORM (ADR-0008).
    var registrationRequiresInvite: Bool { get set }
    var qrCodeLoginEnabled: Bool { get set }
    
    var viewSourceEnabled: Bool { get set } // AGENT-PLATFORM (decision 188): moved here from Advanced settings.
    
    var globalSearchEnabled: Bool { get set }
    var spacesEnabled: Bool { get set } // AGENT-PLATFORM (decision 301)
    
    var multiAccountEnabled: Bool { get set }
    var multiAccountEnabledPublisher: AnyPublisher<Bool, Never> { get }
    var hasSeenMultiAccountAnnouncement: Bool { get set }
    
    // AGENT-PLATFORM (Brief 0067): no `nativeCallEnabled` toggle — upstream's experimental
    // native calls (element-call-ios) are not linked; Spiral's calls are native MatrixRTC.
}

extension AppSettings: DeveloperOptionsProtocol { }
