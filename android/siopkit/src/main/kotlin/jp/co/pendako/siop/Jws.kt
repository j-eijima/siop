package jp.co.pendako.siop

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Minimal JWS (RFC 7515) compact serialization with RS256, the signing
 * algorithm a Self-Issued OP must support (OpenID Connect Core 1.0 Section 7.1).
 */
internal object Jws {
    private val json = Json { encodeDefaults = true }

    fun signRs256(payload: JsonObject, key: SiopKeyProvider): String {
        val header = buildJsonObject {
            put("alg", "RS256")
            put("typ", "JWT")
        }
        val signingInput = "${encode(header)}.${encode(payload)}"
        return "$signingInput.${Base64Url.encode(key.sign(signingInput.toByteArray()))}"
    }

    fun decode(jwt: String): DecodedJws {
        val parts = jwt.split(".")
        if (parts.size != 3) throw SiopError.InvalidToken("malformed JWT")
        return try {
            DecodedJws(
                header = json.parseToJsonElement(String(Base64Url.decode(parts[0]))) as JsonObject,
                payload = json.parseToJsonElement(String(Base64Url.decode(parts[1]))) as JsonObject,
                signature = Base64Url.decode(parts[2]),
                signingInput = "${parts[0]}.${parts[1]}".toByteArray(),
            )
        } catch (cause: Exception) {
            throw SiopError.InvalidToken("malformed JWT")
        }
    }

    private fun encode(value: JsonObject): String =
        Base64Url.encode(json.encodeToString(JsonObject.serializer(), value).toByteArray())
}

internal class DecodedJws(
    val header: JsonObject,
    val payload: JsonObject,
    val signature: ByteArray,
    val signingInput: ByteArray,
)
