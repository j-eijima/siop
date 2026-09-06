import Foundation
import SIOPKit

/// Issues a self-issued ID Token for a request URL and prints the response as
/// JSON. Used to feed real, Swift-signed tokens to the RP test suite.
///
///     swift run siop-issue "openid://?response_type=id_token&client_id=...&scope=openid&nonce=n1"
///
/// Pass --expired to issue an already-expired token.

let arguments = CommandLine.arguments.dropFirst()
guard let requestURL = arguments.first(where: { !$0.hasPrefix("--") }).flatMap(URL.init(string:)) else {
    FileHandle.standardError.write(Data("usage: siop-issue <openid:// request URL> [--expired]\n".utf8))
    exit(2)
}
let issuedAt = arguments.contains("--expired") ? Date(timeIntervalSinceNow: -3600) : Date()

do {
    let op = SelfIssuedOP(keyStore: EphemeralKeyStore())
    let request = try AuthorizationRequest(url: requestURL)
    let response = try op.respond(to: request, now: issuedAt)
    let output: [String: Any] = [
        "id_token": response.idToken,
        "redirect_url": response.redirectURL.absoluteString,
        "sub": try op.subject(for: request.clientID),
    ]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
