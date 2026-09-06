package jp.co.pendako.siop

import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/** Self-Issued ID Token issuance (OpenID Connect Core 1.0 Section 7.4). */
object SelfIssuedIdToken {
    /** Section 7.4: the issuer of a self-issued ID Token. */
    const val ISSUER = "https://self-issued.me"

    fun issue(
        request: AuthorizationRequest,
        key: SiopKeyProvider,
        expiresInSeconds: Long = 600,
        nowEpochSeconds: Long = System.currentTimeMillis() / 1000,
    ): String {
        val jwk = key.publicJwk()
        val claims = buildJsonObject {
            put("iss", ISSUER)
            put("sub", jwk.thumbprint())
            putJsonObject("sub_jwk") {
                jwk.toJsonObject().forEach { (name, value) -> put(name, value) }
            }
            put("aud", request.clientId)
            put("nonce", request.nonce)
            put("iat", nowEpochSeconds)
            put("exp", nowEpochSeconds + expiresInSeconds)
        }
        return Jws.signRs256(claims, key)
    }
}
