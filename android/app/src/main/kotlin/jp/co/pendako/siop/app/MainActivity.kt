package jp.co.pendako.siop.app

import android.app.Application
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.core.net.toUri
import androidx.lifecycle.AndroidViewModel
import java.io.File
import jp.co.pendako.siop.SiopIdentityStore

class MainActivity : ComponentActivity() {
    private val model: SessionModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        setContent {
            SiopTheme {
                Surface(Modifier.fillMaxSize()) {
                    RootScreen(session = model.session, onRespond = ::openRedirect)
                }
            }
        }

        // An activity recreated — turned to landscape, say — has handled its
        // request already, and the session kept it.
        if (savedInstanceState == null) handle(intent)
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
        model.session.receive(data.toString())
    }

    /**
     * Hands the response to the RP. The browser that started the request cannot
     * be named, so this goes to whichever app handles the redirect URI.
     *
     * Returns false when nothing can open it. A `client_id` may name any
     * scheme (Section 7.2), including one no installed app handles, so this is
     * an outcome to report rather than a crash to let happen.
     */
    private fun openRedirect(url: String): Boolean = try {
        startActivity(Intent(Intent.ACTION_VIEW, url.toUri()).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
        true
    } catch (cause: ActivityNotFoundException) {
        false
    } catch (cause: SecurityException) {
        false
    }
}

/**
 * Holds the session across configuration changes, so turning the device
 * mid-consent keeps the request on screen.
 */
class SessionModel(application: Application) : AndroidViewModel(application) {
    val session = AuthenticationSession(
        SiopIdentityStore(
            records = FileIdentityRecords(File(application.noBackupFilesDir, "identities")),
            keys = AndroidKeystoreIdentityKeys(),
            aliasPrefix = KEY_ALIAS_PREFIX,
            adoptsPerRpKeys = true,
        )
    )
}

/**
 * Shared with the key-per-RP version, so that the keys it made for each RP
 * are found and taken over as identities (docs/decisions/0011).
 */
private const val KEY_ALIAS_PREFIX = "jp.co.pendako.siop.key"
