import SIOPKit
import SwiftUI

/// Creating an identity, or inspecting, renaming and deleting one.
///
/// Only the names can be edited. The subject is derived from the key, so it
/// is shown but never offered as a field: a different key would be a
/// different identity.
struct IdentityEditor: View {
    enum Mode: Identifiable {
        case create(clientID: String)
        case inspect(SIOPIdentity)

        var id: String {
            switch self {
            case let .create(clientID): return "create:\(clientID)"
            case let .inspect(identity): return identity.id
            }
        }
    }

    @EnvironmentObject private var session: AuthenticationSession
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    var onCreate: (SIOPIdentity) -> Void = { _ in }

    @State private var label = ""
    @State private var note = ""
    @State private var loaded = false
    @State private var confirmsDeletion = false

    private var inspected: SIOPIdentity? {
        if case let .inspect(identity) = mode { return identity }
        return nil
    }

    private var clientID: String {
        switch mode {
        case let .create(clientID): return clientID
        case let .inspect(identity): return identity.clientID
        }
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let title: LocalizedStringKey = inspected == nil ? "Create identity" : "Identity details"
        let confirm: LocalizedStringKey = inspected == nil ? "Create" : "Save"
        return NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Personal, Testing", text: $label)
                        .accessibilityIdentifier("identity-label")
                }
                Section("Note") {
                    TextField("What it is for, for your own reference", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("identity-note")
                }
                if let identity = inspected {
                    details(of: identity)
                } else {
                    Section {
                        Text(verbatim: clientID)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    } header: {
                        Text("Created for this RP")
                    } footer: {
                        Text("Creates an RSA key for this RP and derives the sub from its public key.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm) { save() }
                        .disabled(trimmedLabel.isEmpty)
                        .accessibilityIdentifier("save-identity")
                }
            }
            .alert("Delete this identity?", isPresented: $confirmsDeletion) {
                Button("Delete identity and key", role: .destructive) {
                    if let identity = inspected {
                        session.delete(identity)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(verbatim: deletionMessage)
            }
            .modifier(ReportsProblems())
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let identity = inspected {
                    label = identity.label
                    note = identity.note
                }
            }
        }
    }

    @ViewBuilder
    private func details(of identity: SIOPIdentity) -> some View {
        let jwk = session.publicKeys[identity.id]
        Section {
            Group {
                if let jwk {
                    Text(verbatim: jwk.thumbprint())
                } else {
                    Text("Key unreadable. This identity cannot answer.")
                }
            }
            .font(.footnote.monospaced())
            .textSelection(.enabled)
        } header: {
            Text("sub · derived from the public key / not editable")
        } footer: {
            Text("Only the name and note change. The public key and sub stay as they are.")
        }

        Section("RP it answers") {
            Text(verbatim: identity.clientID)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
        }

        if let jwk {
            Section {
                DisclosureGroup("Public key sub_jwk and the JSON it is derived from") {
                    Text(verbatim: Self.explanation(of: jwk))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }

        Section {
            Button("Delete identity and key", role: .destructive) {
                confirmsDeletion = true
            }
            .accessibilityIdentifier("delete-identity")
        }
    }

    private var deletionMessage: String {
        guard let identity = inspected else { return "" }
        let subject = session.subject(of: identity) ?? String(localized: "(key unreadable)")
        let consequence = String(localized: "The signing key is deleted too. Unless the key is restored from a backup, this sub can never answer again. This does not delete the account the RP holds.")
        return "\(identity.displayName)\n\(subject)\n\n\(consequence)"
    }

    private func save() {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let identity = inspected {
            session.relabel(identity, label: trimmedLabel, note: note)
            dismiss()
        } else if let created = session.createIdentity(for: clientID, label: trimmedLabel, note: note) {
            onCreate(created)
            dismiss()
        }
    }

    private static func explanation(of jwk: RSAPublicJWK) -> String {
        """
        sub_jwk
        {
          "kty": "\(jwk.kty)",
          "e": "\(jwk.e)",
          "n": "\(jwk.n)"
        }

        \(String(localized: "JSON the thumbprint is taken over"))
        \(jwk.canonicalJSON)

        SHA-256 → Base64url
        \(jwk.thumbprint())
        """
    }
}
