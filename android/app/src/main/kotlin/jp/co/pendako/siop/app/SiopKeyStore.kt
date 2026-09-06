package jp.co.pendako.siop.app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.interfaces.RSAPublicKey
import jp.co.pendako.siop.KeyPairProvider
import jp.co.pendako.siop.SiopKeyProvider
import jp.co.pendako.siop.SiopKeyStore

/**
 * Signing keys held in the Android Keystore, one per RP, so the subject each
 * one sees is stable across launches and different from every other RP's.
 * Private keys never leave the keystore; signing happens inside it.
 */
class AndroidKeystoreKeyStore(private val aliasPrefix: String) : SiopKeyStore {

    override fun existingKeyProvider(clientId: String): SiopKeyProvider? {
        val alias = SiopKeyStore.alias(aliasPrefix, clientId)
        val keyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }
        val existing = keyStore.getEntry(alias, null) as? KeyStore.PrivateKeyEntry ?: return null
        return KeyPairProvider(
            existing.privateKey as PrivateKey,
            existing.certificate.publicKey as RSAPublicKey,
        )
    }

    override fun keyProvider(clientId: String): SiopKeyProvider {
        existingKeyProvider(clientId)?.let { return it }
        val alias = SiopKeyStore.alias(aliasPrefix, clientId)

        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, PROVIDER)
        generator.initialize(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                .setKeySize(2048)
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                .build()
        )
        val keyPair = generator.generateKeyPair()
        return KeyPairProvider(keyPair.private, keyPair.public as RSAPublicKey)
    }

    private companion object {
        const val PROVIDER = "AndroidKeyStore"
    }
}
