package jp.co.pendako.siop.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import jp.co.pendako.siop.AuthorizationRequest
import jp.co.pendako.siop.SelfIssuedIdTokenValidator
import jp.co.pendako.siop.SelfIssuedOp
import jp.co.pendako.siop.SiopError
import jp.co.pendako.siop.SiopIdentityStore
import jp.co.pendako.siop.SiopKeyStore
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The identities as this device keeps them: keys in the Android Keystore,
 * records in files. Everything else is tested against stores in memory, so
 * this is where signing inside the keystore is checked against a verifier.
 */
@RunWith(AndroidJUnit4::class)
class AndroidIdentityStorageTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val clientId = "https://client.example.org/cb"

    // Fresh names for every run, so nothing here meets the app's own identities.
    private val directory = File(context.cacheDir, "identities-${UUID.randomUUID()}")
    private val prefix = "jp.co.pendako.siop.test.${UUID.randomUUID()}"
    private val keys = AndroidKeystoreIdentityKeys()

    private fun store(adopts: Boolean = false) =
        SiopIdentityStore(FileIdentityRecords(directory), keys, prefix, adoptsPerRpKeys = adopts)

    @After
    fun removeWhatWasMade() {
        runCatching { store().allIdentities().forEach { store().delete(it) } }
        keys.removeKey(SiopKeyStore.alias(prefix, clientId))
        directory.deleteRecursively()
    }

    @Test
    fun anIdentityOutlivesTheStoreThatMadeItAndDeletingTakesItsKey() {
        val created = store().createIdentity(clientId, "Personal", "")
        val subject = store().publicJwk(created).thumbprint()

        val reopened = store()
        val found = reopened.allIdentities().single()
        assertEquals(created, found)
        assertEquals("sub が起動をまたいで変わっている", subject, reopened.publicJwk(found).thumbprint())

        reopened.delete(found)
        assertNull("鍵が消えていない", keys.key(created.keyAlias))
        assertTrue(reopened.allIdentities().isEmpty())
    }

    @Test
    fun aKeystoreKeySignsATokenTheVerifierAccepts() {
        val identity = store().createIdentity(clientId)
        val request = AuthorizationRequest.parse(
            "openid://?response_type=id_token&scope=openid&nonce=n1&client_id=https%3A%2F%2Fclient.example.org%2Fcb"
        )

        val response = SelfIssuedOp.respond(request, store().keyProvider(identity))
        val claims = SelfIssuedIdTokenValidator.validate(response.idToken, clientId, "n1")

        assertEquals(store().publicJwk(identity).thumbprint(), claims.getValue("sub").jsonPrimitive.content)
    }

    // The key-per-RP version kept one key per RP under an alias derived from
    // the client_id (docs/decisions/0003). The RP knows the subject it makes.
    @Test
    fun aKeyFromTheKeyPerRpVersionIsTakenOverWhenItsRpAsks() {
        val earlier = keys.createKey(SiopKeyStore.alias(prefix, clientId))

        val adopted = store(adopts = true).identitiesFor(clientId).single()

        assertEquals(earlier.publicJwk().thumbprint(), store().publicJwk(adopted).thumbprint())
        assertEquals("二度目にも引き継いでいる", 1, store(adopts = true).identitiesFor(clientId).size)
    }

    /** All a crash in the middle of a save can leave is the partial file, which is never read. */
    @Test
    fun aSaveCutShortLeavesTheRecordsReadable() {
        val identity = store().createIdentity(clientId, "Kept", "")
        File(directory, "${identity.id}.json.partial").writeText("{ half a rec")

        assertEquals(listOf(identity), store().allIdentities())
    }

    @Test
    fun aRecordThatDoesNotDecodeStopsEverything() {
        store().createIdentity(clientId, "Readable", "")
        File(directory, "broken.json").writeText("{ not a record")

        try {
            store().allIdentities()
            fail("読めない記録を読み飛ばしている")
        } catch (expected: SiopError.UnreadableRecord) {
            // Skipping it would make its RP look new.
        }
    }
}
