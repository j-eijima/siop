# 0008 — Documentation is bilingual, and only its mechanical failures are enforced

## Context

The project documents itself in English and Japanese. Whether a translation says the same thing is
a human judgement and cannot be checked by a script; the ways a pair silently falls apart are
mechanical and can be.

## Decision

Every directory that documents itself carries `README.md` and `README.ja.md`, each linking to the
other, with English canonical: change it first, change the Japanese in the same commit, never one
alone. `tools/check-docs.py` enforces the presence of the pair, matching heading structure, the
language switcher, and working relative links, in CI as well as by hand.

Per-directory `CLAUDE.md` files and generated READMEs are both rejected: two audiences reading
documents generated from each other end up with the wrong material in one of them.

## Consequences

A heading added to one language fails the check even when the wording differs, which is the point.
Coding-agent configuration is exempt because it is not documentation the project ships — see
[0009](0009-specs-and-decisions-split.md).
