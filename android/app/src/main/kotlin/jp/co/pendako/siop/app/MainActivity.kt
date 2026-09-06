package jp.co.pendako.siop.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.core.net.toUri

class MainActivity : ComponentActivity() {
    private lateinit var session: AuthenticationSession

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        session = try {
            AuthenticationSession(SiopKeyStore.loadOrCreate())
        } catch (cause: Exception) {
            AuthenticationSession(null, keyFailure = cause.toString())
        }

        setContent {
            MaterialTheme {
                Surface {
                    RootScreen(
                        session = session,
                        onRespond = ::openRedirect,
                    )
                }
            }
        }

        handle(intent)
    }

    // launchMode is singleTask, so a request arriving while the app is running
    // comes here rather than through onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent) {
        val data = intent.data ?: return
        if (data.scheme != "openid") return
        session.receive(data.toString())
    }

    /**
     * Hands the response to the RP. The browser that started the request cannot
     * be named, so this goes to whichever app handles the redirect URI.
     */
    private fun openRedirect(url: String) {
        startActivity(Intent(Intent.ACTION_VIEW, url.toUri()).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    }
}
