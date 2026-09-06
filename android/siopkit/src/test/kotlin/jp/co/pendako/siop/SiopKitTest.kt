package jp.co.pendako.siop

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class Base64UrlTest {
    @Test
    fun `encodes with the URL-safe alphabet and no padding`() {
        assertEquals("-_--AA", Base64Url.encode(byteArrayOf(-5, -1, -66, 0)))
    }

    @Test
    fun `decodes without padding`() {
        assertContentEquals(byteArrayOf(-5, -1, -66, 0), Base64Url.decode("-_--AA"))
    }
}

class ThumbprintTest {
    @Test
    fun `matches the RFC 7638 example`() {
        val jwk = RsaPublicJwk(
            n = "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6t" +
                "Soc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-6" +
                "5YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLy" +
                "rdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJz" +
                "KnqDKgw",
            e = "AQAB",
        )
        assertEquals("NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs", jwk.thumbprint())
    }
}

class AuthorizationRequestTest {
    private val valid =
        "openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb" +
            "&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj"

    @Test
    fun `parses a valid request`() {
        val request = AuthorizationRequest.parse(valid)
        assertEquals("id_token", request.responseType)
        assertEquals(listOf("openid", "profile"), request.scope)
        assertEquals("https://client.example.org/cb", request.clientId)
        assertEquals("n-0S6_WzA2Mj", request.nonce)
        assertEquals("af0ifjsldkj", request.state)
    }

    @Test
    fun `rejects a scope without openid`() {
        assertFailsWith<SiopError.InvalidScope> {
            AuthorizationRequest.parse(
                "openid://?response_type=id_token&client_id=https%3A%2F%2Fc.example%2Fcb&scope=profile&nonce=n1"
            )
        }
    }

    @Test
    fun `rejects an unsupported response_type`() {
        val error = assertFailsWith<SiopError.UnsupportedResponseType> {
            AuthorizationRequest.parse(
                "openid://?response_type=code&client_id=https%3A%2F%2Fc.example%2Fcb&scope=openid&nonce=n1"
            )
        }
        assertEquals("code", error.responseType)
    }

    @Test
    fun `rejects a missing nonce`() {
        assertFailsWith<SiopError.InvalidRequest> {
            AuthorizationRequest.parse(
                "openid://?response_type=id_token&client_id=https%3A%2F%2Fc.example%2Fcb&scope=openid"
            )
        }
    }

    @Test
    fun `rejects a redirect_uri that differs from client_id`() {
        assertFailsWith<SiopError.InvalidRequest> {
            AuthorizationRequest.parse(
                "openid://?response_type=id_token&client_id=https%3A%2F%2Fc.example%2Fcb" +
                    "&redirect_uri=https%3A%2F%2Fevil.example%2Fcb&scope=openid&nonce=n1"
            )
        }
    }
}

class SelfIssuedOpTest {
    private val keyProvider = KeyPairProvider.generate()
    private val requestUrl =
        "openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb" +
            "&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj"

    @Test
    fun `issues a token this implementation can validate`() {
        val response = SelfIssuedOp(keyProvider).handle(requestUrl)

        assertEquals("af0ifjsldkj", response.state)
        assertTrue(response.redirectUrl.startsWith("https://client.example.org/cb#id_token="))
        assertTrue(response.redirectUrl.endsWith("&state=af0ifjsldkj"))

        val payload = SelfIssuedIdTokenValidator.validate(
            idToken = response.idToken,
            expectedAudience = "https://client.example.org/cb",
            expectedNonce = "n-0S6_WzA2Mj",
        )
        assertEquals(SelfIssuedIdToken.ISSUER, payload.string("iss"))
        assertEquals(keyProvider.publicJwk().thumbprint(), payload.string("sub"))
    }

    @Test
    fun `rejects a tampered payload`() {
        val response = SelfIssuedOp(keyProvider).handle(requestUrl)
        val parts = response.idToken.split(".").toMutableList()
        val payload = String(Base64Url.decode(parts[1]))
            .replace("https://client.example.org/cb", "https://attacker.example/cb")
        parts[1] = Base64Url.encode(payload.toByteArray())

        val error = assertFailsWith<SiopError.InvalidToken> {
            SelfIssuedIdTokenValidator.validate(
                idToken = parts.joinToString("."),
                expectedAudience = "https://attacker.example/cb",
            )
        }
        assertEquals("signature verification failed", error.reason)
    }

    @Test
    fun `rejects an expired token`() {
        val issuedLongAgo = System.currentTimeMillis() / 1000 - 3600
        val response = SelfIssuedOp(keyProvider).handle(requestUrl, nowEpochSeconds = issuedLongAgo)
        val error = assertFailsWith<SiopError.InvalidToken> {
            SelfIssuedIdTokenValidator.validate(
                idToken = response.idToken,
                expectedAudience = "https://client.example.org/cb",
            )
        }
        assertEquals("token expired", error.reason)
    }

    @Test
    fun `refusal returns access_denied to the RP`() {
        val request = AuthorizationRequest.parse(requestUrl)
        val response = AuthenticationErrorResponse(request)
        assertEquals(
            "https://client.example.org/cb#error=access_denied&state=af0ifjsldkj",
            response.redirectUrl,
        )
    }
}

private fun kotlinx.serialization.json.JsonObject.string(name: String): String =
    getValue(name).jsonPrimitive.content
