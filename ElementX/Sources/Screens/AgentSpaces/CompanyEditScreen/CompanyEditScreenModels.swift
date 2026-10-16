//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import UIKit

// AGENT-PLATFORM: Brief 0039 S4b — edit a company space's profile on the
// RoomDetailsEditScreen canon: centred logo avatar with the
// confirmationDialog sources, labelled NAME/INDUSTRY/WEBSITE sections,
// deferred save (changed logo uploads via `clientProxy.uploadMedia` at
// Save time; one PATCH carries only the changed fields) and the
// unsaved-changes gate on Cancel.

enum CompanyEditScreenViewModelAction {
    case cancel
    case saveFinished
    case displayCameraPicker
    case displayMediaPicker
    case displayFilePicker
}

struct CompanyEditScreenViewState: BindableState {
    let orgID: String
    let initialName: String
    let initialIndustry: String
    let initialWebsite: String
    let initialLogoMXC: String?
    
    /// Current logo (nil after Remove — an explicit clear on save).
    var logoMXC: String?
    /// Deferred replacement logo, uploaded at Save time.
    var localMedia: MediaInfo? {
        didSet {
            switch localMedia {
            case .image(_, let thumbnailURL, _):
                localMediaThumbnail = UIImage(contentsOfFile: thumbnailURL.path(percentEncoded: false))
            default:
                localMediaThumbnail = nil
            }
        }
    }
    
    var localMediaThumbnail: UIImage?
    var isSaving = false
    
    var bindings: CompanyEditScreenViewStateBindings
    
    var nameDidChange: Bool {
        bindings.name.trimmingCharacters(in: .whitespacesAndNewlines) != initialName
    }
    
    var industryDidChange: Bool {
        bindings.industry.trimmingCharacters(in: .whitespacesAndNewlines) != initialIndustry
    }
    
    var websiteDidChange: Bool {
        bindings.website.trimmingCharacters(in: .whitespacesAndNewlines) != initialWebsite
    }
    
    var logoDidChange: Bool {
        localMedia != nil || logoMXC != initialLogoMXC
    }
    
    var canSave: Bool {
        !bindings.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (logoDidChange || nameDidChange || industryDidChange || websiteDidChange)
            && !isSaving
    }
    
    var showDeleteImageAction: Bool {
        localMedia != nil || logoMXC != nil
    }
}

struct CompanyEditScreenViewStateBindings {
    var name: String
    var industry: String
    var website: String
    var showMediaSheet = false
    
    var alertInfo: AlertInfo<CompanyEditScreenAlertType>?
}

enum CompanyEditScreenAlertType {
    case failedProcessingMedia
    case failedUploadingLogo
    case unsavedChanges
    case saveFailed
}

enum CompanyEditScreenViewAction {
    case cancel
    case save
    case presentMediaSource
    case displayCameraPicker
    case displayMediaPicker
    case displayFilePicker
    case removeImage
}
