package jp.co.pendako.siop

import java.net.URI

/** Self-Issued OpenID Provider Request (OpenID Connect Core 1.0 Section 7.3). */
data class AuthorizationRequest(
    val responseType: String,
    val scope: List<String>,
    /** Section 7.2: the client_id is the RP's redirect URI. */
    val clientId: String,
    val nonce: String,
    val state: String?,
    val idTokenHint: String?,
    /** Raw JSON of the claims parameter, if any (Section 5.5). */
    val claims: String?,
    /** Raw JSON of the registration parameter, if any (Section 7.2.1). */
    val registration: String?,
) {
    companion object {
        fun parse(url: String): AuthorizationRequest {
            val params = queryParameters(url)

            val responseType = params["response_type"]
                ?: throw SiopError.InvalidRequest("response_type is required")
            if (responseType != "id_token") throw SiopError.UnsupportedResponseType(responseType)

            val scope = (params["scope"] ?: "").split(" ").filter { it.isNotEmpty() }
            if (!scope.contains("openid")) throw SiopError.InvalidScope()

            val clientId = params["client_id"]?.takeIf { it.isNotEmpty() }
                ?: throw SiopError.InvalidRequest("client_id is required")
            runCatching { URI(clientId) }.getOrNull()?.scheme
                ?: throw SiopError.InvalidRequest("client_id must be the RP redirect URI")
            params["redirect_uri"]?.let {
                if (it != clientId) throw SiopError.InvalidRequest("redirect_uri must equal client_id")
            }

            // response_type=id_token is the implicit flow, so nonce is required
            // (Section 3.2.2.1).
            val nonce = params["nonce"]?.takeIf { it.isNotEmpty() }
                ?: throw SiopError.InvalidRequest("nonce is required")

            return AuthorizationRequest(
                responseType = responseType,
                scope = scope,
                clientId = clientId,
                nonce = nonce,
                state = params["state"],
                idTokenHint = params["id_token_hint"],
                claims = params["claims"],
                registration = params["registration"],
            )
        }

        private fun queryParameters(url: String): Map<String, String> {
            val query = url.substringAfter('?', "").substringBefore('#')
            if (query.isEmpty()) throw SiopError.InvalidRequest("no query parameters")
            return query.split("&").mapNotNull { pair ->
                if (pair.isEmpty()) return@mapNotNull null
                val name = pair.substringBefore('=')
                val value = pair.substringAfter('=', "")
                name.percentDecoded() to value.percentDecoded()
            }.toMap()
        }

        private fun String.percentDecoded(): String =
            java.net.URLDecoder.decode(this, Charsets.UTF_8)
    }
}
