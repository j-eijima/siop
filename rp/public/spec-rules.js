// Rules the spec lays on a request, kept apart from the page so they can be
// tested under Node.

/// The only hosts OpenID Connect Core 3.2.2.1 names, spelled exactly as it
/// names them. Nothing else counts — not 127.0.0.2, not a name that merely
/// begins with "localhost".
const LOOPBACK = new Set(["localhost", "127.0.0.1", "[::1]"]);

/// OpenID Connect Core 3.2.2.1: in the Implicit Flow the redirection URI MUST
/// NOT use the http scheme unless the Client is a native application, which
/// MAY use it with localhost or the loopback literals 127.0.0.1 and [::1].
///
/// The exception belongs to the kind of client, not to the network path: a
/// web page on localhost never leaves the machine either, and is still not
/// covered. Other schemes are not this rule's business, and a value that does
/// not parse as a URL is left to the checks that are.
export function httpRedirectForbidden(uri, { native = false } = {}) {
  let url;
  try {
    url = new URL(uri);
  } catch {
    return false;
  }
  return url.protocol === "http:" && !(native && LOOPBACK.has(url.hostname));
}
