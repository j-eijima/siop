package jp.co.pendako.siop.app

import android.content.Intent
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import java.net.InetSocketAddress
import java.net.Socket
import java.util.regex.Pattern
import org.junit.Assert.assertNotNull
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Full round trip against the test RP in `rp/`: Chrome sends the request to
 * the `openid:` endpoint, the app issues the ID Token, and the RP verifies it
 * (OpenID Connect Core 1.0 Sections 7.3 - 7.5).
 *
 * Needs the RP running on the host and reachable as localhost from the
 * device:
 *
 *     python3 rp/serve.py
 *     adb reverse tcp:8080 tcp:8080
 *
 * The response comes back by opening `redirect_uri`, which Android hands to
 * the default browser; the nonce and state the RP checks live in the browser
 * that started the request. So the round trip completes only when the RP page
 * was opened in that browser — here, Chrome, the only one on the emulator.
 */
@RunWith(AndroidJUnit4::class)
class EndToEndRpTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)

    @Before
    fun startFromAFreshChrome() {
        // A socket rather than an HTTP request: the app, whose process this
        // runs in, does not allow cleartext HTTP, and only reachability matters.
        val reachable = runCatching {
            Socket().use { it.connect(InetSocketAddress("localhost", 8080), 5_000) }
        }.isSuccess
        assumeTrue("テスト RP が起動していません: python3 rp/serve.py と adb reverse tcp:8080 tcp:8080", reachable)

        // Chrome left with the tabs of an earlier run shows one of them first,
        // and then scrolls away from anything found on it when the new page
        // loads. Starting from nothing makes the page on screen the one opened
        // here.
        device.executeShellCommand("pm clear $CHROME")
    }

    @Test
    fun rpRequestIsIssuedAndVerified() {
        instrumentation.targetContext.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(RP_URL))
                .setPackage(CHROME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        )
        dismissChromeFirstRun()

        // Found by its text: the page is a web page, and what UI Automator
        // sees of it is what each element reads as. The RP's page notes where
        // this string lives. The URL's fragment scrolls it into view.
        waitFor(By.pkg(CHROME).text("Authentication request"), "RP のページが表示されません")
        scrollUntilShown(START, "開始のリンクが見つかりません").click()

        // Found by test tag, which the app exposes as a resource id: the
        // button's title depends on whether this RP has an identity yet.
        val approve = waitForApprove()
        approve.click()

        // Section 7.5: the RP verifies iss / sub / sub_jwk / signature / aud / nonce.
        assertNotNull(
            "RP がトークンを検証できませんでした",
            device.wait(Until.findObject(By.text("✓ Authentication verified")), TIMEOUT),
        )
    }

    private fun waitFor(selector: BySelector, message: String): UiObject2 {
        val found = device.wait(Until.findObject(selector), TIMEOUT)
        assertNotNull(message, found)
        return found
    }

    /** Chrome shows UI Automator only what is on screen, so scroll the page until it is. */
    private fun scrollUntilShown(selector: BySelector, message: String): UiObject2 {
        repeat(15) {
            device.findObject(selector)?.let { return it }
            val x = device.displayWidth / 2
            device.swipe(x, device.displayHeight * 3 / 4, x, device.displayHeight / 4, 20)
            device.waitForIdle()
        }
        return waitFor(selector, message)
    }

    /**
     * Waits for the consent screen. Chrome may ask before handing a link to
     * another app; that is answered yes. The request page offers its link
     * only once it has recorded the request, so a tap that landed before
     * that is made again.
     */
    private fun waitForApprove(): UiObject2 {
        val deadline = System.currentTimeMillis() + TIMEOUT
        var retapAt = System.currentTimeMillis() + RETAP_AFTER
        while (System.currentTimeMillis() < deadline) {
            device.findObject(By.res("approve"))?.let { return it }
            device.findObject(By.pkg(CHROME).text(HAND_OFF))?.click()
            if (System.currentTimeMillis() > retapAt) {
                device.findObject(START)?.click()
                retapAt = System.currentTimeMillis() + RETAP_AFTER
            }
            device.waitForIdle()
            Thread.sleep(500)
        }
        return waitFor(By.res("approve"), "同意画面が表示されません")
    }

    /** A fresh Chrome opens on its welcome screens. */
    private fun dismissChromeFirstRun() {
        repeat(4) {
            val button = device.wait(Until.findObject(By.pkg(CHROME).text(FIRST_RUN)), 3_000) ?: return
            button.click()
            device.waitForIdle()
        }
    }

    private companion object {
        /**
         * In English: Chrome follows the device's language, and the RP's
         * wording is what the test reads. The fragment names the link that
         * starts the request, so the page opens scrolled to it.
         */
        const val RP_URL = "http://localhost:8080/index.html?lang=en#start-authentication"
        const val CHROME = "com.android.chrome"
        const val TIMEOUT = 30_000L
        const val RETAP_AFTER = 5_000L
        val START: BySelector = By.pkg(CHROME).text("Choose an identity in SIOP →")
        val HAND_OFF: Pattern = Pattern.compile("(?i)open|continue|開く|続行")
        val FIRST_RUN: Pattern = Pattern.compile("(?i)use without an account|accept & continue|no thanks|got it")
    }
}
