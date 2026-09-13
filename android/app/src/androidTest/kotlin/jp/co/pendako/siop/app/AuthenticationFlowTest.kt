package jp.co.pendako.siop.app

import android.content.res.Configuration
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.net.URLEncoder
import java.util.Locale
import jp.co.pendako.siop.SelfIssuedIdTokenValidator
import jp.co.pendako.siop.SiopIdentityStore
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Covers what the screens do with a Section 7.3 request: the consent screen
 * they show, the identities they offer, and the response produced on approval
 * or refusal.
 *
 * The request is handed to the session directly rather than through an
 * intent: these tests are about the screens and the response. That the
 * `openid:` route works is the job of [EndToEndRpTest], which goes through
 * the browser.
 *
 * Buttons are found by test tag; everything else is read as text, so the
 * screens are shown in English whatever language the device is set to
 * (docs/decisions/0012).
 */
@RunWith(AndroidJUnit4::class)
class AuthenticationFlowTest {

    // A blank host rather than MainActivity, which sets its own content.
    @get:Rule
    val composeRule = createComposeRule()

    private val clientId = "https://client.example.org/cb"
    private val requestUrl =
        "openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb" +
            "&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj"

    private fun requestFrom(clientId: String) =
        "openid://?response_type=id_token&scope=openid&nonce=n1&client_id=" + URLEncoder.encode(clientId, "UTF-8")

    private fun session(url: String? = requestUrl, store: SiopIdentityStore = SiopIdentityStore.ephemeral()) =
        AuthenticationSession(store).also { session -> url?.let(session::receive) }

    private fun show(session: AuthenticationSession, onRespond: (String) -> Boolean = { true }) {
        composeRule.setContent { English { SiopTheme { RootScreen(session, onRespond) } } }
    }

    /** The screens' wording in English, whatever the device is set to. */
    @Composable
    private fun English(content: @Composable () -> Unit) {
        val base = LocalContext.current
        val configuration = Configuration(base.resources.configuration).apply { setLocale(Locale.ENGLISH) }
        val context = base.createConfigurationContext(configuration)
        CompositionLocalProvider(
            LocalContext provides context,
            LocalConfiguration provides configuration,
            LocalResources provides context.resources,
        ) { content() }
    }

    /**
     * The whole subject that will be signed, as the preview shows it; rows
     * elsewhere shorten it. A JWK thumbprint is 43 base64url characters.
     */
    private fun subjectShown(): String? = composeRule
        .onAllNodes(isThumbprint)
        .fetchSemanticsNodes()
        .firstOrNull()
        ?.config?.getOrNull(SemanticsProperties.Text)
        ?.joinToString("") { it.text }

    private val isThumbprint = SemanticsMatcher("shows a JWK thumbprint") { node ->
        node.config.getOrNull(SemanticsProperties.Text).orEmpty().any { THUMBPRINT.matches(it.text) }
    }

    @Test
    fun homeShowsIdentitiesAndTheDiscoveryMetadata() {
        show(session(url = null))

        composeRule.onNodeWithText("a separate key for one RP", substring = true).assertIsDisplayed()
        composeRule.onNodeWithText("pairwise").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("https://self-issued.me").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun consentShowsTheRequestAndWhatWillBeSigned() {
        show(session())

        composeRule.onAllNodesWithText(clientId).onFirst().assertIsDisplayed()
        composeRule.onNodeWithText("openid profile").performScrollTo().assertIsDisplayed()
        composeRule.onAllNodesWithText("n-0S6_WzA2Mj").onFirst().performScrollTo().assertIsDisplayed()
        // state comes back outside the token, so it is previewed beside it.
        assertEquals(2, composeRule.onAllNodesWithText("af0ifjsldkj").fetchSemanticsNodes().size)
        // The decision stays put while the request scrolls.
        composeRule.onNodeWithTag("approve").assertIsDisplayed()
        composeRule.onNodeWithTag("decline").assertIsDisplayed()
    }

    @Test
    fun approvalReturnsAVerifiableTokenToTheRp() {
        var redirect: String? = null
        show(session()) { redirect = it; true }

        composeRule.onNodeWithTag("approve").performClick()
        composeRule.waitForIdle()

        val url = requireNotNull(redirect) { "RP に応答が返されていない" }
        // Section 3.2.2.5: the implicit flow returns the response in the fragment.
        assertTrue(url.startsWith("$clientId#id_token="))
        assertTrue(url.endsWith("&state=af0ifjsldkj"))
        val payload = SelfIssuedIdTokenValidator.validate(
            idToken = url.substringAfter("#id_token=").substringBefore("&"),
            expectedAudience = clientId,
            expectedNonce = "n-0S6_WzA2Mj",
        )
        assertEquals("https://self-issued.me", payload.getValue("iss").jsonPrimitive.content)
        composeRule.onNodeWithText("ID Token returned").assertIsDisplayed()
    }

    @Test
    fun declineReturnsAccessDenied() {
        var redirect: String? = null
        show(session()) { redirect = it; true }

        composeRule.onNodeWithTag("decline").performClick()
        composeRule.waitForIdle()

        // Section 3.1.2.6
        assertEquals("$clientId#error=access_denied&state=af0ifjsldkj", redirect)
        composeRule.onNodeWithText("Request declined").assertIsDisplayed()
    }

    @Test
    fun aRedirectNothingCanOpenIsReportedRatherThanClaimingSuccess() {
        // Section 7.2 lets client_id be any URI, including a scheme no app
        // handles. The token is issued but never reaches the RP.
        show(session(requestFrom("com.example.nothing.handles.this://cb")), onRespond = { false })

        composeRule.onNodeWithTag("approve").performClick()
        composeRule.waitForIdle()

        composeRule.onNodeWithText("Response not delivered").assertIsDisplayed()
    }

    /**
     * Showing a consent screen must not create a key: the `client_id` comes
     * from whoever sent the request, so an unanswered stream of them would
     * otherwise fill the keystore.
     */
    @Test
    fun anUnansweredRequestEstablishesNoIdentifier() {
        val store = SiopIdentityStore.ephemeral()
        show(session(store = store))

        composeRule.onNodeWithText("First request from this requester", substring = true)
            .performScrollTo().assertIsDisplayed()
        assertTrue("応答前に識別子を作っている", store.allIdentities().isEmpty())
        assertNull("応答前に sub を表示している", subjectShown())
    }

    /** The subject is the thumbprint of a key made for one RP, so a second RP is shown another. */
    @Test
    fun eachRpIsShownItsOwnSubject() {
        val store = SiopIdentityStore.ephemeral()
        val one = "https://one.example/cb"
        val two = "https://two.example/cb"
        val session = session(url = null, store = store)
        for (rp in listOf(one, two)) {
            session.receive(requestFrom(rp))
            val request = (session.phase as AuthenticationSession.Phase.Consent).request
            session.approve(request, null) { true }
        }

        session.receive(requestFrom(one))
        show(session)

        val first = subjectShown()
        assertNotNull("応答後も識別子が確立していない", first)
        assertEquals(session.subjectOf(session.identitiesFor(one).single()), first)
        assertNotEquals("別の RP に同じ識別子を提示している", first, session.subjectOf(session.identitiesFor(two).single()))
    }

    /** A second identity for the same RP is a second key, so choosing it changes the subject signed. */
    @Test
    fun choosingAnotherIdentityChangesTheSubjectSigned() {
        val session = session(url = null)
        val personal = session.createIdentity(clientId, "Personal", "")!!
        val testing = session.createIdentity(clientId, "Testing", "")!!
        session.receive(requestUrl)
        var redirect: String? = null
        show(session) { redirect = it; true }

        assertEquals(session.subjectOf(personal), subjectShown())
        composeRule.onNodeWithText("Testing").performScrollTo().performClick()
        assertEquals(session.subjectOf(testing), subjectShown())

        composeRule.onNodeWithTag("approve").performClick()
        composeRule.waitForIdle()
        val token = requireNotNull(redirect).substringAfter("#id_token=").substringBefore("&")
        val sub = SelfIssuedIdTokenValidator.validate(token, clientId, "n-0S6_WzA2Mj").getValue("sub").jsonPrimitive.content
        assertEquals(session.subjectOf(testing), sub)
    }

    @Test
    fun anIdentityCreatedForTheRpIsOfferedAndSignsTheResponse() {
        show(session())

        composeRule.onNodeWithText("Create identity").performScrollTo().performClick()
        composeRule.onNodeWithTag("identity-label").performTextInput("Personal")
        composeRule.onNodeWithTag("save-identity").performClick()

        composeRule.onNodeWithText("Personal").performScrollTo().assertIsDisplayed()
        assertNotNull("作った識別子の sub がプレビューに無い", subjectShown())
        composeRule.onNodeWithTag("approve").performClick()
        composeRule.onNodeWithText("ID Token returned").assertIsDisplayed()
    }

    /** Deleting takes the key with it, so it asks first, and says what it does not do. */
    @Test
    fun deletingAnIdentityAsksFirstAndSaysWhatItLeavesAlone() {
        show(session())
        composeRule.onNodeWithText("Create identity").performScrollTo().performClick()
        composeRule.onNodeWithTag("identity-label").performTextInput("Doomed")
        composeRule.onNodeWithTag("save-identity").performClick()

        composeRule.onNodeWithContentDescription("Details").performScrollTo().performClick()
        composeRule.onNodeWithTag("delete-identity").performScrollTo().performClick()

        composeRule.onNodeWithText("does not delete the account the RP holds", substring = true).assertIsDisplayed()
        composeRule.onNodeWithTag("confirm-delete").performClick()

        composeRule.onNodeWithText("First request from this requester", substring = true)
            .performScrollTo().assertIsDisplayed()
    }

    @Test
    fun anUnsupportedResponseTypeIsRejected() {
        show(session("openid://?response_type=code&client_id=https%3A%2F%2Fc.example%2Fcb&scope=openid&nonce=n1"))

        composeRule.onNodeWithText("Could not process the request").assertIsDisplayed()
        composeRule.onNodeWithText("Unsupported response_type: code").assertIsDisplayed()
    }

    private companion object {
        val THUMBPRINT = Regex("[A-Za-z0-9_-]{43}")
    }
}
