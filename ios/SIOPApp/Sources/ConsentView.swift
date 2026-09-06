import SIOPKit
import SwiftUI

/// Consent screen for an incoming request. A Self-Issued OP cannot
/// authenticate the RP, so the redirect URI is shown as-is and labelled as
/// unverified rather than dressed up as a trusted identity.
struct ConsentView: View {
    @EnvironmentObject private var session: AuthenticationSession

    let request: AuthorizationRequest

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text(request.clientID)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("要求元 (client_id / redirect_uri)")
                } footer: {
                    Text("この URL は検証されていません。心当たりのある相手か確認してください。")
                }

                Section {
                    ForEach(request.scope, id: \.self) { scope in
                        LabeledContent(scope, value: Self.description(for: scope))
                    }
                } header: {
                    Text("要求されている scope")
                } footer: {
                    Text(request.scope.contains(where: { $0 != "openid" })
                         ? "現在の実装が返すのは識別子(sub)のみで、その他の属性は含まれません。"
                         : "識別子(sub)のみを返します。")
                }

                Section {
                    if let subject = session.establishedSubject(for: request.clientID) {
                        Text(subject)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } else {
                        Text("この要求元は初めてです。応答すると、この要求元専用の識別子を作成します。")
                            .font(.callout)
                    }
                } header: {
                    Text("この要求元に提示する識別子 (sub)")
                } footer: {
                    Text("この要求元専用の値です。他の RP には別の値を提示します。")
                }

                Section("リクエスト詳細") {
                    LabeledContent("response_type", value: request.responseType)
                    LabeledContent("nonce") {
                        Text(request.nonce).font(.caption.monospaced())
                    }
                    if let state = request.state {
                        LabeledContent("state") {
                            Text(state).font(.caption.monospaced())
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                Button {
                    session.approve(request)
                } label: {
                    Text("この識別子で応答する").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .cancel) {
                    session.decline(request)
                } label: {
                    Text("拒否する").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(20)
            .background(.bar)
        }
    }

    private static func description(for scope: String) -> String {
        switch scope {
        case "openid": return "識別子の提供"
        case "profile": return "プロフィール"
        case "email": return "メールアドレス"
        case "address": return "住所"
        case "phone": return "電話番号"
        default: return "—"
        }
    }
}
