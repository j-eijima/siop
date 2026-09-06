import Foundation

/// Self-Issued OpenID Provider Request (OpenID Connect Core 1.0 Section 7.3).
public struct AuthorizationRequest: Equatable {
    public let responseType: String
    public let scope: [String]
    /// Section 7.2: the client_id is the RP's redirect URI.
    public let clientID: String
    public let nonce: String
    public let state: String?
    public let idTokenHint: String?
    /// Raw JSON of the claims parameter, if any (Section 5.5).
    public let claims: String?
    /// Raw JSON of the registration parameter, if any (Section 7.2.1).
    public let registration: String?

    public init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SIOPError.invalidRequest("malformed URL")
        }
        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            params[item.name] = item.value
        }

        guard let responseType = params["response_type"] else {
            throw SIOPError.invalidRequest("response_type is required")
        }
        guard responseType == "id_token" else {
            throw SIOPError.unsupportedResponseType(responseType)
        }

        let scope = (params["scope"] ?? "").split(separator: " ").map(String.init)
        guard scope.contains("openid") else {
            throw SIOPError.invalidScope
        }

        guard let clientID = params["client_id"], !clientID.isEmpty else {
            throw SIOPError.invalidRequest("client_id is required")
        }
        guard let redirectURL = URL(string: clientID), redirectURL.scheme != nil else {
            throw SIOPError.invalidRequest("client_id must be the RP redirect URI")
        }
        if let redirectURI = params["redirect_uri"], redirectURI != clientID {
            throw SIOPError.invalidRequest("redirect_uri must equal client_id")
        }

        // response_type=id_token is the implicit flow, so nonce is required (Section 3.2.2.1).
        guard let nonce = params["nonce"], !nonce.isEmpty else {
            throw SIOPError.invalidRequest("nonce is required")
        }

        self.responseType = responseType
        self.scope = scope
        self.clientID = clientID
        self.nonce = nonce
        self.state = params["state"]
        self.idTokenHint = params["id_token_hint"]
        self.claims = params["claims"]
        self.registration = params["registration"]
    }
}
