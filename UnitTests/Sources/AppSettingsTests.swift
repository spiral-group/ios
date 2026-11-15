//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import Spiral
import Testing

struct AppSettingsTests {
    @Test
    func defaultAccountProvider() {
        let appSettings = AppSettings.volatile()
        #expect(appSettings.defaultAccountProvider == appSettings.accountProviders[0])
        
        // AGENT-PLATFORM: Spiral's default is the closed provider list; open it as upstream's is.
        appSettings.override(allowOtherAccountProviders: true)
        appSettings.previousServers = ["example.com"]
        #expect(appSettings.defaultAccountProvider == .generic("example.com"))
        
        appSettings.override(allowOtherAccountProviders: false)
        #expect(appSettings.defaultAccountProvider == appSettings.accountProviders[0])
    }
}

// MARK: - Helpers

private extension AppSettings {
    func override(allowOtherAccountProviders: Bool) {
        override(accountProviders: accountProviders,
                 allowOtherAccountProviders: allowOtherAccountProviders,
                 hideBrandChrome: hideBrandChrome,
                 pushGatewayBaseURL: pushGatewayBaseURL,
                 oAuthRedirectURL: oAuthRedirectURL,
                 oAuthClientURIPath: oAuthClientURIPath,
                 websiteURL: websiteURL,
                 logoURL: logoURL,
                 copyrightURL: copyrightURL,
                 acceptableUseURL: acceptableUseURL,
                 privacyURL: privacyURL,
                 encryptionURL: encryptionURL,
                 deviceVerificationURL: deviceVerificationURL,
                 chatBackupDetailsURL: chatBackupDetailsURL,
                 identityPinningViolationDetailsURL: identityPinningViolationDetailsURL,
                 historySharingDetailsURL: historySharingDetailsURL, // AGENT-PLATFORM (Brief 0083 L1b): no accountProvisioningHost
                 bugReportApplicationID: bugReportApplicationID,
                 analyticsTermsURL: analyticsTermsURL,
                 mapTilerConfiguration: mapTilerConfiguration.publisher.value)
    }
}
