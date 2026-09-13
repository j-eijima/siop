package jp.co.pendako.siop.app

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import jp.co.pendako.siop.SelfIssuedIdToken
import jp.co.pendako.siop.SiopIdentity

/**
 * Shown when the app is opened directly: every identity on the device, grouped
 * by the RP it answers, and the Discovery metadata.
 *
 * Nothing is created here. An identity belongs to one RP, so there is nothing
 * to make one for until an RP asks.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(session: AuthenticationSession) {
    var inspecting by remember { mutableStateOf<SiopIdentity?>(null) }
    // Grouped in the order identities are offered, so the RP answered most
    // recently comes first.
    val byRp = session.identities.groupBy { it.clientId }

    Scaffold(topBar = { CenterAlignedTopAppBar(title = { Text("Self-Issued OP") }) }) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 720.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Panel(title = stringResource(R.string.identities_header)) {
                    Text(stringResource(R.string.home_identities_explain), style = MaterialTheme.typography.bodyMedium)
                    Text(
                        stringResource(R.string.home_identities_footer),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                if (byRp.isEmpty()) {
                    Text(
                        stringResource(R.string.home_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                byRp.forEach { (clientId, identities) ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(MaterialTheme.colorScheme.surfaceContainerLow, RoundedCornerShape(14.dp))
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            clientId,
                            style = MaterialTheme.typography.labelMedium.mono(),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        identities.forEach { identity ->
                            Box(Modifier.fillMaxWidth().clickable { inspecting = identity }) {
                                IdentityRow(identity, session.subjectOf(identity))
                            }
                        }
                    }
                }

                // Protocol vocabulary, shown as the metadata spells it.
                Panel(title = stringResource(R.string.home_metadata_header)) {
                    ParameterRow("issuer", SelfIssuedIdToken.ISSUER)
                    ParameterRow("authorization_endpoint", "openid:")
                    ParameterRow("response_types", "id_token")
                    ParameterRow("subject_types", "pairwise")
                    ParameterRow("alg", "RS256")
                    Text(
                        stringResource(R.string.home_metadata_footer),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }

    inspecting?.let { identity ->
        IdentityEditor(session, EditorMode.Inspect(identity), onDismiss = { inspecting = null })
    }
}
