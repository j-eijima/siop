# Making the protocol legible

**English** | [日本語](README.ja.md)

The highest priority for both the SIOP app and the test RP is that a person can understand the
protocol parameters: their actual values, where each came from, and how request fields, response
fields, and validation expectations line up. Everything else in the UI comes after this.

## Where this stands

A requirement on both sides, met so far only by the
[HTML UI mock](../../../rp/public/mock.html), which runs real WebCrypto operations against
temporary in-memory keys without contacting an external RP. The mock is a demonstration of the
intended behaviour, not an implementation of it and not an interoperability test.

## Constraints

Most of what this subject asks for holds at all times rather than at a moment, so it is stated as
requirements rather than scenarios.

- The SIOP app shall show each parameter of a received request with the value that arrived, not a
  normalised or re-encoded form of it.
- The SIOP app shall distinguish values that came from the Relying Party from values the device
  produced.
- The RP shall show each parameter of a request with the value it will send, before it is sent.
- The RP shall mark the parameters it will check the response against.
- The RP shall report each Section 7.5 check on its own, and shall not reduce the result to a
  single pass or fail.
- The RP shall make the ID Token available in its encoded form and as a decoded header and
  payload.
- Where a value is derived rather than received, the app showing it shall say what it was derived
  from.

## Behaviour

```gherkin
Feature: Reading a verification result

  Scenario: Comparing a response against what was expected
    Given the RP has received an ID Token
    When the verification result is shown
    Then each checked claim is shown beside the value that was expected

  Scenario: A check that fails
    Given a response whose nonce does not match the request
    When the verification result is shown
    Then the failing check is named
    And the received value and the expected value are both shown
    And the checks that passed are still shown as passed
```

## Checked by test instead

Whether each Section 7.5 check reaches the right verdict is decided by `rp/test/verify.test.mjs`
and the validator tests in each implementation. What is specified here is only that a person can
see the values and the verdicts.
