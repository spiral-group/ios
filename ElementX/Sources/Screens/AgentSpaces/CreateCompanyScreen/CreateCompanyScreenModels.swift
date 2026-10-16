//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import UIKit

// AGENT-PLATFORM: Brief 0037, artboard 0037-H — create a company space.
// Brief 0039 S3 rebuilt the form on the CreateRoomScreen canon: logo
// avatar-in-name-header, confirmationDialog media sources, deferred save
// (the logo uploads via `clientProxy.uploadMedia` at Create time and the
// resulting mxc travels as `branding_mxc` in the ONE create call).

enum CreateCompanyScreenViewModelAction {
    /// Created — the flow dismisses the sheet and opens the new space.
    case created(AgentSpaceSummary)
    case cancel
    case displayCameraPicker
    case displayMediaPicker
    case displayFilePicker
}

struct CreateCompanyScreenViewState: BindableState {
    var isCreating = false
    var bindings = CreateCompanyScreenViewStateBindings()
    
    /// Deferred logo — accumulated locally, uploaded on Create
    /// (CreateRoom canon: `avatarMediaInfo` + derived `avatarImage`).
    var avatarMediaInfo: MediaInfo? {
        didSet {
            switch avatarMediaInfo {
            case .image(_, let thumbnailURL, _):
                avatarImage = UIImage(contentsOfFile: thumbnailURL.path(percentEncoded: false))
            default:
                avatarImage = nil
            }
        }
    }
    
    var avatarImage: UIImage?
    
    var canCreate: Bool {
        !bindings.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }
}

struct CreateCompanyScreenViewStateBindings {
    var name = ""
    var industry = ""
    var website = ""
    var showAttachmentConfirmationDialog = false
    var alertInfo: AlertInfo<CreateCompanyScreenAlertType>?
}

enum CreateCompanyScreenAlertType: Hashable {
    case createFailed
    case failedProcessingMedia
    case failedUploadingLogo
}

enum CreateCompanyScreenViewAction {
    case create
    case cancel
    case displayCameraPicker
    case displayMediaPicker
    case displayFilePicker
    case removeImage
}
