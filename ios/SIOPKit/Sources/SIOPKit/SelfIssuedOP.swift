import Foundation

/// Self-Issued OpenID Provider (OpenID Connect Core 1.0 Section 7).
public struct SelfIssuedOP {
    public let keyProvider: SIOPKeyProvider

    public init(keyProvider: SIOPKeyProvider) {
        self.keyProvider = keyProvider
    }

    /// Handles an authentication request URL (openid://...) and produces the
    /// response to deliver to the RP's redirect URI (Section 7.4).
    public func handle(url: URL, now: Date = Date()) throws -> AuthenticationResponse {
        let request = try AuthorizationRequest(url: url)
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

        var fragment = "id_token=\(idToken)"
        if let state {
            let allowed = CharacterSet.urlFragmentAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))
            guard let encoded = state.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw SIOPError.invalidRequest("state cannot be encoded")
            }
            fragment += "&state=\(encoded)"
        }
        guard var components = URLComponents(string: redirectURI) else {
            throw SIOPError.invalidRequest("client_id must be the RP redirect URI")
        }
        components.percentEncodedFragment = fragment
        guard let url = components.url else {
            throw SIOPError.invalidRequest("failed to build redirect URL")
        }
        self.redirectURL = url
    }
}
