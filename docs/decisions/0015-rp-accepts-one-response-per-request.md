# 0015 — The test RP accepts one response per request, and each result page judges once

## Context

The nonce is what lets a Client detect a replayed ID Token (OpenID Connect Core 1.0 Sections
3.2.2.11 and 15.5.2), so a response is accepted once for the request it answers and never again.
The RP is a static page that verifies in the browser, and the fragment carrying the token never
reaches its server ([0006](0006-rp-verifies-in-the-browser.md)). There is no server state to hold
the rule, so it has to hold in the browser: in localStorage, which every tab of the origin shares,
and with Web Locks, since localStorage has no compare-and-remove.

The rule was built up one review finding at a time, and nine rounds each found another path through
it: the request consumed before the response was correlated with it; an unsolicited response
without a state consuming it; two tabs both accepting; the check and the removal not atomic across
tabs; the request page writing a spent request back; a check against a changed expectation showing
success; spent nonces forgotten by count while their tokens were still valid; a redraw on the same
page losing the claim. Each fix was local, and the rule itself was written down nowhere, so there was
nothing to check the next change against.

## Decision

The RP holds these together, for each request a browser records:

1. **Only a response that passes every check against the request as recorded claims it.** A stale
   or unsolicited response, with a state or without, never consumes it.
2. **At most one response per request is accepted, across every tab of the origin.** Finding the
   record and removing it happen under one Web Lock, and the request page writes new records under
   the same lock. A browser without Web Locks accepts nothing.
3. **A nonce accepted once is never accepted again while a token carrying it could still pass** —
   until its `exp` plus the verifier's 120-second skew, however many other nonces are accepted in the
   meantime and even if the record is written back. It is recorded as spent before the request is
   removed.
4. **A check against a changed expectation never shows success and never claims.** The result page
   can replace one expectation to watch a check fail; that is never an authentication.
5. **Each result page judges once.** When it loads, it checks the response against the request as
   recorded and, if every check passes, claims it; that judgement is then fixed. Switching language
   or scenario redraws from it and cannot claim, so no redraw can race the claim, lose it, or
   contradict it. A new fragment reloads the page, so a new response is judged on its own.
6. **When in doubt, nothing is accepted, and the page says why** — storage that cannot be read or
   written, no Web Locks, no expiry, or a token that expired while waiting for the lock.

The rule lives in `rp/public/pending.js` (the record, the claim, the spent nonces) and
`rp/public/callback.js` (the one judgement per page); the request page, `rp/public/app.js`, only
writes records.

## Consequences

A response is judged in the browser that sent the request. One that lands in another browser finds
no record and fails closed; that is the price of keeping the token off the server.

Editing a request after it was sent supersedes it: the request page writes the new record, and a
response to the old one is refused. The request page withholds its start link until the record is
written, since a response to an unrecorded request could never be accepted.

Failing closed can cost a legitimate response: a nonce marked spent whose request could not then be
removed is burnt, and an unreadable list of spent nonces blocks every acceptance until storage is
cleared. Both need storage to fail, or code other than the RP's to write it.

Changing any of the six points above is a new record, not an edit of this one.
