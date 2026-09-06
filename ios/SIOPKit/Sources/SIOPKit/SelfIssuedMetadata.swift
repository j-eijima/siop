import Foundation

/// Static discovery metadata for Self-Issued OPs (OpenID Connect Core 1.0 Section 7.1).
///
/// `request` and `request_uri` are not implemented, so the Request Object is
/// turned off explicitly. Omitting the flags would not do it:
/// `request_uri_parameter_supported` defaults to *true* when absent (OpenID
/// Connect Discovery 1.0 Section 3), so silence there advertises a capability
/// this OP does not have.
public enum SelfIssuedMetadata {
    public static let configuration: [String: Any] = [
        "authorization_endpoint": "openid:",
        "issuer": "https://self-issued.me",
        "scopes_supported": ["openid", "profile", "email", "address", "phone"],
        "response_types_supported": ["id_token"],
        "subject_types_supported": ["pairwise"],
        "id_token_signing_alg_values_supported": ["RS256"],
        "request_parameter_supported": false,
        "request_uri_parameter_supported": false,
    ]
}
