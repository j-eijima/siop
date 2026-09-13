package jp.co.pendako.siop.app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.ProviderException
import java.security.interfaces.RSAPublicKey
import jp.co.pendako.siop.KeyPairProvider
import jp.co.pendako.siop.SiopError
import jp.co.pendako.siop.SiopIdentity
import jp.co.pendako.siop.SiopIdentityKeys
import jp.co.pendako.siop.SiopIdentityRecordFormat
import jp.co.pendako.siop.SiopIdentityRecords
import jp.co.pendako.siop.SiopKeyProvider

/**
 * Private keys in the Android Keystore, by alias. They never leave it:
 * signing happens inside the keystore.
 */
class AndroidKeystoreIdentityKeys : SiopIdentityKeys {

    override fun key(alias: String): SiopKeyProvider? = guarded {
        val entry = keyStore().getEntry(alias, null) ?: return@guarded null
        val signing = entry as? KeyStore.PrivateKeyEntry
            ?: throw SiopError.InvalidKey("$alias is not a signing key")
        KeyPairProvider(signing.privateKey, signing.certificate.publicKey as RSAPublicKey)
    }

    override fun createKey(alias: String): SiopKeyProvider = guarded {
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, PROVIDER)
        generator.initialize(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                .setKeySize(2048)
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                .build()
        )
        val pair = generator.generateKeyPair()
        KeyPairProvider(pair.private, pair.public as RSAPublicKey)
    }

    override fun removeKey(alias: String) = guarded { keyStore().deleteEntry(alias) }

    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    /** The keystore's own failures, as the error the rest of the app knows. */
    private inline fun <T> guarded(block: () -> T): T = try {
        block()
    } catch (cause: GeneralSecurityException) {
        throw SiopError.Storage(cause.toString())
    } catch (cause: ProviderException) {
        throw SiopError.Storage(cause.toString())
    } catch (cause: IOException) {
        throw SiopError.Storage(cause.toString())
    }

    private companion object {
        const val PROVIDER = "AndroidKeyStore"
    }
}

/**
 * Identity records as JSON files, one per identity.
 *
 * Kept where nothing is backed up (`Context.noBackupFilesDir`): the keys they
 * describe cannot leave the Android Keystore, so a record restored without
 * its key would list an identity that can never answer. Records and keys go
 * together when the app is removed.
 */
class FileIdentityRecords(private val directory: File) : SiopIdentityRecords {

    override fun loadAll(): List<SiopIdentity> {
        if (!directory.exists()) return emptyList()
        val files = directory.listFiles { file -> file.name.endsWith(SUFFIX) }
            ?: throw SiopError.Storage("cannot list $directory")
        val texts = files.map { file ->
            try {
                file.readText()
            } catch (cause: IOException) {
                throw SiopError.Storage(cause.toString())
            }
        }
        return SiopIdentityRecordFormat.decode(texts)
    }

    override fun save(identity: SiopIdentity) {
        if (!directory.isDirectory && !directory.mkdirs()) throw SiopError.Storage("cannot create $directory")
        // Written beside the record and renamed over it, so a record is never
        // left half written.
        val target = File(directory, identity.id + SUFFIX)
        val partial = File(directory, identity.id + SUFFIX + ".partial")
        try {
            partial.writeText(SiopIdentityRecordFormat.encode(identity))
        } catch (cause: IOException) {
            throw SiopError.Storage(cause.toString())
        }
        if (!partial.renameTo(target)) throw SiopError.Storage("cannot write $target")
    }

    override fun remove(id: String) {
        val file = File(directory, id + SUFFIX)
        if (file.exists() && !file.delete()) throw SiopError.Storage("cannot delete $file")
    }

    private companion object {
        const val SUFFIX = ".json"
    }
}
