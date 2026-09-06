import SIOPKit
import SwiftUI

/// Shown when the app is opened directly. There is no single identifier to
/// show: the subject presented depends on which RP is asking, which is what
/// makes the advertised pairwise subject type true.
struct IdentityView: View {
    let keyState: AuthenticationSession.KeyState?

    var body: some View {
        List {
            Section {
                Text("この端末は、RP ごとに別の鍵で署名します。そのため RP ごとに異なる識別子 (sub) を提示し、同じ RP には毎回同じ識別子を提示します。")
                    .font(.callout)
                if let keyState, !keyState.isPersistent {
                    Label(
                        "Keychain が使えないため一時鍵で動作しています。再起動すると識別子が変わります。",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("識別子")
            } footer: {
                Text("sub は、その RP 向けの公開鍵の JWK サムプリント (RFC 7638) です。RP どうしが結託しても、同じ利用者だと突き合わせることはできません。")
            }

            Section {
                LabeledContent("issuer", value: SelfIssuedIDToken.issuer)
                LabeledContent("authorization_endpoint", value: "openid:")
                LabeledContent("response_types", value: "id_token")
                LabeledContent("subject_types", value: "pairwise")
                LabeledContent("alg", value: "RS256")
            } header: {
                Text("Discovery メタデータ")
            } footer: {
                Text("openid:// で始まる認証リクエストを受け取ると、同意画面を表示します。")
            }
        }
    }
}
