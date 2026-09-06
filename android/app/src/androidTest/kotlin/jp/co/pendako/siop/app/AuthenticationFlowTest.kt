package jp.co.pendako.siop.app

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import jp.co.pendako.siop.KeyPairProvider
import jp.co.pendako.siop.SelfIssuedIdTokenValidator
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Covers what the app does with a Section 7.3 request: the consent screen it
 * shows and the response it produces on approval or refusal.
 *
 * The request is handed to the session directly rather than through an intent,
 * because these tests are about the screen and the response. That the
 * `openid:` intent filter routes at all is exercised by the real launch path.
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

    private fun session(url: String = requestUrl): AuthenticationSession {
        val session = AuthenticationSession(KeyPairProvider.generate())
        session.receive(url)
        return session
    }

    private fun show(session: AuthenticationSession, onRespond: (String) -> Boolean = { true }) {
        composeRule.setContent { RootScreen(session = session, onRespond = onRespond) }
    }

    @Test
    fun consentScreenShowsTheRequest() {
        show(session())

        composeRule.onNodeWithText(clientId).assertIsDisplayed()
        composeRule.onNodeWithText("openid").assertIsDisplayed()
        composeRule.onNodeWithText("profile").assertIsDisplayed()
        composeRule.onNodeWithText("n-0S6_WzA2Mj").assertIsDisplayed()
        composeRule.onNodeWithText("この識別子で応答する").assertIsDisplayed()
        composeRule.onNodeWithText("拒否する").assertIsDisplayed()
    }

    @Test
    fun approvalReturnsAVerifiableTokenToTheRp() {
        var redirect: String? = null
        show(session()) { redirect = it; true }

        composeRule.onNodeWithText("この識別子で応答する").performClick()
        composeRule.waitForIdle()

        val url = requireNotNull(redirect) { "RP に応答が返されていない" }
        // Section 3.2.2.5: the implicit flow returns the response in the fragment.
        assertTrue(url.startsWith("$clientId#id_token="))
        assertTrue(url.endsWith("&state=af0ifjsldkj"))

        val idToken = url.substringAfter("#id_token=").substringBefore("&")
        val payload = SelfIssuedIdTokenValidator.validate(
            idToken = idToken,
            expectedAudience = clientId,
            expectedNonce = "n-0S6_WzA2Mj",
        )
        assertEquals("https://self-issued.me", payload.getValue("iss").jsonPrimitive.content)
        composeRule.onNodeWithText("ID Token を返しました").assertIsDisplayed()
    }

    @Test
    fun refusalReturnsAccessDenied() {
        var redirect: String? = null
        show(session()) { redirect = it; true }

        composeRule.onNodeWithText("拒否する").performClick()
        composeRule.waitForIdle()

        // Section 3.1.2.6
        assertEquals("$clientId#error=access_denied&state=af0ifjsldkj", redirect)
        composeRule.onNodeWithText("リクエストを拒否しました").assertIsDisplayed()
    }

    @Test
    fun aRedirectNothingCanOpenIsReportedRatherThanCrashing() {
        // Section 7.2 lets client_id be any URI, including a scheme no app
        // handles. The token is issued but never reaches the RP.
        val unreachable = "com.example.nothing.handles.this://cb"
        val request =
            "openid://?response_type=id_token&scope=openid&nonce=n1&client_id=" +
                java.net.URLEncoder.encode(unreachable, "UTF-8")

        show(session(request), onRespond = { false })
        composeRule.onNodeWithText("この識別子で応答する").performClick()
        composeRule.waitForIdle()

        composeRule.onNodeWithText("応答を渡せませんでした").assertIsDisplayed()
    }

    @Test
    fun aRefusalThatCannotBeDeliveredIsReported() {
        show(session(), onRespond = { false })
        composeRule.onNodeWithText("拒否する").performClick()
        composeRule.waitForIdle()

        composeRule.onNodeWithText("応答を渡せませんでした").assertIsDisplayed()
    }

    @Test
    fun anUnsupportedResponseTypeIsRejected() {
        show(session("openid://?response_type=code&client_id=https%3A%2F%2Fc.example%2Fcb&scope=openid&nonce=n1"))

        composeRule.onNodeWithText("処理できませんでした").assertIsDisplayed()
        composeRule.onNodeWithText("未対応の response_type です: code").assertIsDisplayed()
    }
}
