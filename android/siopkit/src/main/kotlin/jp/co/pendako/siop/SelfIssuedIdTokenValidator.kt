package jp.co.pendako.siop

import java.security.Signature
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** RP-side validation of a self-issued ID Token (OpenID Connect Core 1.0 Section 7.5). */
object SelfIssuedIdTokenValidator {
    fun validate(
        idToken: String,
        expectedAudience: String,
        expectedNonce: String? = null,
        nowEpochSeconds: Long = System.currentTimeMillis() / 1000,
    ): JsonObject {
        val jws = Jws.decode(idToken)

        if (jws.header.string("alg") != "RS256") throw SiopError.InvalidToken("unsupported alg")
        // 7.5 rule 2
        if (jws.payload.string("iss") != SelfIssuedIdToken.ISSUER) {
            throw SiopError.InvalidToken("iss must be ${SelfIssuedIdToken.ISSUER}")
        }

        // 7.5 rule 3
        val subJwk = jws.payload["sub_jwk"]?.jsonObject
            ?: throw SiopError.InvalidToken("sub_jwk missing")
        if (subJwk.string("kty") != "RSA") throw SiopError.InvalidToken("sub_jwk is not an RSA key")
        val jwk = RsaPublicJwk(
            n = subJwk.string("n") ?: throw SiopError.InvalidToken("sub_jwk has no n"),
            e = subJwk.string("e") ?: throw SiopError.InvalidToken("sub_jwk has no e"),
        )

        // 7.5 rule 4: binding the identifier to the key is what makes the
        // subject unforgeable without it.
        if (jws.payload.string("sub") != jwk.thumbprint()) {
            throw SiopError.InvalidToken("sub does not match sub_jwk thumbprint")
        }

        val audiences = jws.payload["aud"]?.let { element ->
            runCatching { element.jsonArray.map { it.jsonPrimitive.content } }
                .getOrElse { listOfNotNull(jws.payload.string("aud")) }
        } ?: emptyList()
        if (!audiences.contains(expectedAudience)) throw SiopError.InvalidToken("aud mismatch")

        if (expectedNonce != null && jws.payload.string("nonce") != expectedNonce) {
            throw SiopError.InvalidToken("nonce mismatch")
        }

        val exp = jws.payload.string("exp")?.toLongOrNull()
            ?: throw SiopError.InvalidToken("exp is missing")
        if (nowEpochSeconds >= exp) throw SiopError.InvalidToken("token expired")

        // 7.5 rule 5
        val verified = Signature.getInstance("SHA256withRSA").run {
            initVerify(jwk.toPublicKey())
            update(jws.signingInput)
            verify(jws.signature)
        }
        if (!verified) throw SiopError.InvalidToken("signature verification failed")

        return jws.payload
    }

    private fun JsonObject.string(name: String): String? =
        this[name]?.let { runCatching { it.jsonPrimitive.content }.getOrNull() }
}
