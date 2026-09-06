package jp.co.pendako.siop.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import jp.co.pendako.siop.SelfIssuedIdToken

/**
 * Shown when the app is opened directly: the identity this device presents,
 * and the static metadata a Self-Issued OP advertises (Section 7.1).
 */
@Composable
fun IdentityScreen(identity: AuthenticationSession.Identity?) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Self-Issued OP", style = MaterialTheme.typography.titleLarge)

        if (identity == null) {
            Text("鍵を準備できませんでした", color = MaterialTheme.colorScheme.error)
            return@Column
        }

        Text("この端末の識別子", style = MaterialTheme.typography.titleSmall)
        Field("sub", identity.subject)
        Field("kty", identity.jwk.kty)
        Field("alg", "RS256")
        Text(
            "sub は公開鍵の JWK サムプリント(RFC 7638)です。RP ごとに固定の値を提示します。",
            style = MaterialTheme.typography.bodySmall,
        )

        Text("公開鍵 (sub_jwk)", style = MaterialTheme.typography.titleSmall)
        Text(
            text = identity.jwk.n,
            style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
        )

        Text("Discovery メタデータ", style = MaterialTheme.typography.titleSmall)
        Field("issuer", SelfIssuedIdToken.ISSUER)
        Field("authorization_endpoint", "openid:")
        Field("response_types", "id_token")
        Text(
            "openid:// で始まる認証リクエストを受け取ると、同意画面を表示します。",
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
internal fun Field(name: String, value: String) {
    Column {
        Text(name, style = MaterialTheme.typography.labelMedium)
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
        )
    }
}
