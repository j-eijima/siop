import SIOPKit
import SwiftUI

/// Consent screen for an incoming request, laid out as the UI mock's SIOP
/// view: what arrived, who to answer as, and exactly what will be signed.
///
/// A Self-Issued OP cannot authenticate the RP, so the redirect URI is shown
/// as it arrived and labelled as unverified rather than dressed up as a
/// trusted identity.
///
/// A scroll view rather than a list: a list builds only the rows on screen,
/// and every value that will be signed has to be there to be read.
struct ConsentView: View {
    @EnvironmentObject private var session: AuthenticationSession

    let request: AuthorizationRequest

    @State private var chosenID: SIOPIdentity.ID?
    @State private var editor: IdentityEditor.Mode?
    @State private var showsWholeKey = false

    private var candidates: [SIOPIdentity] {
        session.identities(for: request.clientID)
    }

    /// The identity the response will be signed as: the one the user picked,
    /// or else the first that can sign. Nil means a new one will be made.
    private var signer: SIOPIdentity? {
        let usable = candidates.filter { session.subject(of: $0) != nil }
        return usable.first { $0.id == chosenID } ?? usable.first
    }

    /// This RP has identities but none can sign. A new one is not made in
    /// their place, since that would answer as someone else; the user can
    /// still create one on purpose.
    private var blocked: Bool {
        signer == nil && !candidates.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                requestPanel
                identityPanel
                previewPanel
                fragmentPanel
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { actionBar }
        .navigationTitle("Which identity will answer?")
        .sheet(item: $editor) { mode in
            IdentityEditor(mode: mode) { created in
                chosenID = created.id
            }
            .environmentObject(session)
        }
    }

    // MARK: - 01 What arrived

    private var requestPanel: some View {
        Panel(number: "01", title: "Request received", badge: SourceBadge("Requester unverified")) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Requester / client_id")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: request.clientID)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Text("This URL has not been verified. Make sure you recognise who is asking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            ForEach(Array(request.receivedParameters.enumerated()), id: \.offset) { _, parameter in
                ParameterRow(name: parameter.name, value: parameter.value)
            }
        }
    }

    // MARK: - Who to answer as

    private var identityPanel: some View {
        Panel(
            title: "Your identities",
            subtitle: "Choose the identity to use with this RP",
            badge: SourceBadge("\(candidates.count) identities")
        ) {
            if candidates.isEmpty {
                Text("First request from this requester. Answering creates an identity for it alone.")
                    .font(.callout)
            } else {
                ForEach(candidates) { identity in
                    identityChoice(identity)
                }
            }
            Button {
                editor = .create(clientID: request.clientID)
            } label: {
                Label("Create identity", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            Text("Names are labels on this device only. The RP receives the sub derived from the public key, and the same RP can be answered as another identity too.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func identityChoice(_ identity: SIOPIdentity) -> some View {
        let subject = session.subject(of: identity)
        let isSigner = identity.id == signer?.id
        return HStack(spacing: 12) {
            Button {
                chosenID = identity.id
            } label: {
                IdentityRow(identity: identity, subject: subject, selected: isSigner)
            }
            .buttonStyle(.plain)
            .disabled(subject == nil)

            Button {
                editor = .inspect(identity)
            } label: {
                Image(systemName: "info.circle").font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Details")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSigner ? Palette.key : Color(.separator), lineWidth: isSigner ? 2 : 1)
        )
    }

    // MARK: - 02 What will be signed

    private var previewPanel: some View {
        let jwk = signer.flatMap { session.publicKeys[$0.id] }
        let keyToggle: LocalizedStringKey = showsWholeKey ? "Collapse the public key" : "Show the whole public key"
        let minutes = Int(SelfIssuedIDToken.lifetime / 60)
        return Panel(number: "02", title: "Response preview", badge: SourceBadge("Not yet signed", source: .key)) {
            Group {
                if let signer {
                    Text("Using the key and identity of \(signer.displayName)")
                } else {
                    Text("A new key and identity for this RP will be created when you answer")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Text("ID Token · what will be signed").font(.caption.weight(.semibold))
                Spacer()
                Text(verbatim: "RS256").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            ClaimRow(name: "iss", value: SelfIssuedIDToken.issuer, origin: "Fixed", source: .fixed)
            ClaimRow(name: "aud", value: request.clientID, origin: "From client_id", source: .request)
            ClaimRow(name: "sub", value: jwk?.thumbprint(), origin: "Derived from the public key", source: .key)
            ClaimRow(
                name: "sub_jwk",
                value: jwk.map(Self.json),
                origin: "The chosen public key",
                source: .key,
                lineLimit: showsWholeKey ? nil : 3
            )
            if jwk != nil {
                Button(keyToggle) {
                    showsWholeKey.toggle()
                }
                .font(.caption)
            }
            ClaimRow(name: "nonce", value: request.nonce, origin: "From nonce", source: .request)
            ClaimRow(
                name: "iat / exp",
                value: String(localized: "Fixed at signing / expires \(minutes) minutes after issue"),
                origin: "At signing",
                source: .fixed
            )

            SourceLegend()
            Text("Switching identities changes the green rows. The blue rows correspond to the RP's request.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !otherScopes.isEmpty {
                Text("\(otherScopes.joined(separator: " ")) requested too, but this implementation returns only sub, with no other claims.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fragmentPanel: some View {
        Panel(title: "URL fragment · outside the ID Token") {
            ClaimRow(
                name: "state",
                value: request.state ?? String(localized: "(omitted)"),
                origin: "Copied from the request",
                source: .request
            )
            Text("nonce comes back inside the signed token, state outside it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var otherScopes: [String] {
        request.scope.filter { $0 != "openid" }
    }

    /// The public key as it travels in `sub_jwk`.
    private static func json(_ jwk: RSAPublicJWK) -> String {
        "{ \"kty\": \"\(jwk.kty)\", \"e\": \"\(jwk.e)\", \"n\": \"\(jwk.n)\" }"
    }

    // MARK: - Answer

    private var actionBar: some View {
        VStack(spacing: 8) {
            Group {
                if blocked {
                    Text("This RP's identity cannot be read right now, so no new one is made in its place. Try again, or create one yourself.")
                } else if signer == nil {
                    Text("A new key will sign, and the response goes back to the requester.")
                } else {
                    Text("The chosen key will sign, and the response goes back to the requester.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                // Declining keeps its natural width, so the approve button's
                // longer title gets the rest of the bar on one line.
                Button(role: .cancel) {
                    session.decline(request)
                } label: {
                    Text("Decline").padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("decline")

                Button {
                    session.approve(request, as: signer)
                } label: {
                    Group {
                        if signer == nil {
                            Text("Use a new identity")
                        } else {
                            Text("Use this identity")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.key)
                .controlSize(.large)
                .disabled(blocked)
                .accessibilityIdentifier("approve")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
