# 0007 — A push is reviewed by the coding agent that did not write it

## Context

The same reasoning as [0002](0002-verification-across-implementations.md), applied to the work
rather than to the tokens: an agent reviewing its own output agrees with itself.

## Decision

A pre-push hook routes by the origin of the push. Claude-originated pushes require a successful
adversarial Codex review with a structured `approve` verdict; Codex-originated pushes are not
reviewed by the hook at all. Unknown or ambiguous origins are refused rather than guessed at, and
`PUSH_AGENT` states the policy explicitly when the markers cannot.

## Consequences

The gate drives the local Codex CLI under the developer's own credentials, so it cannot run in CI
and only guards machines where the hook is installed; hooks are not cloned, so the installer runs
once per clone. Nothing in the gate is specific to this project. Failed runs, unparseable results
and a missing reviewer all block — a gate that fails open is not a gate.
