package jp.co.pendako.siop

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/**
 * Verifies a token the Swift implementation signed, using this one.
 *
 * An implementation that both issues and checks its own tokens can be
 * self-consistently wrong, so the same fixture that `rp/` verifies in
 * JavaScript is verified here in Kotlin. It is committed rather than produced
 * on the fly, so this suite needs no Swift toolchain. Refresh it with
 * `rp/test/fixtures/regenerate.sh`.
 */
class CrossImplementationTest {
    private val fixture: JsonObject = Json.parseToJsonElement(
        checkNotNull(javaClass.getResourceAsStream("/swift-issued.json")) {
            "swift-issued.json is missing from the test resources"
        }.reader().readText()
    ) as JsonObject

    private val idToken = fixture.string("id_token")
    private val expectedSubject = fixture.string("sub")
    private val audience = "http://localhost:8080/callback.html"
    private val nonce = "n-0S6_WzA2Mj"

    /** The fixture has a fixed lifetime, so judge it at a fixed instant. */
    private val validAt: Long
        get() = claimsOf(idToken).string("iat").toLong() + 1

    @Test
    fun `a token signed by Swift passes every check`() {
        val payload = SelfIssuedIdTokenValidator.validate(
            idToken = idToken,
            expectedAudience = audience,
            expectedNonce = nonce,
            nowEpochSeconds = validAt,
        )
        assertEquals(SelfIssuedIdToken.ISSUER, payload.string("iss"))
        // Both implementations must derive the same subject from the same key.
        assertEquals(expectedSubject, payload.string("sub"))
    }

    @Test
    fun `both implementations derive the same thumbprint from sub_jwk`() {
        val subJwk = claimsOf(idToken)["sub_jwk"] as JsonObject
        val jwk = RsaPublicJwk(n = subJwk.string("n"), e = subJwk.string("e"))
        assertEquals(expectedSubject, jwk.thumbprint())
    }

    @Test
    fun `a token addressed to another RP is rejected`() {
        val error = assertFailsWith<SiopError.InvalidToken> {
            SelfIssuedIdTokenValidator.validate(
                idToken = idToken,
                expectedAudience = "https://other.example/cb",
                nowEpochSeconds = validAt,
            )
        }
        assertEquals("aud mismatch", error.reason)
    }

    @Test
    fun `a mismatched nonce is rejected`() {
        val error = assertFailsWith<SiopError.InvalidToken> {
            SelfIssuedIdTokenValidator.validate(
                idToken = idToken,
                expectedAudience = audience,
                expectedNonce = "another-nonce",
                nowEpochSeconds = validAt,
            )
        }
        assertEquals("nonce mismatch", error.reason)
    }

    @Test
    fun `rewriting sub breaks the thumbprint check`() {
        val tampered = reencode(idToken) { payload ->
            payload.replace(
                """"sub":"$expectedSubject"""",
                """"sub":"NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs"""",
            )
        }
        val error = assertFailsWith<SiopError.InvalidToken> {
            SelfIssuedIdTokenValidator.validate(
                idToken = tampered,
                expectedAudience = audience,
                nowEpochSeconds = validAt,
            )
        }
        assertEquals("sub does not match sub_jwk thumbprint", error.reason)
    }

    @Test
    fun `the fixture is rejected once it has expired`() {
        val error = assertFailsWith<SiopError.InvalidToken> {
            SelfIssuedIdTokenValidator.validate(
                idToken = idToken,
                expectedAudience = audience,
                nowEpochSeconds = claimsOf(idToken).string("exp").toLong() + 1,
            )
        }
        assertEquals("token expired", error.reason)
    }

    private fun claimsOf(token: String): JsonObject =
        Json.parseToJsonElement(String(Base64Url.decode(token.split(".")[1]))) as JsonObject

    private fun reencode(token: String, mutate: (String) -> String): String {
        val parts = token.split(".").toMutableList()
        parts[1] = Base64Url.encode(mutate(String(Base64Url.decode(parts[1]))).toByteArray())
        return parts.joinToString(".")
    }

    private fun JsonObject.string(name: String): String = getValue(name).jsonPrimitive.content
}
