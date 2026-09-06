package jp.co.pendako.siop

/** Static discovery metadata for Self-Issued OPs (OpenID Connect Core 1.0 Section 7.1). */
object SelfIssuedMetadata {
    val configuration: Map<String, Any> = mapOf(
        "authorization_endpoint" to "openid:",
        "issuer" to SelfIssuedIdToken.ISSUER,
        "scopes_supported" to listOf("openid", "profile", "email", "address", "phone"),
        "response_types_supported" to listOf("id_token"),
        "subject_types_supported" to listOf("pairwise"),
        "id_token_signing_alg_values_supported" to listOf("RS256"),
        "request_object_signing_alg_values_supported" to listOf("none", "RS256"),
    )
}
