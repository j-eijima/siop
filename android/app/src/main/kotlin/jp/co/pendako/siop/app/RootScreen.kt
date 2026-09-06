package jp.co.pendako.siop.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp

/**
 * @param onRespond opens the RP's redirect URI, returning false when no app can
 *   handle it.
 */
@Composable
fun RootScreen(session: AuthenticationSession, onRespond: (String) -> Boolean) {
    when (val phase = session.phase) {
        is AuthenticationSession.Phase.Idle ->
            IdentityScreen(session.hasKeys)

        is AuthenticationSession.Phase.Consent ->
            ConsentScreen(
                request = phase.request,
                subject = session.establishedSubject(phase.request.clientId),
                onApprove = { session.approve(phase.request, onRespond) },
                onDecline = { session.decline(phase.request, onRespond) },
            )

        is AuthenticationSession.Phase.Sent ->
            ResultScreen(
                title = "ID Token を返しました",
                message = "${phase.clientId} に応答を送信しました。",
                detail = phase.redirectUrl,
                onClose = session::reset,
            )

        is AuthenticationSession.Phase.Declined ->
            ResultScreen(
                title = "リクエストを拒否しました",
                message = "${phase.clientId} に access_denied を返しました。",
                detail = null,
                onClose = session::reset,
            )

        is AuthenticationSession.Phase.Undeliverable ->
            ResultScreen(
                title = "応答を渡せませんでした",
                message = "${phase.clientId} を開けるアプリがありません。" +
                    "ID Token は発行済みですが、RP には届いていません。",
                detail = phase.redirectUrl,
                onClose = session::reset,
            )

        is AuthenticationSession.Phase.Failed ->
            ResultScreen(
                title = "処理できませんでした",
                message = phase.message,
                detail = null,
                onClose = session::reset,
            )
    }
}

@Composable
private fun ResultScreen(title: String, message: String, detail: String?, onClose: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge)
        Text(message, style = MaterialTheme.typography.bodyMedium)
        if (detail != null) {
            Text(
                text = detail,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.semantics { contentDescription = "response-redirect-url" },
            )
        }
        OutlinedButton(onClick = onClose, modifier = Modifier.fillMaxWidth()) { Text("閉じる") }
    }
}
