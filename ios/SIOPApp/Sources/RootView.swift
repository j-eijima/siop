import SIOPKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: AuthenticationSession

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .idle:
                    HomeView()
                case let .consent(request):
                    ConsentView(request: request)
                case let .delivering(clientID):
                    ResultView(
                        symbol: "paperplane.fill",
                        tint: .accentColor,
                        title: "Returning the response",
                        message: Text("Opening \(clientID)."),
                        detail: nil
                    )
                case let .sent(clientID, redirectURL):
                    ResultView(
                        symbol: "checkmark.seal.fill",
                        tint: .green,
                        title: "ID Token returned",
                        message: Text("Sent the response to \(clientID)."),
                        detail: redirectURL.absoluteString
                    )
                case let .undeliverable(clientID, redirectURL):
                    ResultView(
                        symbol: "arrow.uturn.left.circle.fill",
                        tint: .orange,
                        title: "Response not delivered",
                        message: Text("No app can open \(clientID). The ID Token was issued but has not reached the RP."),
                        detail: redirectURL.absoluteString
                    )
                case let .declined(clientID):
                    ResultView(
                        symbol: "hand.raised.fill",
                        tint: .orange,
                        title: "Request declined",
                        message: Text("Returned access_denied to \(clientID)."),
                        detail: nil
                    )
                case let .failed(message):
                    ResultView(
                        symbol: "exclamationmark.triangle.fill",
                        tint: .red,
                        title: "Could not process the request",
                        // Already translated where it was made.
                        message: Text(verbatim: message),
                        detail: nil
                    )
                }
            }
            .navigationTitle(Text(verbatim: "Self-Issued OP"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .modifier(ReportsProblems())
    }
}

/// Terminal state of one request, with a way back to the identity screen.
private struct ResultView: View {
    @EnvironmentObject private var session: AuthenticationSession

    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let message: Text
    let detail: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(tint)
            Text(title)
                .font(.title3.bold())
            message
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let detail {
                ScrollView {
                    Text(verbatim: detail)
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
            Button("Close") { session.reset() }
                .buttonStyle(.bordered)
        }
        .padding(24)
    }
}
