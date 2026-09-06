import SIOPKit
import SwiftUI

/// Shown when the app is opened directly: the identity this device presents,
/// plus the static metadata a Self-Issued OP advertises (Section 7.1).
struct IdentityView: View {
    let identity: AuthenticationSession.Identity?

    var body: some View {
        List {
            Section {
                if let identity {
                    LabeledContent("sub") {
                        Text(identity.subject)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("kty", value: identity.jwk.kty)
                    LabeledContent("alg", value: "RS256")
                    if !identity.isPersistent {
                        Label("Keychain が使えないため一時鍵で動作しています。再起動すると sub が変わります。", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("鍵を準備できませんでした").foregroundStyle(.red)
                }
            } header: {
                Text("この端末の識別子")
            } footer: {
                Text("sub は公開鍵の JWK サムプリント(RFC 7638)です。RP ごとに固定の値を提示します。")
            }

            if let identity {
                Section("公開鍵 (sub_jwk)") {
                    Text(identity.jwk.n)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                LabeledContent("issuer", value: SelfIssuedIDToken.issuer)
                LabeledContent("authorization_endpoint", value: "openid:")
                LabeledContent("response_types", value: "id_token")
            } header: {
                Text("Discovery メタデータ")
            } footer: {
                Text("openid:// で始まる認証リクエストを受け取ると、同意画面を表示します。")
            }
        }
    }
}
