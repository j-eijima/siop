package jp.co.pendako.siop

import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * A key the user holds for one Relying Party, with the names they gave it.
 *
 * The subject an RP sees is the thumbprint of the key that signs for it, so an
 * identity is really a key. It belongs to exactly one RP: answering a second
 * RP with it would hand both the same subject and let them discover they are
 * talking to the same person. One RP may have several — the user can answer
 * it as more than one person — but no identity ever answers two
 * (docs/decisions/0011).
 */
@Serializable
data class SiopIdentity(
    val id: String,
    /** The RP this identity answers. Section 7.2: its redirect URI. */
    val clientId: String,
    /** Names for the user's own benefit. Never sent to the RP. */
    val label: String,
    val note: String,
    val createdAtEpochMillis: Long,
    val lastUsedAtEpochMillis: Long? = null,
    /** Where the private key lives. Not the subject, which comes from the key itself. */
    val keyAlias: String,
) {
    companion object {
        /**
         * The order an RP's identities are offered in. The one used most
         * recently comes first, being the one the user answered as last time;
         * identities never used follow, oldest first.
         */
        val PREFERRED: Comparator<SiopIdentity> = Comparator { a, b ->
            val x = a.lastUsedAtEpochMillis
            val y = b.lastUsedAtEpochMillis
            when {
                x != null && y != null -> y.compareTo(x)
                x != null -> -1
                y != null -> 1
                else -> a.createdAtEpochMillis.compareTo(b.createdAtEpochMillis)
            }
        }
    }
}

/** Where identity records — names, and which RP each answers — are kept. */
interface SiopIdentityRecords {
    fun loadAll(): List<SiopIdentity>
    fun save(identity: SiopIdentity)
    fun remove(id: String)
}

/** Where private keys are kept, by alias. */
interface SiopIdentityKeys {
    fun key(alias: String): SiopKeyProvider?
    fun createKey(alias: String): SiopKeyProvider
    fun removeKey(alias: String)
}

/** The identities on this device, and the keys behind them. */
class SiopIdentityStore(
    private val records: SiopIdentityRecords,
    private val keys: SiopIdentityKeys,
    private val aliasPrefix: String,
    /**
     * Whether keys made by a [SiopKeyStore] under the same [aliasPrefix] are
     * taken over as identities. Devices that ran the key-per-RP version hold
     * one for every RP they answered, and those RPs already know the subject
     * it produces.
     */
    private val adoptsPerRpKeys: Boolean = false,
    private val now: () -> Long = System::currentTimeMillis,
) {
    fun allIdentities(): List<SiopIdentity> = records.loadAll().sortedWith(SiopIdentity.PREFERRED)

    /**
     * The identities held for [clientId], in the order they should be offered.
     *
     * Creates no key, so it is safe to call as soon as a request arrives. It
     * may write a record, when a key from the key-per-RP version is found for
     * this RP and taken over.
     */
    fun identitiesFor(clientId: String): List<SiopIdentity> {
        val held = records.loadAll().filter { it.clientId == clientId }.toMutableList()
        if (adoptsPerRpKeys) adoptPerRpKey(clientId, held)?.let(held::add)
        return held.sortedWith(SiopIdentity.PREFERRED)
    }

    /**
     * Generates a key for [clientId].
     *
     * That costs an RSA generation and a permanent keystore entry, and
     * `client_id` is chosen by whoever sent the request. Call it only on the
     * user's explicit request — never because a request arrived.
     */
    fun createIdentity(clientId: String, label: String = "", note: String = ""): SiopIdentity {
        val alias = "$aliasPrefix.${UUID.randomUUID()}"
        keys.createKey(alias)
        val identity = SiopIdentity(
            id = UUID.randomUUID().toString(),
            clientId = clientId,
            label = label,
            note = note,
            createdAtEpochMillis = now(),
            keyAlias = alias,
        )
        try {
            records.save(identity)
        } catch (cause: Exception) {
            runCatching { keys.removeKey(alias) }
            throw cause
        }
        return identity
    }

    /**
     * Changes the names and nothing else. The key, and so the subject, cannot
     * be edited: a different key would be a different identity.
     */
    fun relabel(identity: SiopIdentity, label: String, note: String): SiopIdentity =
        identity.copy(label = label, note = note).also(records::save)

    /**
     * Records that the identity has just answered its RP, which puts it first
     * the next time that RP asks.
     */
    fun markUsed(identity: SiopIdentity): SiopIdentity =
        identity.copy(lastUsedAtEpochMillis = now()).also(records::save)

    /**
     * Removes the key along with the record. Nothing can sign as this subject
     * again; the account the RP holds for it is untouched, since this device
     * has no way to reach it.
     */
    fun delete(identity: SiopIdentity) {
        keys.removeKey(identity.keyAlias)
        records.remove(identity.id)
    }

    fun keyProvider(identity: SiopIdentity): SiopKeyProvider =
        keys.key(identity.keyAlias) ?: throw SiopError.InvalidKey("no key for this identity")

    fun publicJwk(identity: SiopIdentity): RsaPublicJwk = keyProvider(identity).publicJwk()

    /**
     * A key-per-RP key exists only because the user once answered this RP, so
     * it is marked used. Takes it over at most once, and creates nothing when
     * there is no such key.
     */
    private fun adoptPerRpKey(clientId: String, held: List<SiopIdentity>): SiopIdentity? {
        val alias = SiopKeyStore.alias(aliasPrefix, clientId)
        if (held.any { it.keyAlias == alias } || keys.key(alias) == null) return null
        val adopted = SiopIdentity(
            id = UUID.randomUUID().toString(),
            clientId = clientId,
            label = "",
            note = "",
            createdAtEpochMillis = now(),
            lastUsedAtEpochMillis = now(),
            keyAlias = alias,
        )
        records.save(adopted)
        return adopted
    }

    companion object {
        /**
         * Identities and keys in memory only. For tests and tools, where
         * nothing should outlive the process.
         */
        fun ephemeral(): SiopIdentityStore =
            SiopIdentityStore(InMemoryIdentityRecords(), InMemoryIdentityKeys(), "ephemeral")
    }
}

/** How a record is written down, wherever it is kept. */
object SiopIdentityRecordFormat {
    // Fields a later version adds are skipped, so a record it wrote still
    // reads here. A field this version needs and a record lacks is not.
    private val json = Json { ignoreUnknownKeys = true }

    fun encode(identity: SiopIdentity): String = json.encodeToString(SiopIdentity.serializer(), identity)

    /**
     * Every record, or an error. A record that does not decode is not
     * skipped: dropping it would drop an identity, the RP it answers would
     * look new, and answering that RP would make a different subject. So the
     * record's shape can change only in ways old records still decode.
     */
    fun decode(texts: List<String>): List<SiopIdentity> = texts.map { text ->
        try {
            json.decodeFromString(SiopIdentity.serializer(), text)
        } catch (cause: Exception) {
            throw SiopError.UnreadableRecord()
        }
    }
}

class InMemoryIdentityRecords : SiopIdentityRecords {
    private val byId = linkedMapOf<String, SiopIdentity>()

    override fun loadAll(): List<SiopIdentity> = byId.values.toList()
    override fun save(identity: SiopIdentity) { byId[identity.id] = identity }
    override fun remove(id: String) { byId.remove(id) }
}

class InMemoryIdentityKeys : SiopIdentityKeys {
    private val byAlias = mutableMapOf<String, SiopKeyProvider>()

    override fun key(alias: String): SiopKeyProvider? = byAlias[alias]
    override fun createKey(alias: String): SiopKeyProvider =
        KeyPairProvider.generate().also { byAlias[alias] = it }
    override fun removeKey(alias: String) { byAlias.remove(alias) }
}
