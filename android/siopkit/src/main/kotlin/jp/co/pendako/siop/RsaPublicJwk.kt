package jp.co.pendako.siop

import java.math.BigInteger
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.PublicKey
import java.security.interfaces.RSAPublicKey
import java.security.spec.RSAPublicKeySpec

/** RSA public key as a JWK (RFC 7517), as carried in the `sub_jwk` claim. */
data class RsaPublicJwk(val n: String, val e: String) {
    val kty: String get() = "RSA"

    /**
     * JWK thumbprint (RFC 7638): SHA-256 over the canonical JSON of the
     * required members in lexicographic order. This is the `sub` of a
     * self-issued ID Token (OpenID Connect Core 1.0 Section 7.4).
     */
    fun thumbprint(): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(canonicalJson.toByteArray())
        return Base64Url.encode(digest)
    }

    /** The JSON the thumbprint is taken over: the required members, in order, with no whitespace. */
    val canonicalJson: String get() = """{"e":"$e","kty":"$kty","n":"$n"}"""

    fun toJsonObject(): Map<String, String> = mapOf("kty" to kty, "n" to n, "e" to e)

    fun toPublicKey(): PublicKey {
        val modulus = BigInteger(1, Base64Url.decode(n))
        val exponent = BigInteger(1, Base64Url.decode(e))
        return KeyFactory.getInstance("RSA").generatePublic(RSAPublicKeySpec(modulus, exponent))
    }

    companion object {
        fun from(key: RSAPublicKey): RsaPublicJwk = RsaPublicJwk(
            n = Base64Url.encode(key.modulus.toUnsignedBytes()),
            e = Base64Url.encode(key.publicExponent.toUnsignedBytes()),
        )

        /** Big-endian magnitude without the sign byte BigInteger prepends. */
        private fun BigInteger.toUnsignedBytes(): ByteArray {
            val bytes = toByteArray()
            return if (bytes.size > 1 && bytes[0] == 0.toByte()) bytes.copyOfRange(1, bytes.size) else bytes
        }
    }
}
