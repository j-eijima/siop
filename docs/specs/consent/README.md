# Consent and the response preview

**English** | [日本語](README.ja.md)

Nothing is signed before the user has seen what would be signed and where it would go. This is the
one screen a person must read, so it is specified rather than left to the implementation.

## Where this stands

Partly built. Both apps receive the request on `openid:` and show a consent screen carrying the
requesting `client_id`, the requested scope, `response_type`, `nonce` and `state`, and either the
subject already established for that Relying Party or a note that responding will create one.
Declining already returns `access_denied`. Not built: the public key is not shown before signing,
the full parameter view described in [parameters/](../parameters/) is not there, and neither is the
identity choice described in [identity/](../identity/).

## Behaviour

```gherkin
Feature: Consent and the response preview

  Background:
    Given a Relying Party has sent an authentication request to openid://

  Scenario: Showing what is about to be signed
    Given an identity on this device has already answered this Relying Party
    When the app asks the user whether to respond
    Then the client_id that sent the request is shown as it arrived
    And the redirect URI the response will be sent to is shown
    And the subject identifier that will appear in sub is shown
    And the public key that will travel as sub_jwk is shown

  Scenario: A Relying Party that has not been answered before
    Given no identity on this device has answered this Relying Party
    When the app asks the user whether to respond
    Then the client_id and the redirect URI are shown as above
    And the app says a new subject will be created if the user responds
    And no subject or public key is shown, because none exists yet

  Scenario: Declining
    When the user declines
    Then error=access_denied is returned to the Relying Party through the redirect URI
    And the app says which Relying Party was answered that way

  Scenario: Approving
    When the user approves
    Then the ID Token is handed back through the redirect URI that was shown

  Scenario: A response that cannot be delivered
    Given nothing on the device can open the redirect URI
    When the user approves
    Then the app says the ID Token was issued and did not reach the Relying Party
```

## Constraints

- The SIOP app shall not create a signing key for a Relying Party before the user has responded to
  that Relying Party.
- The SIOP app shall not issue an ID Token the user has not approved. Declining is an answer, not
  silence: the Relying Party is told, and told only that.
- If the request is missing a parameter the OP requires, then the SIOP app shall name the missing
  parameter and shall not ask for consent.
- If the request cannot be parsed at all, then the SIOP app shall say so and shall not contact the
  redirect URI it failed to read.
- While the app is waiting for the user's answer, the SIOP app shall show the values it will sign
  rather than a summary of them.

## Checked by test instead

That the token the Relying Party receives validates under Section 7.5 is decided end to end by
`ios/SIOPApp/UITests/EndToEndRPTests.swift` and by the cross-implementation suites in `rp/test/`.
The scenarios above stop at the point the response leaves the app.
