import Foundation

/// Self-Issued OpenID Provider (OpenID Connect Core 1.0 Section 7).
public struct SelfIssuedOP {
    public let keyProvider: SIOPKeyProvider

    public init(keyProvider: SIOPKeyProvider) {
        self.keyProvider = keyProvider
    }

    /// Parses an authentication request URL (openid://...) and produces the
    /// response to deliver to the RP's redirect URI (Section 7.4).
    public func handle(url: URL, now: Date = Date()) throws -> AuthenticationResponse {
        try respond(to: try AuthorizationRequest(url: url), now: now)
    }

    /// Issues an ID Token for an already-parsed request, e.g. after the user
    /// has approved it on a consent screen.
    public func respond(to request: AuthorizationRequest, now: Date = Date()) throws -> AuthenticationResponse {
        let idToken = try SelfIssuedIDToken.issue(for: request, key: keyProvider, now: now)
        return try AuthenticationResponse(idToken: idToken, state: request.state, redirectURI: request.clientID)
    }
}

/// Self-Issued OpenID Provider Response (Section 7.4).
public struct AuthenticationResponse {
    public let idToken: String
    public let state: String?
    /// The redirect_uri with the response encoded in the URL fragment (implicit flow).
    public let redirectURL: URL

    init(idToken: String, state: String?, redirectURI: String) throws {
        self.idToken = idToken
        self.state = state
        var parameters = [("id_token", idToken)]
        if let state {
            parameters.append(("state", state))
        }
        self.redirectURL = try RedirectBuilder.url(redirectURI: redirectURI, parameters: parameters)
    }
}

/// Error response delivered to the RP's redirect URI (Section 3.1.2.6),
/// e.g. `access_denied` when the user declines the request.
public struct AuthenticationErrorResponse {
    public let error: String
    public let errorDescription: String?
    public let state: String?
    public let redirectURL: URL

    public init(
        error: String = "access_denied",
        errorDescription: String? = nil,
        request: AuthorizationRequest
    ) throws {
        self.error = error
        self.errorDescription = errorDescription
        self.state = request.state

        var parameters = [("error", error)]
        if let errorDescription {
            parameters.append(("error_description", errorDescription))
        }
        if let state = request.state {
            parameters.append(("state", state))
        }
        self.redirectURL = try RedirectBuilder.url(redirectURI: request.clientID, parameters: parameters)
    }
}

/// Builds the redirect URL carrying the response in the fragment, as the
/// implicit flow requires (Section 3.2.2.5).
enum RedirectBuilder {
    static func url(redirectURI: String, parameters: [(String, String)]) throws -> URL {
        let fragment = try parameters
            .map { name, value in
                guard let encoded = value.addingPercentEncoding(withAllowedCharacters: .siopFragmentAllowed) else {
                    throw SIOPError.invalidRequest("cannot encode \(name)")
                }
                return "\(name)=\(encoded)"
            }
            .joined(separator: "&")

        guard var components = URLComponents(string: redirectURI) else {
            throw SIOPError.invalidRequest("client_id must be the RP redirect URI")
        }
        components.percentEncodedFragment = fragment
        guard let url = components.url else {
            throw SIOPError.invalidRequest("failed to build redirect URL")
        }
        return url
    }
}

private extension CharacterSet {
    /// RFC 3986 unreserved characters — everything else is percent-encoded.
    static let siopFragmentAllowed = CharacterSet(charactersIn: "-._~")
        .union(.alphanumerics)
}
