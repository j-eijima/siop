package jp.co.pendako.siop.app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.interfaces.RSAPublicKey
import jp.co.pendako.siop.KeyPairProvider

/**
 * The device's signing key, held in the Android Keystore so that the `sub` it
 * produces is the same on every launch. The private key never leaves the
 * keystore; signing happens inside it.
 */
object SiopKeyStore {
    private const val PROVIDER = "AndroidKeyStore"
    private const val ALIAS = "jp.co.pendako.siop.key"

    fun loadOrCreate(): KeyPairProvider {
        val keyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

        val existing = keyStore.getEntry(ALIAS, null) as? KeyStore.PrivateKeyEntry
        if (existing != null) {
            return KeyPairProvider(
                existing.privateKey as PrivateKey,
                existing.certificate.publicKey as RSAPublicKey,
            )
        }

        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, PROVIDER)
        generator.initialize(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                .setKeySize(2048)
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                .build()
        )
        val keyPair = generator.generateKeyPair()
        return KeyPairProvider(keyPair.private, keyPair.public as RSAPublicKey)
    }
}
