import SIOPKit
import SwiftUI
import UIKit

/// The UI mock's palette. Blue marks a value copied from the request, green a
/// value that comes from the chosen key; everything fixed or decided at
/// signing stays grey. Switching identities changes exactly the green rows.
enum Palette {
    static let request = dynamic(light: 0x376BAF, dark: 0x8FB3EA)
    static let key = dynamic(light: 0x24664A, dark: 0x7FC4A0)
    static let danger = dynamic(light: 0xAF4540, dark: 0xF09A94)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Where a value in the response comes from.
enum ValueSource {
    case request
    case key
    case fixed

    var color: Color {
        switch self {
        case .request: return Palette.request
        case .key: return Palette.key
        case .fixed: return .secondary
        }
    }
}

struct SourceBadge: View {
    let text: LocalizedStringKey
    var source: ValueSource? = nil

    init(_ text: LocalizedStringKey, source: ValueSource? = nil) {
        self.text = text
        self.source = source
    }

    var body: some View {
        let color = source?.color ?? .secondary
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// What the three colours mean, shown beside the preview they colour.
struct SourceLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            SourceBadge("Copied from the request", source: .request)
            SourceBadge("From the chosen key", source: .key)
            SourceBadge("Fixed / at signing", source: .fixed)
        }
    }
}

/// A card with a numbered heading, as the mock lays out each step.
struct Panel<Content: View>: View {
    var number: String? = nil
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var badge: SourceBadge? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let number {
                    Text(number)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let badge { badge }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// One request parameter, name above the value exactly as it arrived.
struct ParameterRow: View {
    let name: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Group {
                if let value {
                    Text(verbatim: value)
                } else {
                    Text("(no value)")
                }
            }
            .font(.footnote.monospaced())
            .textSelection(.enabled)
        }
    }
}

/// One value of the response, with where it comes from.
///
/// The value is its own text element rather than merged with its name, so
/// that it reads — and can be copied — exactly as it will be signed. It is
/// shown verbatim: a protocol value is never translated.
struct ClaimRow: View {
    let name: String
    /// Nil when the value does not exist yet: a subject made at the moment
    /// the user answers.
    let value: String?
    let origin: LocalizedStringKey
    let source: ValueSource
    var lineLimit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.caption.monospaced().weight(.semibold))
                Spacer(minLength: 8)
                SourceBadge(origin, source: source)
            }
            if let value {
                Text(verbatim: value)
                    .font(.footnote.monospaced())
                    .lineLimit(lineLimit)
                    .textSelection(.enabled)
            } else {
                Text("Created when you answer")
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            source == .key ? Palette.key.opacity(0.07) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

/// An identity as a row: its name, its note, and its subject cut to fit.
struct IdentityRow: View {
    let identity: SIOPIdentity
    /// Nil when the key could not be read, which leaves the identity unable
    /// to answer. It is still listed, so the user can see it and delete it.
    let subject: String?
    /// Nil when the row is not something to choose between.
    var selected: Bool? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: String(identity.displayName.prefix(1)))
                .font(.headline)
                .frame(width: 36, height: 36)
                .foregroundStyle(Palette.key)
                .background(Palette.key.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: identity.displayName).font(.body.weight(.semibold))
                Group {
                    if identity.note.isEmpty {
                        Text("Identity for this RP")
                    } else {
                        Text(verbatim: identity.note)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let subject {
                    Text(verbatim: "sub \(subject)")
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Key unreadable — this identity cannot answer")
                        .font(.caption)
                        .foregroundStyle(Palette.danger)
                }
            }
            Spacer(minLength: 0)
            if let selected {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Palette.key : .secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected == true ? .isSelected : [])
    }
}

extension SIOPIdentity {
    /// What to call the identity on screen. One made by answering an RP for
    /// the first time, or taken over from the key-per-RP version, has not been
    /// named, so it goes by the RP it answers — by host where the RP is a web
    /// address, and whole otherwise, since a custom scheme's "host" is
    /// whatever follows `://` and names nothing.
    var displayName: String {
        guard label.isEmpty else { return label }
        if let url = URL(string: clientID), ["http", "https"].contains(url.scheme), let host = url.host {
            return host
        }
        return clientID
    }
}

/// Shows an identity operation that failed. Attached both to the root and to
/// the editor sheet, since an alert cannot appear beneath a sheet.
struct ReportsProblems: ViewModifier {
    @EnvironmentObject private var session: AuthenticationSession

    func body(content: Content) -> some View {
        content.alert(
            "Something went wrong",
            isPresented: Binding(
                get: { session.problem != nil },
                set: { if !$0 { session.problem = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: session.problem ?? "")
        }
    }
}
