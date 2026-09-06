package jp.co.pendako.siop

import java.security.MessageDigest

/**
 * Resolves the key that identifies this device to one particular RP.
 *
 * A Self-Issued OP advertises `subject_types_supported: ["pairwise"]`, and the
 * subject is the thumbprint of the key that signed the token. Presenting one
 * key to everyone would therefore hand every RP the same identifier, letting
 * any two of them discover they are talking to the same person. A separate key
 * per RP is what makes the advertised pairwise subject true.
 */
interface SiopKeyStore {
    /**
     * The same [clientId] must return the same key every time, so that a user
     * returning to an RP is recognised as the same subject. Creates one on
     * first use, so only call it once the user has agreed to answer this RP.
     */
    fun keyProvider(clientId: String): SiopKeyProvider

    /**
     * The key already held for [clientId], or null if none has been made yet.
     *
     * Creating a key costs an RSA generation and a permanent keystore entry,
     * and `client_id` is chosen by whoever sent the request. Anything that runs
     * before the user has agreed — showing a consent screen, say — must go
     * through here, or a stream of unanswered requests would fill the keystore
     * and stall on key generation.
     */
    fun existingKeyProvider(clientId: String): SiopKeyProvider?

    /**
     * The identifier this device presents to [clientId], creating the key if
     * this RP has not been answered before.
     */
    fun subject(clientId: String): String = keyProvider(clientId).publicJwk().thumbprint()

    /**
     * The identifier already established with [clientId], or null if this RP
     * has never been answered. Creates nothing.
     */
    fun existingSubject(clientId: String): String? =
        existingKeyProvider(clientId)?.publicJwk()?.thumbprint()

    companion object {
        /**
         * SIOP has no registration, so the `client_id` — the RP's redirect URI
         * — is the only stable name an RP has. It is hashed rather than
         * embedded so that the alias is a fixed size and free of URI
         * punctuation.
         */
        fun alias(prefix: String, clientId: String): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(clientId.toByteArray())
            return "$prefix.${Base64Url.encode(digest)}"
        }
    }
}

/**
 * Keys kept in memory only, one per RP. For tests and tools, where nothing
 * should outlive the process.
 */
class EphemeralKeyStore : SiopKeyStore {
    private val providers = mutableMapOf<String, SiopKeyProvider>()

    override fun keyProvider(clientId: String): SiopKeyProvider =
        providers.getOrPut(clientId) { KeyPairProvider.generate() }

    override fun existingKeyProvider(clientId: String): SiopKeyProvider? = providers[clientId]
}
