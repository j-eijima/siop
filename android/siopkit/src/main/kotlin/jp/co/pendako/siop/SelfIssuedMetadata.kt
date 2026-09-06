package jp.co.pendako.siop

/**
 * Static discovery metadata for Self-Issued OPs (OpenID Connect Core 1.0 Section 7.1).
 *
 * `request` and `request_uri` are not implemented, so the Request Object is
 * turned off explicitly. Omitting the flags would not do it:
 * `request_uri_parameter_supported` defaults to *true* when absent (OpenID
 * Connect Discovery 1.0 Section 3), so silence there advertises a capability
 * this OP does not have.
 */
object SelfIssuedMetadata {
    val configuration: Map<String, Any> = mapOf(
        "authorization_endpoint" to "openid:",
        "issuer" to SelfIssuedIdToken.ISSUER,
        "scopes_supported" to listOf("openid", "profile", "email", "address", "phone"),
        "response_types_supported" to listOf("id_token"),
        "subject_types_supported" to listOf("pairwise"),
        "id_token_signing_alg_values_supported" to listOf("RS256"),
        "request_parameter_supported" to false,
        "request_uri_parameter_supported" to false,
    )
}
