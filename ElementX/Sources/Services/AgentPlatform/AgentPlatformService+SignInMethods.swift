//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3, operator 2026-11-20): how the account signs in, and
// adding Sign in with Apple to it.
//

import AgentPlatformClient
import Foundation

extension AgentPlatformService {
    func fetchSignInMethods() async -> Result<SignInMethods, AgentPlatformError> {
        await withUnauthorizedRetry { [client] in
            switch try await client.underlying.getSignInMethods() {
            case .ok(let ok):
                return try .success(SignInMethods(ok.body.json))
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound:
                return .failure(.notFound)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .serviceUnavailable:
                return .failure(.serverError(status: 503))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }
    
    func createAppleLink() async -> Result<URL, AgentPlatformError> {
        await withUnauthorizedRetry { [client, identityHost] in
            switch try await client.underlying.createAppleLink() {
            case .ok(let ok):
                return try Self.identityPageURL(ok.body.json.url, identityHost: identityHost)
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound:
                return .failure(.notFound)
            case .internalServerError:
                return .failure(.serverError(status: 500))
            case .undocumented(statusCode: let code, _):
                return .failure(Self.mapUndocumented(code))
            }
        }
    }
    
    /// A one-time identity page opens only if it is `https` on the identity host this
    /// environment's server sends (`id.<server>`), or on any host when that is not known.
    /// `ASWebAuthenticationSession` raises an exception on anything but http(s).
    nonisolated static func identityPageURL(_ string: String, identityHost: String?) -> Result<URL, AgentPlatformError> {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host(), !host.isEmpty,
              identityHost.map({ host.lowercased() == $0.lowercased() }) ?? true else {
            return .failure(.validation(detail: "identity page url"))
        }
        return .success(url)
    }
}

extension SignInMethods {
    nonisolated init(_ response: Components.Schemas.SignInMethodsResponse) {
        self.init(phrase: response.phrase,
                  apple: response.apple,
                  appleAvailable: response.appleAvailable)
    }
}
