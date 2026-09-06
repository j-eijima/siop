import SIOPKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: AuthenticationSession

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .idle:
                    IdentityView(identity: session.identity)
                case let .consent(request):
                    ConsentView(request: request)
                case let .delivering(clientID):
                    ResultView(
                        symbol: "paperplane.fill",
                        tint: .accentColor,
                        title: "応答を返しています",
                        message: "\(clientID) を開いています。",
                        detail: nil
                    )
                case let .sent(clientID, redirectURL):
                    ResultView(
                        symbol: "checkmark.seal.fill",
                        tint: .green,
                        title: "ID Token を返しました",
                        message: "\(clientID) に応答を送信しました。",
                        detail: redirectURL.absoluteString
                    )
                case let .undeliverable(clientID, redirectURL):
                    ResultView(
                        symbol: "arrow.uturn.left.circle.fill",
                        tint: .orange,
                        title: "応答を渡せませんでした",
                        message: "\(clientID) を開けるアプリがありません。ID Token は発行済みですが、RP には届いていません。",
                        detail: redirectURL.absoluteString
                    )
                case let .declined(clientID):
                    ResultView(
                        symbol: "hand.raised.fill",
                        tint: .orange,
                        title: "リクエストを拒否しました",
                        message: "\(clientID) に access_denied を返しました。",
                        detail: nil
                    )
                case let .failed(message):
                    ResultView(
                        symbol: "exclamationmark.triangle.fill",
                        tint: .red,
                        title: "処理できませんでした",
                        message: message,
                        detail: nil
                    )
                }
            }
            .navigationTitle("Self-Issued OP")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Terminal state of one request, with a way back to the identity screen.
private struct ResultView: View {
    @EnvironmentObject private var session: AuthenticationSession

    let symbol: String
    let tint: Color
    let title: String
    let message: String
    let detail: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(tint)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let detail {
                ScrollView {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer()
            Button("閉じる") { session.reset() }
                .buttonStyle(.bordered)
        }
        .padding(24)
    }
}
