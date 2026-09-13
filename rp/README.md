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
3. Press "Choose an identity in SIOP →" to open `openid://...`
4. When the OP returns the response in the fragment of `redirect_uri`, the result page lays each
   value this RP sent beside the one that came back, with a verdict for every check

The pages follow the browser's language — English, or Japanese where the browser prefers it. The
switch in the header, or `?lang=en` / `?lang=ja` in the URL, overrides that and is remembered in
this browser. Switching redraws the page in place, so a result already checked is not lost.

### The request is editable

Every parameter can be changed, and more can be added. Values that depart from the spec are
reported under "Departures from the spec" as warnings, but sending is never blocked — seeing how an OP handles
a malformed request is the point, so `response_type=code` or a missing nonce can be sent as-is.

Each parameter carries the section number it comes from. The ones the response will be checked
against — `client_id`, `nonce`, `state` — are marked, and listed again as the values the RP keeps
for the comparison. The response side lists the received fragment parameters in the same form.
Once a response has been accepted in another tab, the request page prepares a fresh nonce and state
for the next request, and the result page never accepts the same nonce twice.

### Watching a check fail

A token cannot be changed once it has arrived, but what the RP expects can. The result page
re-checks the same token against a different `nonce`, `state` or `aud`, so one check fails while
every other still shows as passed. The token itself is never touched, and a check against a changed
expectation is never an authentication, whatever it finds.

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
| state | The fragment's `state` matches the one sent — checked apart from the token, which does not carry it |
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
- `test/state.test.mjs` — the `state` comparison, which happens outside the token
- `test/pending.test.mjs` — one response, and only one, is accepted for a request, even when two
  tabs claim it at once: finding the record and removing it run under a Web Lock every tab of the
  origin shares, and a browser without Web Locks accepts nothing. A nonce accepted once is not
  accepted again while its token is still valid, however many others follow and even if its record
  is written back
- `test/request.test.mjs` — the spec's rules on the request itself. Section 3.2.2.1 allows an
  http `redirect_uri` only to a native app, and only on the three hosts it names — `localhost`,
  `127.0.0.1`, `[::1]`. This RP is a web page, so it reports even its own default

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

### With Terraform

`deploy/gcp/` describes the same deployment in Terraform — the Cloud Run service, the registry its
images go to, and the APIs they need — so that what was created is written down. Each cloud gets a
directory of its own under `deploy/`, since Terraform reads every `.tf` file in a directory as one
configuration:

```
rp/deploy/gcp/deploy.sh <gcp-project> [region]     # region defaults to asia-northeast1
```

The image is built by Cloud Build, since Cloud Run runs amd64 and a Mac builds arm64, and is tagged
with the commit and a suffix unique to the build. Cloud Run is given the image's digest rather than
the tag, so what runs is exactly what was built. The script first enables the two APIs Terraform
works through (Cloud Resource Manager and Service Usage), then applies once to create the registry,
builds, and applies again. It applies without asking — running it is the approval — so to see what
it would change, run `terraform plan` in `deploy/gcp/` first. `terraform output url` there prints
where the RP is.

The state stays in `deploy/gcp/` and is not committed, and so does `deploy.auto.tfvars`, where the
script records the project, region and image of the last deploy. That makes `terraform plan` and
`terraform destroy` in `deploy/gcp/` work without arguments; `destroy` takes everything down again but
leaves the APIs enabled. The script never writes `terraform.tfvars`: settings of your own, such as
the service name, go there and are kept across deploys. `terraform.tfvars.sample` shows its shape,
also for running Terraform there without the script.

## Known limitations

- **Open this in your default browser.** The OP returns the response by opening `redirect_uri`,
  and iOS hands an https URL to the default browser — there is no way to return to the browser
  that started the request. Starting in a different browser means the response never arrives, and
  the localStorage holding the nonce and state is not reachable either, so the check fails. It
  fails closed: it never succeeds incorrectly.
- **The default `redirect_uri` is itself outside the spec.** Section 3.2.2.1 forbids http in the
  Implicit Flow except for a native app on localhost or a loopback address, and this RP is a web
  page, so `http://localhost:8080/callback.html` is not covered. The request page says so every
  time. To test within the spec, host the RP on https.
- Verification needs a secure context, so over plain http on a LAN address the page loads but
  cannot verify. On a desktop browser `--tls` covers it; on iOS it does not, and the RP has to be
  hosted or its certificate trusted on the device.
