package jp.co.pendako.siop.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import jp.co.pendako.siop.AuthenticationErrorResponse
import jp.co.pendako.siop.AuthorizationRequest
import jp.co.pendako.siop.KeyPairProvider
import jp.co.pendako.siop.RsaPublicJwk
import jp.co.pendako.siop.SelfIssuedOp
import jp.co.pendako.siop.SiopError

/**
 * Drives one authentication request from arrival through consent to the
 * response handed back to the RP (OpenID Connect Core 1.0 Sections 7.3-7.4).
 */
class AuthenticationSession(keyProvider: KeyPairProvider?, keyFailure: String? = null) {

    sealed interface Phase {
        data object Idle : Phase
        data class Consent(val request: AuthorizationRequest) : Phase
        data class Sent(val clientId: String, val redirectUrl: String) : Phase
        data class Declined(val clientId: String) : Phase
        data class Failed(val message: String) : Phase
    }

    /** The self-issued identity this device presents to every RP. */
    data class Identity(val subject: String, val jwk: RsaPublicJwk)

    var phase: Phase by mutableStateOf(
        if (keyFailure != null) Phase.Failed("鍵を準備できませんでした: $keyFailure") else Phase.Idle
    )
        private set

    val identity: Identity? = keyProvider?.publicJwk()?.let { Identity(it.thumbprint(), it) }

    private val op = keyProvider?.let { SelfIssuedOp(it) }

    fun receive(url: String) {
        phase = try {
            Phase.Consent(AuthorizationRequest.parse(url))
        } catch (cause: Exception) {
            Phase.Failed(describe(cause))
        }
    }

    /** Returns the URL to open so the RP receives the response, or null on failure. */
    fun approve(request: AuthorizationRequest): String? {
        val op = op ?: run {
            phase = Phase.Failed("鍵が利用できません")
            return null
        }
        return try {
            val response = op.respond(request)
            phase = Phase.Sent(request.clientId, response.redirectUrl)
            response.redirectUrl
        } catch (cause: Exception) {
            phase = Phase.Failed(describe(cause))
            null
        }
    }

    /** Section 3.1.2.6: tell the RP the user declined rather than leaving it waiting. */
    fun decline(request: AuthorizationRequest): String {
        phase = Phase.Declined(request.clientId)
        return AuthenticationErrorResponse(request).redirectUrl
    }

    fun reset() {
        if (identity != null) phase = Phase.Idle
    }

    private fun describe(cause: Exception): String = when (cause) {
        is SiopError.InvalidRequest -> "リクエストが不正です: ${cause.reason}"
        is SiopError.UnsupportedResponseType -> "未対応の response_type です: ${cause.responseType}"
        is SiopError.InvalidScope -> "scope に openid が含まれていません"
        is SiopError.InvalidKey -> "鍵が不正です: ${cause.reason}"
        is SiopError.InvalidToken -> "ID Token が不正です: ${cause.reason}"
        else -> cause.toString()
    }
}
