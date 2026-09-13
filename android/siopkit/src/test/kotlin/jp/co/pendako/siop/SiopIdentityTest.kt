package jp.co.pendako.siop

import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SiopIdentityStoreTest {
    private val clientId = "https://client.example.org/cb"

    /** A clock the test moves by hand, so the order of use is exact. */
    private class Clock {
        var millis = 1_000L
        fun tick(): Long = ++millis
    }

    private fun store(
        keys: SiopIdentityKeys = InMemoryIdentityKeys(),
        records: SiopIdentityRecords = InMemoryIdentityRecords(),
        adopts: Boolean = false,
        clock: Clock = Clock(),
    ) = SiopIdentityStore(records, keys, "test", adoptsPerRpKeys = adopts, now = clock::tick)

    @Test
    fun `looking up an RP's identities creates no key`() {
        val keys = CountingKeys()
        val store = store(keys = keys, adopts = true)

        assertTrue(store.identitiesFor(clientId).isEmpty())
        assertEquals(0, keys.created)
    }

    @Test
    fun `an identity is a key of its own, with a subject from that key`() {
        val store = store()
        val personal = store.createIdentity(clientId, label = "Personal")
        val testing = store.createIdentity(clientId, label = "Testing")

        assertNotEquals(store.publicJwk(personal).thumbprint(), store.publicJwk(testing).thumbprint())
        assertEquals(listOf(personal.id, testing.id), store.identitiesFor(clientId).map { it.id })
    }

    @Test
    fun `the identity that answered last is offered first`() {
        val store = store()
        store.createIdentity(clientId, label = "a")
        val b = store.createIdentity(clientId, label = "b")

        store.markUsed(b)

        assertEquals(b.id, store.identitiesFor(clientId).first().id)
    }

    @Test
    fun `renaming keeps the key and so the subject`() {
        val store = store()
        val identity = store.createIdentity(clientId, label = "before")
        val subject = store.publicJwk(identity).thumbprint()

        val renamed = store.relabel(identity, label = "after", note = "note")

        assertEquals("after", store.allIdentities().single().label)
        assertEquals(subject, store.publicJwk(renamed).thumbprint())
    }

    @Test
    fun `deleting removes the key with the record`() {
        val store = store()
        val identity = store.createIdentity(clientId)

        store.delete(identity)

        assertTrue(store.allIdentities().isEmpty())
        assertFailsWith<SiopError.InvalidKey> { store.keyProvider(identity) }
    }

    @Test
    fun `a key whose record cannot be saved is not left behind`() {
        val keys = CountingKeys()
        val store = store(keys = keys, records = RefusingRecords())

        assertFailsWith<SiopError.Storage> { store.createIdentity(clientId) }
        assertEquals(1, keys.created)
        assertTrue(keys.aliases.all { keys.key(it) == null })
    }

    // A save that fails after the record became visible — its sync failing —
    // must not leave a record whose key is gone.
    @Test
    fun `a save that fails after the record appeared takes the record back before the key`() {
        val keys = CountingKeys()
        val records = SavesThenFails()
        val store = store(keys = keys, records = records)

        assertFailsWith<SiopError.Storage> { store.createIdentity(clientId) }

        assertTrue(records.loadAll().isEmpty())
        assertTrue(keys.aliases.all { keys.key(it) == null })
    }

    @Test
    fun `a record that cannot be taken back keeps its key`() {
        val keys = CountingKeys()
        val records = SavesThenFails(removes = false)
        val store = store(keys = keys, records = records)

        assertFailsWith<SiopError.Storage> { store.createIdentity(clientId) }

        val left = records.loadAll().single()
        assertEquals(left.keyAlias, keys.aliases.single())
        assertTrue(store.publicJwk(left).thumbprint().isNotEmpty(), "鍵の無い識別子が残っている")
    }

    // Keys made by the key-per-RP version (docs/decisions/0003) are known to
    // their RPs by the subject they produce, so they are taken over.
    @Test
    fun `a key-per-RP key is taken over once, as already used`() {
        val keys = InMemoryIdentityKeys()
        val perRp = keys.createKey(SiopKeyStore.alias("test", clientId))
        val store = store(keys = keys, adopts = true)

        val first = store.identitiesFor(clientId)
        val again = store.identitiesFor(clientId)

        assertEquals(1, first.size)
        assertEquals(first, again)
        assertEquals(perRp.publicJwk().thumbprint(), store.publicJwk(first.single()).thumbprint())
        assertTrue(first.single().lastUsedAtEpochMillis != null)
    }

    @Test
    fun `a key-per-RP key is left alone unless asked for`() {
        val keys = InMemoryIdentityKeys()
        keys.createKey(SiopKeyStore.alias("test", clientId))

        assertTrue(store(keys = keys).identitiesFor(clientId).isEmpty())
    }

    @Test
    fun `a response is signed as the key it is given`() {
        val store = SiopIdentityStore.ephemeral()
        val identity = store.createIdentity(clientId)
        val request = AuthorizationRequest.parse(
            "openid://?response_type=id_token&scope=openid&nonce=n1&client_id=https%3A%2F%2Fclient.example.org%2Fcb"
        )

        val response = SelfIssuedOp.respond(request, store.keyProvider(identity))
        val claims = SelfIssuedIdTokenValidator.validate(response.idToken, clientId, "n1")

        assertEquals(store.publicJwk(identity).thumbprint(), claims.getValue("sub").jsonPrimitive.content)
    }

    /** Keys in memory, keeping every alias a key was made under. */
    private class CountingKeys : SiopIdentityKeys {
        private val base = InMemoryIdentityKeys()
        val aliases = mutableListOf<String>()
        val created get() = aliases.size
        override fun key(alias: String) = base.key(alias)
        override fun createKey(alias: String): SiopKeyProvider = base.createKey(alias).also { aliases += alias }
        override fun removeKey(alias: String) = base.removeKey(alias)
    }

    /** Records whose save lands and then reports failure, as when syncing fails after the rename. */
    private class SavesThenFails(private val removes: Boolean = true) : SiopIdentityRecords {
        private val base = InMemoryIdentityRecords()
        override fun loadAll() = base.loadAll()
        override fun save(identity: SiopIdentity) {
            base.save(identity)
            throw SiopError.Storage("sync failed")
        }
        override fun remove(id: String) {
            if (!removes) throw SiopError.Storage("cannot delete")
            base.remove(id)
        }
    }

    private class RefusingRecords : SiopIdentityRecords {
        override fun loadAll() = emptyList<SiopIdentity>()
        override fun save(identity: SiopIdentity) = throw SiopError.Storage("full")
        override fun remove(id: String) {}
    }
}

class SiopIdentityRecordFormatTest {
    private val identity = SiopIdentity(
        id = "id-1",
        clientId = "https://client.example.org/cb",
        label = "Personal",
        note = "",
        createdAtEpochMillis = 1_000,
        lastUsedAtEpochMillis = null,
        keyAlias = "test.alias",
    )

    @Test
    fun `a record reads back as it was written`() {
        val text = SiopIdentityRecordFormat.encode(identity)
        assertEquals(listOf(identity), SiopIdentityRecordFormat.decode(listOf(text)))
    }

    @Test
    fun `a field added later does not stop a record being read`() {
        val text = SiopIdentityRecordFormat.encode(identity).dropLast(1) + ""","addedLater":true}"""
        assertEquals(listOf(identity), SiopIdentityRecordFormat.decode(listOf(text)))
    }

    // Skipping it would make its RP look new, and answering that RP would make
    // a different subject.
    @Test
    fun `a record that does not decode is an error, not a gap`() {
        val good = SiopIdentityRecordFormat.encode(identity)
        assertFailsWith<SiopError.UnreadableRecord> {
            SiopIdentityRecordFormat.decode(listOf(good, """{"id":"id-2"}"""))
        }
    }
}

class ReceivedParametersTest {
    @Test
    fun `every parameter is kept as it arrived, in order`() {
        val request = AuthorizationRequest.parse(
            "openid://?scope=openid%20profile&response_type=id_token&nonce=n1" +
                "&client_id=https%3A%2F%2Fc.example%2Fcb&prompt=login"
        )
        assertEquals(
            listOf(
                "scope" to "openid profile",
                "response_type" to "id_token",
                "nonce" to "n1",
                "client_id" to "https://c.example/cb",
                "prompt" to "login",
            ),
            request.receivedParameters,
        )
        assertNull(request.state)
    }
}
