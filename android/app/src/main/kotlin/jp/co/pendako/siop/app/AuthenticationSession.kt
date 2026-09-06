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
        /** The response was built but could not be delivered to the RP. */
        data class Undeliverable(val clientId: String, val redirectUrl: String) : Phase
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

    /**
     * Issues the token and hands the response to [deliver], which reports
     * whether the redirect URI could actually be opened.
     *
     * The phase only becomes [Phase.Sent] once delivery succeeded: a
     * `client_id` naming a scheme no installed app handles is a valid request
     * by Section 7.2, so failing to reach the RP is an expected outcome, not
     * an impossible one.
     */
    fun approve(request: AuthorizationRequest, deliver: (String) -> Boolean) {
        val op = op ?: run {
            phase = Phase.Failed("鍵が利用できません")
            return
        }
        val redirectUrl = try {
            op.respond(request).redirectUrl
        } catch (cause: Exception) {
            phase = Phase.Failed(describe(cause))
            return
        }
        phase = if (deliver(redirectUrl)) {
            Phase.Sent(request.clientId, redirectUrl)
        } else {
            Phase.Undeliverable(request.clientId, redirectUrl)
        }
    }

    /** Section 3.1.2.6: tell the RP the user declined rather than leaving it waiting. */
    fun decline(request: AuthorizationRequest, deliver: (String) -> Boolean) {
        val redirectUrl = AuthenticationErrorResponse(request).redirectUrl
        phase = if (deliver(redirectUrl)) {
            Phase.Declined(request.clientId)
        } else {
            Phase.Undeliverable(request.clientId, redirectUrl)
        }
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
