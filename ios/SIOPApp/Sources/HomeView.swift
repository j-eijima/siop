import SIOPKit
import SwiftUI

/// Shown when the app is opened directly: every identity on the device,
/// grouped by the RP it answers, and the Discovery metadata.
///
/// Nothing is created here. An identity belongs to one RP, so there is nothing
/// to make one for until an RP asks.
struct HomeView: View {
    @EnvironmentObject private var session: AuthenticationSession
    @State private var inspecting: SIOPIdentity?

    /// Identities grouped by the RP they answer, the RP answered most recently
    /// first.
    private var byRP: [(clientID: String, identities: [SIOPIdentity])] {
        var order: [String] = []
        var groups: [String: [SIOPIdentity]] = [:]
        for identity in session.identities {
            if groups[identity.clientID] == nil { order.append(identity.clientID) }
            groups[identity.clientID, default: []].append(identity)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Text("Each identity is a separate key for one RP. You can answer the same RP as several identities, but no identity is ever used with another RP.")
                    .font(.callout)
            } header: {
                Text("Your identities")
            } footer: {
                Text("sub is the JWK thumbprint (RFC 7638) of the public key. Even RPs working together cannot tell they share a user.")
            }

            if byRP.isEmpty {
                Section {
                    Text("No identities yet. When an RP sends an authentication request, you can create an identity for it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(byRP, id: \.clientID) { group in
                Section {
                    ForEach(group.identities) { identity in
                        Button {
                            inspecting = identity
                        } label: {
                            IdentityRow(identity: identity, subject: session.subject(of: identity))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(verbatim: group.clientID)
                        .font(.caption.monospaced())
                        .textCase(nil)
                }
            }

            // Protocol vocabulary, shown as the metadata spells it.
            Section {
                LabeledContent { Text(verbatim: SelfIssuedIDToken.issuer) } label: { Text(verbatim: "issuer") }
                LabeledContent { Text(verbatim: "openid:") } label: { Text(verbatim: "authorization_endpoint") }
                LabeledContent { Text(verbatim: "id_token") } label: { Text(verbatim: "response_types") }
                LabeledContent { Text(verbatim: "pairwise") } label: { Text(verbatim: "subject_types") }
                LabeledContent { Text(verbatim: "RS256") } label: { Text(verbatim: "alg") }
            } header: {
                Text("Discovery metadata")
            } footer: {
                Text("When an authentication request starting with openid:// arrives, the app asks which identity should answer.")
            }
        }
        .sheet(item: $inspecting) { identity in
            IdentityEditor(mode: .inspect(identity))
                .environmentObject(session)
        }
    }
}
