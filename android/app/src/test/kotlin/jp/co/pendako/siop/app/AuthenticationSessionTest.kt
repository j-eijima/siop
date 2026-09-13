package jp.co.pendako.siop.app

import jp.co.pendako.siop.AuthorizationRequest
import jp.co.pendako.siop.InMemoryIdentityKeys
import jp.co.pendako.siop.InMemoryIdentityRecords
import jp.co.pendako.siop.SelfIssuedIdTokenValidator
import jp.co.pendako.siop.SiopError
import jp.co.pendako.siop.SiopIdentity
import jp.co.pendako.siop.SiopIdentityKeys
import jp.co.pendako.siop.SiopIdentityRecords
import jp.co.pendako.siop.SiopIdentityStore
import jp.co.pendako.siop.SiopKeyProvider
import jp.co.pendako.siop.SiopKeyStore
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the session does with a request and with the identities behind it.
 * These are questions about state rather than about any screen, so they are
 * answered here exactly, on the JVM.
 */
class AuthenticationSessionTest {
    private val clientId = "https://client.example.org/cb"

    private fun requestUrl(nonce: String = "n1") =
        "openid://?response_type=id_token&scope=openid&nonce=$nonce&client_id=https%3A%2F%2Fclient.example.org%2Fcb"

    /** Every redirect handed to the RP, answering whether it could be opened. */
    private class Deliveries(private val opens: Boolean = true) {
        val urls = mutableListOf<String>()
        fun deliver(url: String): Boolean {
            urls += url
            return opens
        }
    }

    private fun consent(session: AuthenticationSession, nonce: String = "n1"): AuthorizationRequest {
        session.receive(requestUrl(nonce))
        val phase = session.phase
        assertTrue("同意画面になっていない: $phase", phase is AuthenticationSession.Phase.Consent)
        return (phase as AuthenticationSession.Phase.Consent).request
    }

    /** The subject of the ID Token carried in a redirect, once the RP's own checks pass. */
    private fun subjectIn(redirect: String): String {
        val token = redirect.substringAfter("#id_token=").substringBefore("&")
        return SelfIssuedIdTokenValidator.validate(token, clientId, "n1").getValue("sub").jsonPrimitive.content
    }

    // Identities

    /** `client_id` comes from whoever sent the request, so a request alone must not cost a key. */
    @Test
    fun receivingARequestCreatesNoIdentity() {
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        consent(session)
        assertTrue("リクエストを受け取っただけで識別子を作っている", session.identities.isEmpty())
    }

    @Test
    fun decliningCreatesNoIdentity() {
        val deliveries = Deliveries()
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        session.decline(consent(session), deliveries::deliver)

        assertTrue("拒否したのに識別子を作っている", session.identities.isEmpty())
        assertTrue(deliveries.urls.single().contains("error=access_denied"))
        assertTrue(session.phase is AuthenticationSession.Phase.Declined)
    }

    @Test
    fun theFirstAnswerToAnRpCreatesOneIdentityAndSignsAsIt() {
        val deliveries = Deliveries()
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        session.approve(consent(session), null, deliveries::deliver)

        val identity = session.identities.single()
        assertEquals(clientId, identity.clientId)
        assertEquals(session.subjectOf(identity), subjectIn(deliveries.urls.single()))
        assertTrue(session.phase is AuthenticationSession.Phase.Sent)
    }

    @Test
    fun theResponseIsSignedAsTheChosenIdentity() {
        val deliveries = Deliveries()
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        val personal = session.createIdentity(clientId, "個人用", "")!!
        val testing = session.createIdentity(clientId, "テスト用", "")!!

        session.approve(consent(session), testing, deliveries::deliver)

        assertEquals(session.subjectOf(testing), subjectIn(deliveries.urls.single()))
        assertNotEquals(session.subjectOf(personal), session.subjectOf(testing))
        assertEquals("選んだ識別子があるのに新しく作っている", 2, session.identities.size)
    }

    /** An identity answering a second RP would hand both the same subject. */
    @Test
    fun anIdentityNeverAnswersAnotherRp() {
        val deliveries = Deliveries()
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        val other = session.createIdentity("https://other.example/cb", "別の RP", "")!!

        session.approve(consent(session), other, deliveries::deliver)

        assertTrue("別の RP の識別子で応答しようとしている", session.phase is AuthenticationSession.Phase.Failed)
        assertTrue("別の RP の識別子で応答を送っている", deliveries.urls.isEmpty())
    }

    @Test
    fun theIdentityThatAnsweredLastIsOfferedFirst() {
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        session.createIdentity(clientId, "a", "")!!
        val b = session.createIdentity(clientId, "b", "")!!

        session.approve(consent(session), b, Deliveries()::deliver)

        assertEquals(b.id, session.identitiesFor(clientId).first().id)
    }

    @Test
    fun renamingKeepsTheSubject() {
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        val identity = session.createIdentity(clientId, "before", "")!!
        val before = session.subjectOf(identity)

        session.relabel(identity, "after", "メモ")

        val renamed = session.identities.single()
        assertEquals("after", renamed.label)
        assertEquals("メモ", renamed.note)
        assertEquals(before, session.subjectOf(renamed))
    }

    /** A screen can hold the identity from before a rename; answering must not put the old name back. */
    @Test
    fun answeringAsAnIdentityRenamedSinceKeepsTheNewName() {
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        val stale = session.createIdentity(clientId, "before", "")!!
        session.relabel(stale, "after", "")

        session.approve(consent(session), stale, Deliveries()::deliver)

        assertEquals("after", session.identities.single().label)
    }

    @Test
    fun aKeyPerRpKeyIsOfferedWhenItsRpAsks() {
        val keys = InMemoryIdentityKeys()
        val perRp = keys.createKey(SiopKeyStore.alias("test", clientId))
        val store = SiopIdentityStore(InMemoryIdentityRecords(), keys, "test", adoptsPerRpKeys = true)
        val session = AuthenticationSession(store)

        consent(session)

        val adopted = session.identitiesFor(clientId).single()
        assertEquals("旧版の鍵の sub が引き継がれていない", perRp.publicJwk().thumbprint(), session.subjectOf(adopted))
    }

    /** Keys that cannot be read at all, as when the keystore refuses. */
    private class UnreadableKeys : SiopIdentityKeys {
        override fun key(alias: String): SiopKeyProvider? = throw SiopError.Storage("keystore refused")
        override fun createKey(alias: String): SiopKeyProvider = InMemoryIdentityKeys().createKey(alias)
        override fun removeKey(alias: String) {}
    }

    /** Keys that exist, but stop being readable once told to. */
    private class ForgetfulKeys : SiopIdentityKeys {
        private val base = InMemoryIdentityKeys()
        var forgets = false
        override fun key(alias: String): SiopKeyProvider? = if (forgets) null else base.key(alias)
        override fun createKey(alias: String) = base.createKey(alias)
        override fun removeKey(alias: String) = base.removeKey(alias)
    }

    /** Records that cannot be read, as when one no longer decodes. */
    private class UnreadableRecords : SiopIdentityRecords {
        override fun loadAll(): List<SiopIdentity> = throw SiopError.UnreadableRecord()
        override fun save(identity: SiopIdentity) {}
        override fun remove(id: String) {}
    }

    /** A record that does not decode must stop the request: skipping it would make its RP look new. */
    @Test
    fun aRequestStopsWhenARecordCannotBeRead() {
        val deliveries = Deliveries()
        val store = SiopIdentityStore(UnreadableRecords(), InMemoryIdentityKeys(), "test")
        val session = AuthenticationSession(store)

        session.receive(requestUrl())

        assertTrue("記録を読めないのに同意画面へ進んでいる", session.phase is AuthenticationSession.Phase.Failed)
        assertTrue(deliveries.urls.isEmpty())
    }

    /**
     * If the identities cannot be read, an RP this device has answered would
     * look new, and answering it would make a different subject.
     */
    @Test
    fun aRequestStopsWhenIdentitiesCannotBeRead() {
        val store = SiopIdentityStore(InMemoryIdentityRecords(), UnreadableKeys(), "test", adoptsPerRpKeys = true)
        val session = AuthenticationSession(store)

        session.receive(requestUrl())

        assertTrue("識別子を読めないのに同意画面へ進んでいる", session.phase is AuthenticationSession.Phase.Failed)
        assertTrue(session.identities.isEmpty())
    }

    /** An identity that exists but cannot sign gets no stand-in: that would answer as someone else. */
    @Test
    fun anIdentityThatCannotSignIsNotReplacedUnasked() {
        val keys = ForgetfulKeys()
        val deliveries = Deliveries()
        val session = AuthenticationSession(SiopIdentityStore(InMemoryIdentityRecords(), keys, "test"))
        session.createIdentity(clientId, "established", "")!!
        keys.forgets = true

        val request = consent(session)
        assertNull("読めない鍵の識別子に sub が付いている", session.subjectOf(session.identities.single()))

        session.approve(request, null, deliveries::deliver)

        assertTrue("読めない識別子の代わりに新しい識別子で応答しようとしている", session.phase is AuthenticationSession.Phase.Failed)
        assertEquals("代わりの識別子を作っている", 1, session.identities.size)
        assertTrue(deliveries.urls.isEmpty())
    }

    @Test
    fun deletingRemovesTheIdentity() {
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        val identity = session.createIdentity(clientId, "gone", "")!!

        session.delete(identity)

        assertTrue(session.identities.isEmpty())
        assertNull(session.subjectOf(identity))
    }

    // What is kept for when the process is ended

    /**
     * A request waiting for the user is reported, so it can be kept past the
     * process being ended, and dropped once answered, so an answered request
     * is never offered again.
     */
    @Test
    fun theRequestWaitingForAnAnswerIsReportedUntilItIsAnswered() {
        val kept = mutableListOf<String?>()
        val session = AuthenticationSession(SiopIdentityStore.ephemeral()) { kept += it }

        val request = consent(session)
        assertEquals(requestUrl(), kept.last())

        session.approve(request, null, Deliveries()::deliver)
        assertNull("応答済みのリクエストを残している", kept.last())

        session.receive(requestUrl(nonce = "n2"))
        session.reset()
        assertNull("閉じたリクエストを残している", kept.last())

        session.receive("openid://?response_type=code&client_id=https%3A%2F%2Fc.example%2Fcb&scope=openid&nonce=n1")
        assertNull("処理できなかったリクエストを残している", kept.last())
    }

    // Delivery

    /** Section 7.2 lets client_id name a scheme no app handles; the token is issued but never arrives. */
    @Test
    fun aRedirectNothingOpensIsReportedAsUndeliverable() {
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        session.approve(consent(session), null, Deliveries(opens = false)::deliver)

        assertTrue("渡せなかったことが報告されていない", session.phase is AuthenticationSession.Phase.Undeliverable)
    }

    @Test
    fun anUnsupportedResponseTypeIsRejected() {
        val session = AuthenticationSession(SiopIdentityStore.ephemeral())
        session.receive("openid://?response_type=code&client_id=https%3A%2F%2Fc.example%2Fcb&scope=openid&nonce=n1")

        assertEquals(
            AuthenticationSession.Phase.Failed(Failure.UnsupportedResponseType("code")),
            session.phase,
        )
    }
}
