# 0009 — Behaviour lives in docs/specs, reasoning lives in this skill

## Context

Requirements, promised behaviour and design reasoning were all going into the READMEs, which
already carry what exists and how to run it. Mixed together they push each other out, and an agent
reading a README for one reason absorbs all of it — including decisions from work unrelated to the
task, which then steer it.

## Decision

Three homes, no overlap:

- `docs/specs/` — behaviour agreed and acceptance conditions, limited to what a person confirms by
  hand. Anything a test can decide stays in the test suites. Two notations, because one does not
  cover the ground: Gherkin for behaviour someone walks through, EARS for what holds at all times
  and for what must not happen — a Gherkin step can assert an absence but never says when the
  absence is checked.
- `docs/decisions/` — records like this one, reached through the index in the `siop-decisions`
  skill so that a task loads only what it touches.
- READMEs — what exists, how to run it, what implements what.

`tools/check-docs.py` holds the two `docs/` directories to different rules, because they fail in
different ways. Specifications are documentation and take the usual pair in both languages. Records
are a log, only ever appended to: demanding a translation per record would make writing one
expensive enough that it stops happening, so they are English alone. The one thing checked about
them is that every record appears in the index and every index row points at a record — nothing
reads the directory itself, so a record left out of the index is invisible.

`.claude/` is skipped entirely, on the same grounds a local `CLAUDE.md` is: it is configuration for
whoever works here, not documentation the project ships. What lives there is the index and the
instruction to read it, never the reasoning itself, so the records stay with the project rather
than with the tool that happens to read them.

## Consequences

A requirement now goes to `docs/specs/` rather than a README, and the root README points there
instead of carrying the text. A decision becomes a record plus a row in the index, and the check
refuses the change when the row is missing.

Two rules inside `docs/` is the cost: whoever adds a third directory there has to say which kind it
is, and teach `check-docs.py` about it. That is deliberate — the alternative was one rule and a
category of document that fits neither.
