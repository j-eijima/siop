package jp.co.pendako.siop

import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.RSAPublicKey

/** The OP's key pair: RS256 signing and the public key as a JWK. */
interface SiopKeyProvider {
    fun publicJwk(): RsaPublicJwk
    fun sign(data: ByteArray): ByteArray
}

/**
 * Key provider backed by a JCA key pair.
 *
 * On Android, pass a key pair held in the Android Keystore so that `sub` stays
 * stable across launches; [generate] produces an ephemeral one for tests.
 */
class KeyPairProvider(private val privateKey: PrivateKey, publicKey: RSAPublicKey) : SiopKeyProvider {
    private val jwk = RsaPublicJwk.from(publicKey)

    constructor(keyPair: KeyPair) : this(keyPair.private, keyPair.public as RSAPublicKey)

    override fun publicJwk(): RsaPublicJwk = jwk

    override fun sign(data: ByteArray): ByteArray =
        Signature.getInstance("SHA256withRSA").run {
            initSign(privateKey)
            update(data)
            sign()
        }

    companion object {
        fun generate(bits: Int = 2048): KeyPairProvider {
            val generator = KeyPairGenerator.getInstance("RSA").apply { initialize(bits) }
            return KeyPairProvider(generator.generateKeyPair())
        }
    }
}
