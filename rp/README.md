# SIOP test RP

**English** | [日本語](README.ja.md)

A Relying Party for exercising a Self-Issued OpenID Provider (OpenID Connect Core 1.0,
Section 7).

It builds an authentication request, hands it to the OP, and verifies the returned ID Token by
the steps in Section 7.5. Verification runs entirely in the browser using WebCrypto: the Implicit
Flow returns the response in the URL fragment, and browsers do not send fragments to the server,
so the ID Token never reaches one.

## Starting it

```
python3 serve.py            # http://localhost:8080/
python3 serve.py --tls      # https://<this Mac's LAN address>:8443/
python3 serve.py --port 9000
```

It only serves static files. There are no dependencies to install.

Verification runs on WebCrypto, which is only available in a secure context: `http://localhost`
counts as one, a LAN address over plain HTTP does not. A device reaching this over the LAN
therefore gets a page that loads and cannot verify anything.

`--tls` serves HTTPS with a self-signed certificate, generated on first use. That is enough for a
desktop browser, where the warning can be clicked through. **It is not enough for iOS**: Safari
rejects a certificate it does not trust outright, with nothing offered to click, so the page
simply never loads. Getting an iPhone or iPad to verify means either installing and trusting the
certificate on the device, or serving the RP from somewhere that has a real one. A name from a
wildcard DNS service does not help either way — the secure-context rule is about the scheme, not
the name.

## Using it

1. Open `http://localhost:8080/`
2. Edit the parameters as needed — the defaults are the smallest request the spec allows
3. Press "SIOP アプリで認証する" to open `openid://...`
4. When the OP returns the response in the fragment of `redirect_uri`, the verification result
   appears

### The request is editable

Every parameter can be changed, and more can be added. Values that depart from the spec are
reported under "仕様との差分" as warnings, but sending is never blocked — seeing how an OP handles
a malformed request is the point, so `response_type=code` or a missing nonce can be sent as-is.

Each parameter carries the section number it comes from. The response side lists the received
fragment parameters and the ID Token claims in the same form.

## What is checked (Section 7.5)

| Check | Detail |
|---|---|
| JWS structure | Splits into three segments; header and payload parse as JSON |
| alg | `RS256`, the algorithm Section 7.1 requires |
| iss | `https://self-issued.me` |
| sub_jwk | Carries an RSA public key |
| sub | Equals the JWK thumbprint (RFC 7638) of `sub_jwk` |
| signature | Verifies against the key in `sub_jwk` |
| aud | Addressed to this RP's `client_id` |
| nonce | Matches the value sent in the request |
| exp | Not expired |

A failure does not stop the run: every check is reported so the whole picture is visible.

## Tests

```
node --test
```

Node is all that is needed; there are no dependencies.

- `test/verify.test.mjs` — verifies a real ID Token signed by Swift (`ios/SIOPKit`) and committed
  as `test/fixtures/swift-issued.json`. It also confirms that tampering, a mismatched aud, a
  mismatched nonce, and expiry are all rejected
- `test/cross-implementation.test.mjs` — the same checks against a token from the **current**
  Swift build, so a stale fixture cannot hide an interoperability regression. Skipped
  automatically where SIOPKit cannot be built

Refresh the fixture with `test/fixtures/regenerate.sh` (needs Swift).

The end-to-end test that includes the iOS app is
`ios/SIOPApp/UITests/EndToEndRPTests.swift` (it needs this server running).

## Hosting it

The server takes its port from `$PORT`, and the page derives `client_id` and `redirect_uri` from
the URL it was loaded from, so it runs anywhere that terminates TLS and assigns a port, with
nothing to configure. The `Dockerfile` builds it.

```
gcloud run deploy siop-rp --source rp --allow-unauthenticated
```

A hosted RP is the practical way to exercise a phone or tablet, since the certificate is then one
the device already trusts.

## Known limitations

- **Open this in your default browser.** The OP returns the response by opening `redirect_uri`,
  and iOS hands an https URL to the default browser — there is no way to return to the browser
  that started the request. Starting in a different browser means the response never arrives, and
  the localStorage holding the nonce and state is not reachable either, so the check fails. It
  fails closed: it never succeeds incorrectly.
- Verification needs a secure context, so over plain http on a LAN address the page loads but
  cannot verify. On a desktop browser `--tls` covers it; on iOS it does not, and the RP has to be
  hosted or its certificate trusted on the device.
