import Foundation

/// Static discovery metadata for Self-Issued OPs (OpenID Connect Core 1.0 Section 7.1).
public enum SelfIssuedMetadata {
    public static let configuration: [String: Any] = [
        "authorization_endpoint": "openid:",
        "issuer": "https://self-issued.me",
        "scopes_supported": ["openid", "profile", "email", "address", "phone"],
        "response_types_supported": ["id_token"],
        "subject_types_supported": ["pairwise"],
        "id_token_signing_alg_values_supported": ["RS256"],
        "request_object_signing_alg_values_supported": ["none", "RS256"],
    ]
}
