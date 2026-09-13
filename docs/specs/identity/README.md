# Identity management and selection

**English** | [日本語](README.ja.md)

An identity is a signing key together with the subject identifier derived from it. The user can
keep several, and chooses which one answers a given Relying Party.

## Where this stands

Built on iOS. Android still holds a separate key per `client_id` and uses it automatically, so the
pairwise subject is there but the user never sees a choice. On iOS, the keys the key-per-RP version
made are taken over as identities when their Relying Party next asks, so an identity already tied
to a Relying Party stays tied to it. The [UI mock](../../../rp/public/mock.html) shows the same
shape with temporary in-memory keys.

## Behaviour

```gherkin
Feature: Identity management and selection

  Background:
    Given the SIOP app is installed on the device

  Scenario: Listing identities
    When the user opens the identity list
    Then every identity is listed with its label and its subject identifier
    And each identity shows which Relying Parties it has answered

  Scenario: Creating an identity
    When the user creates an identity and gives it a label
    Then a new signing key is generated on the device
    And the subject identifier shown is the JWK thumbprint of that key's public part

  Scenario: Inspecting an identity
    When the user opens an identity from the list
    Then the subject identifier is shown
    And the public key is shown as it will appear in sub_jwk
    And the Relying Parties this identity has answered are shown

  Scenario: Editing an identity
    When the user edits an identity
    Then the label and the note can be changed

  Scenario: Deleting an identity
    When the user deletes an identity
    Then the app states that the signing key is removed
    And the app states that this identity can never answer again unless the key is restored
    And the app states that the account the Relying Party holds is not deleted
    And the deletion takes a second, explicit confirmation

  Scenario: Choosing which identity answers a request
    Given an authentication request has arrived from a Relying Party
    When the user is asked whether to respond
    Then the identity used for the response can be changed before signing
    And the identity that has already answered this Relying Party is the one offered first

  Scenario: Answering a Relying Party for the first time
    Given the Relying Party has never been answered from this device
    When the user is asked whether to respond
    Then the app says that responding creates a new identity for this Relying Party
```

## Constraints

- The SIOP app shall derive an identity's subject identifier from its public key, and shall not
  accept a subject identifier as input.
- While an identity is being edited, the SIOP app shall not alter its signing key.
- The SIOP app shall keep an identity's association with a Relying Party until the user changes it.
- If a signing key cannot be read from the device's key store, then the SIOP app shall show the
  identity as unusable rather than omitting it from the list.
- If a Relying Party has an identity whose signing key cannot be read, then the SIOP app shall not
  answer that Relying Party as a new identity unless the user creates one.

## Checked by test instead

That the subject identifier really is the RFC 7638 thumbprint of the public key, and that two
Relying Parties receive different subjects, are decided by the unit tests in each implementation.
They are not repeated as scenarios here.
