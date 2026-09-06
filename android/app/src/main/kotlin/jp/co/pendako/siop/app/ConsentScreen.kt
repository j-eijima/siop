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
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import jp.co.pendako.siop.AuthorizationRequest

/**
 * Consent for an incoming request. A Self-Issued OP cannot authenticate the
 * RP, so the redirect URI is shown as-is and labelled unverified rather than
 * dressed up as a trusted identity.
 */
@Composable
fun ConsentScreen(
    request: AuthorizationRequest,
    onApprove: () -> Unit,
    onDecline: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Self-Issued OP", style = MaterialTheme.typography.titleLarge)

        Text("要求元 (client_id / redirect_uri)", style = MaterialTheme.typography.titleSmall)
        Field("client_id", request.clientId)
        Text(
            "この URL は検証されていません。心当たりのある相手か確認してください。",
            style = MaterialTheme.typography.bodySmall,
        )

        Text("要求されている scope", style = MaterialTheme.typography.titleSmall)
        request.scope.forEach { scope -> Field(scope, scopeDescription(scope)) }
        Text(
            if (request.scope.any { it != "openid" }) {
                "現在の実装が返すのは識別子(sub)のみで、その他の属性は含まれません。"
            } else {
                "識別子(sub)のみを返します。"
            },
            style = MaterialTheme.typography.bodySmall,
        )

        Text("リクエスト詳細", style = MaterialTheme.typography.titleSmall)
        Field("response_type", request.responseType)
        Field("nonce", request.nonce)
        request.state?.let { Field("state", it) }

        Button(onClick = onApprove, modifier = Modifier.fillMaxWidth().padding(top = 12.dp)) {
            Text("この識別子で応答する")
        }
        OutlinedButton(onClick = onDecline, modifier = Modifier.fillMaxWidth()) {
            Text("拒否する")
        }
    }
}

private fun scopeDescription(scope: String): String = when (scope) {
    "openid" -> "識別子の提供"
    "profile" -> "プロフィール"
    "email" -> "メールアドレス"
    "address" -> "住所"
    "phone" -> "電話番号"
    else -> "—"
}
