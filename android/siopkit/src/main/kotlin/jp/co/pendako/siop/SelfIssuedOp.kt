package jp.co.pendako.siop

/** Self-Issued OpenID Provider (OpenID Connect Core 1.0 Section 7). */
class SelfIssuedOp(private val keyProvider: SiopKeyProvider) {

    /** Parses a request URL and produces the response for the RP (Section 7.4). */
    fun handle(
        url: String,
        nowEpochSeconds: Long = System.currentTimeMillis() / 1000,
    ): AuthenticationResponse = respond(AuthorizationRequest.parse(url), nowEpochSeconds)

    /** Issues for an already-parsed request, e.g. after the user has consented. */
    fun respond(
        request: AuthorizationRequest,
        nowEpochSeconds: Long = System.currentTimeMillis() / 1000,
    ): AuthenticationResponse {
        val idToken = SelfIssuedIdToken.issue(request, keyProvider, nowEpochSeconds = nowEpochSeconds)
        return AuthenticationResponse(idToken, request.state, request.clientId)
    }
}

/** Self-Issued OpenID Provider Response (Section 7.4). */
class AuthenticationResponse(val idToken: String, val state: String?, redirectUri: String) {
    /** The redirect URI with the response in the fragment, as the implicit flow requires. */
    val redirectUrl: String = RedirectBuilder.build(
        redirectUri,
        buildList {
            add("id_token" to idToken)
            state?.let { add("state" to it) }
        },
    )
}

/**
 * Error response delivered to the RP's redirect URI (Section 3.1.2.6), such as
 * `access_denied` when the user declines.
 */
class AuthenticationErrorResponse(
    request: AuthorizationRequest,
    val error: String = "access_denied",
    val errorDescription: String? = null,
) {
    val state: String? = request.state
    val redirectUrl: String = RedirectBuilder.build(
        request.clientId,
        buildList {
            add("error" to error)
            errorDescription?.let { add("error_description" to it) }
            request.state?.let { add("state" to it) }
        },
    )
}

internal object RedirectBuilder {
    /** RFC 3986 unreserved characters; everything else is percent-encoded. */
    private val UNRESERVED =
        ('A'..'Z').toSet() + ('a'..'z').toSet() + ('0'..'9').toSet() + setOf('-', '.', '_', '~')

    fun build(redirectUri: String, parameters: List<Pair<String, String>>): String {
        val fragment = parameters.joinToString("&") { (name, value) -> "$name=${value.encoded()}" }
        return "${redirectUri.substringBefore('#')}#$fragment"
    }

    private fun String.encoded(): String = buildString {
        for (byte in this@encoded.toByteArray()) {
            val char = byte.toInt().toChar()
            if (char in UNRESERVED) append(char) else append("%%%02X".format(byte))
        }
    }
}
