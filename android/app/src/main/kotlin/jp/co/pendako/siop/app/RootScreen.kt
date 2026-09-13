package jp.co.pendako.siop.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * @param onRespond opens the RP's redirect URI, returning false when no app can
 *   handle it.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun RootScreen(session: AuthenticationSession, onRespond: (String) -> Boolean) {
    // Test tags double as resource ids, so the end-to-end test — which drives
    // the browser and the app together through UI Automator — can find the
    // buttons whatever language the device is in.
    Box(Modifier.semantics { testTagsAsResourceId = true }) {
        when (val phase = session.phase) {
            AuthenticationSession.Phase.Idle -> HomeScreen(session)

            is AuthenticationSession.Phase.Consent -> ConsentScreen(
                session = session,
                request = phase.request,
                onApprove = { session.approve(phase.request, it, onRespond) },
                onDecline = { session.decline(phase.request, onRespond) },
            )

            is AuthenticationSession.Phase.Sent -> ResultScreen(
                symbol = "✓",
                tint = Palette.key,
                title = stringResource(R.string.result_sent_title),
                message = stringResource(R.string.result_sent_message, phase.clientId),
                detail = phase.redirectUrl,
                onClose = session::reset,
            )

            is AuthenticationSession.Phase.Undeliverable -> ResultScreen(
                symbol = "↩",
                tint = Palette.caution,
                title = stringResource(R.string.result_undeliverable_title),
                message = stringResource(R.string.result_undeliverable_message, phase.clientId),
                detail = phase.redirectUrl,
                onClose = session::reset,
            )

            is AuthenticationSession.Phase.Declined -> ResultScreen(
                symbol = "✋",
                tint = Palette.caution,
                title = stringResource(R.string.result_declined_title),
                message = stringResource(R.string.result_declined_message, phase.clientId),
                detail = null,
                onClose = session::reset,
            )

            is AuthenticationSession.Phase.Failed -> ResultScreen(
                symbol = "⚠",
                tint = Palette.danger,
                title = stringResource(R.string.result_failed_title),
                message = describe(phase.failure),
                detail = null,
                onClose = session::reset,
            )
        }

        session.problem?.let { problem ->
            AlertDialog(
                onDismissRequest = { session.problem = null },
                title = { Text(stringResource(R.string.problem_title)) },
                text = { Text(describe(problem)) },
                confirmButton = {
                    TextButton(onClick = { session.problem = null }) { Text(stringResource(R.string.ok)) }
                },
            )
        }
    }
}

/** Terminal state of one request, with a way back to the identities. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ResultScreen(
    symbol: String,
    tint: Color,
    title: String,
    message: String,
    detail: String?,
    onClose: () -> Unit,
) {
    Scaffold(topBar = { CenterAlignedTopAppBar(title = { Text("Self-Issued OP") }) }) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(
                Modifier.widthIn(max = 720.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(symbol, fontSize = 56.sp, color = tint, modifier = Modifier.clearAndSetSemantics {})
                Text(title, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold))
                Text(
                    message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
                if (detail != null) {
                    SelectionContainer {
                        Text(
                            detail,
                            style = MaterialTheme.typography.bodySmall.mono(),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(10.dp))
                                .padding(12.dp)
                                .testTag("response-redirect-url"),
                        )
                    }
                }
                OutlinedButton(onClick = onClose) { Text(stringResource(R.string.close)) }
            }
        }
    }
}
