//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct LoginScreen: View {
    /// The focus state of the username text field.
    @FocusState private var isUsernameFocused: Bool
    /// The focus state of the password text field.
    @FocusState private var isPasswordFocused: Bool
    
    @Bindable var context: LoginScreenViewModel.Context
    
    var body: some View {
        ScrollView {
            // AGENT-PLATFORM (Brief 0083, decision 308): the title leads, left aligned, without the lock icon, and
            // the fields sit closer together, as on the storyboard.
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, UIConstants.titleTopPaddingToNavigationBar)
                    .padding(.bottom, CompoundDesignTokens.space8X)
                
                switch context.viewState.loginMode {
                case .password:
                    loginForm
                case .oAuth:
                    // This should never be shown.
                    ProgressView()
                default:
                    // This should never be shown either.
                    loginUnavailableText
                }
            }
            .readableFrame()
            .padding(.horizontal, CompoundDesignTokens.space6X)
            .padding(.bottom, CompoundDesignTokens.space4X)
        }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
    }
    
    /// The header containing the title.
    var header: some View {
        // AGENT-PLATFORM (Brief 0083, decision 308): no lock icon; a larger title, left aligned.
        Text(L10n.screenLoginTitleWithHomeserver(context.viewState.homeserver.accountProvider.serverNameOrBaseURL))
            .font(.compound.headingLGBold)
            .foregroundColor(.compound.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
    
    /// The form with text fields for username and password, along with a submit button.
    var loginForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(text: $context.username) {
                Text(L10n.commonUsername).foregroundColor(.compound.textSecondary)
            }
            .focused($isUsernameFocused)
            .textFieldStyle(.compound(labelText: L10n.screenLoginFormHeader, accessibilityIdentifier: A11yIdentifiers.loginScreen.emailUsername))
            .disableAutocorrection(true)
            .textContentType(.username)
            .autocapitalization(.none)
            .submitLabel(.next)
            .onChange(of: isUsernameFocused) { _, newValue in
                usernameFocusChanged(isFocussed: newValue)
            }
            .onSubmit { isPasswordFocused = true }
            .padding(.bottom, CompoundDesignTokens.space3X) // AGENT-PLATFORM (Brief 0083): the storyboard's spacing
            
            SecureField(text: $context.password) {
                Text(L10n.commonPassword).foregroundColor(.compound.textSecondary)
            }
            .focused($isPasswordFocused)
            .textFieldStyle(.compound(accessibilityIdentifier: A11yIdentifiers.loginScreen.password))
            .textContentType(.password)
            .submitLabel(.done)
            .onSubmit(submit)
            
            Spacer().frame(height: CompoundDesignTokens.space6X) // AGENT-PLATFORM (Brief 0083): the storyboard's spacing
            
            Button(action: submit) {
                Text(L10n.actionContinue)
            }
            .buttonStyle(.compound(.primary))
            .disabled(!context.viewState.canSubmit)
            .accessibilityIdentifier(A11yIdentifiers.loginScreen.continue)
        }
    }
    
    /// Text shown if neither password or OAuth login is supported.
    var loginUnavailableText: some View {
        // AGENT-PLATFORM (Brief 0083): left aligned under the title.
        Text(L10n.screenLoginErrorUnsupportedAuthentication)
            .font(.compound.bodyLG)
            .foregroundColor(.compound.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(A11yIdentifiers.loginScreen.unsupportedServer)
    }
    
    /// Parses the username for a homeserver.
    private func usernameFocusChanged(isFocussed: Bool) {
        guard !isFocussed, !context.username.isEmpty else { return }
        context.send(viewAction: .parseUsername)
    }
    
    /// Sends the `next` view action so long as valid credentials have been input.
    private func submit() {
        guard context.viewState.canSubmit else { return }
        context.send(viewAction: .next)
        isUsernameFocused = false
        isPasswordFocused = false
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083): opted in to Spiral's gates. Without `@available(iOS 26.0, *)` it builds for the
// iOS 18 lane, and `observe(_:)` resolves to its AsyncStream fallback.
struct LoginScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel()
    static let credentialsViewModel = makeViewModel(withCredentials: true)
    static let unconfiguredViewModel = makeViewModel(serverNameOrBaseURL: "somethingtofailconfiguration")
    
    static var previews: some View {
        ElementNavigationStack {
            LoginScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.homeserver.loginMode).map { $0 == .password })
        .previewDisplayName("Initial State")
        
        ElementNavigationStack {
            LoginScreen(context: credentialsViewModel.context)
        }
        .snapshotPreferences(expect: credentialsViewModel.context.observe(\.viewState.homeserver.loginMode).map { $0 == .password })
        .previewDisplayName("Credentials Entered")
        
        ElementNavigationStack {
            LoginScreen(context: unconfiguredViewModel.context)
        }
        .previewDisplayName("Unsupported")
    }
    
    static func makeViewModel(serverNameOrBaseURL: String = "example.com", withCredentials: Bool = false) -> LoginScreenViewModel {
        let authenticationService = AuthenticationService.mock
        
        Task { await authenticationService.configure(for: serverNameOrBaseURL, flow: .login) }
        
        let viewModel = LoginScreenViewModel(authenticationService: authenticationService,
                                             loginHint: nil,
                                             userIndicatorController: UserIndicatorControllerMock()) // AGENT-PLATFORM (Brief 0083 L1b)
        
        if withCredentials {
            viewModel.context.username = "alice"
            viewModel.context.password = "password"
        }
        
        return viewModel
    }
}
