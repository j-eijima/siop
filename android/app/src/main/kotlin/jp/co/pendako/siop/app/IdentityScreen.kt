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
 * Shown when the app is opened directly. There is no single identifier to
 * show: the subject presented depends on which RP is asking, which is what
 * makes the advertised pairwise subject type true.
 */
@Composable
fun IdentityScreen(hasKeys: Boolean) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Self-Issued OP", style = MaterialTheme.typography.titleLarge)

        if (!hasKeys) {
            Text("鍵を準備できませんでした", color = MaterialTheme.colorScheme.error)
            return@Column
        }

        Text("識別子", style = MaterialTheme.typography.titleSmall)
        Text(
            "この端末は、RP ごとに別の鍵で署名します。そのため RP ごとに異なる識別子 (sub) を" +
                "提示し、同じ RP には毎回同じ識別子を提示します。",
            style = MaterialTheme.typography.bodyMedium,
        )
        Text(
            "sub は、その RP 向けの公開鍵の JWK サムプリント (RFC 7638) です。RP どうしが結託しても、" +
                "同じ利用者だと突き合わせることはできません。",
            style = MaterialTheme.typography.bodySmall,
        )

        Text("Discovery メタデータ", style = MaterialTheme.typography.titleSmall)
        Field("issuer", SelfIssuedIdToken.ISSUER)
        Field("authorization_endpoint", "openid:")
        Field("response_types", "id_token")
        Field("subject_types", "pairwise")
        Field("alg", "RS256")
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
