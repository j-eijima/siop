import Foundation

/// Self-Issued ID Token issuance (OpenID Connect Core 1.0 Section 7.4).
public enum SelfIssuedIDToken {
    /// Section 7.4: the issuer of a self-issued ID Token.
    public static let issuer = "https://self-issued.me"

    /// How long an issued token stays valid, unless the caller says otherwise.
    public static let lifetime: TimeInterval = 600

    public static func issue(
        for request: AuthorizationRequest,
        key: SIOPKeyProvider,
        expiresIn: TimeInterval = lifetime,
        now: Date = Date()
    ) throws -> String {
        let jwk = try key.publicJWK()
        let claims: [String: Any] = [
            "iss": issuer,
            "sub": jwk.thumbprint(),
            "sub_jwk": jwk.jsonObject,
            "aud": request.clientID,
            "nonce": request.nonce,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(expiresIn).timeIntervalSince1970),
        ]
        return try JWS.signRS256(payload: claims, key: key)
    }
}
