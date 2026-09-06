package jp.co.pendako.siop

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
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

class PairwiseSubjectTest {
    private val store = EphemeralKeyStore()

    private fun request(clientId: String) = AuthorizationRequest.parse(
        "openid://?response_type=id_token&scope=openid&nonce=n1&client_id=" +
            java.net.URLEncoder.encode(clientId, "UTF-8")
    )

    /**
     * The advertised subject type is pairwise, so two RPs must not be handed
     * the same identifier — otherwise they can discover they share a user.
     */
    @Test
    fun `different RPs get different subjects`() {
        assertNotEquals(store.subject("https://one.example/cb"), store.subject("https://two.example/cb"))
    }

    /** ...while the same RP must recognise the user on the way back. */
    @Test
    fun `the same RP gets the same subject every time`() {
        assertEquals(store.subject("https://one.example/cb"), store.subject("https://one.example/cb"))
    }

    @Test
    fun `the token carries the subject for its own RP`() {
        val op = SelfIssuedOp(store)
        for (clientId in listOf("https://one.example/cb", "https://two.example/cb")) {
            val response = op.respond(request(clientId))
            val payload = SelfIssuedIdTokenValidator.validate(
                idToken = response.idToken,
                expectedAudience = clientId,
                expectedNonce = "n1",
            )
            assertEquals(op.subject(clientId), payload.getValue("sub").jsonPrimitive.content)
        }
    }

    /**
     * The keystore alias has to be derived from the client_id, or the keys
     * would collide and the subjects with them.
     */
    @Test
    fun `keystore aliases differ per RP`() {
        val one = SiopKeyStore.alias("test", "https://one.example/cb")
        val two = SiopKeyStore.alias("test", "https://two.example/cb")
        assertNotEquals(one, two)
        assertEquals(one, SiopKeyStore.alias("test", "https://one.example/cb"))
        assertTrue(one.startsWith("test."))
    }
}

class SelfIssuedOpTest {
    private val keyStore = EphemeralKeyStore()
    private val requestUrl =
        "openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb" +
            "&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj"

    @Test
    fun `issues a token this implementation can validate`() {
        val response = SelfIssuedOp(keyStore).handle(requestUrl)

        assertEquals("af0ifjsldkj", response.state)
        assertTrue(response.redirectUrl.startsWith("https://client.example.org/cb#id_token="))
        assertTrue(response.redirectUrl.endsWith("&state=af0ifjsldkj"))

        val payload = SelfIssuedIdTokenValidator.validate(
            idToken = response.idToken,
            expectedAudience = "https://client.example.org/cb",
            expectedNonce = "n-0S6_WzA2Mj",
        )
        assertEquals(SelfIssuedIdToken.ISSUER, payload.string("iss"))
        assertEquals(keyStore.subject("https://client.example.org/cb"), payload.string("sub"))
    }

    @Test
    fun `rejects a tampered payload`() {
        val response = SelfIssuedOp(keyStore).handle(requestUrl)
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
        val response = SelfIssuedOp(keyStore).handle(requestUrl, nowEpochSeconds = issuedLongAgo)
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

class MetadataTest {
    /**
     * Advertising a capability that is not implemented sends RPs down a path
     * that always fails, so the two are held together here.
     */
    @Test
    fun `advertises only what is implemented`() {
        val configuration = SelfIssuedMetadata.configuration

        assertEquals(SelfIssuedIdToken.ISSUER, configuration["issuer"])
        assertEquals("openid:", configuration["authorization_endpoint"])
        assertEquals(listOf("id_token"), configuration["response_types_supported"])
        assertEquals(listOf("RS256"), configuration["id_token_signing_alg_values_supported"])

        // request / request_uri are not handled. request_uri_parameter_supported
        // defaults to true when omitted, so it has to be present and false.
        assertNull(configuration["request_object_signing_alg_values_supported"])
        assertEquals(false, configuration["request_parameter_supported"])
        assertEquals(false, configuration["request_uri_parameter_supported"])
    }
}

private fun kotlinx.serialization.json.JsonObject.string(name: String): String =
    getValue(name).jsonPrimitive.content
