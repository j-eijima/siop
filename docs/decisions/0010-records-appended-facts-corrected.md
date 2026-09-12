# 0010 — Records are appended; only their facts are corrected

## Context

A decision record is useful because it says what was decided at the time and why, so that a later
reader can tell whether the reasons still hold. Rewriting a record to match a later decision
destroys exactly that.

Records also describe the world, though — how an implementation behaves, where a file lives — and
those descriptions can simply be wrong. The first push of this log was refused in review partly
because [0004](0004-keys-created-on-response.md) misdescribed what declining does. Keeping a known
falsehood in place for the sake of an unaltered record would make the log less trustworthy, not
more.

## Decision

The Decision section of a pushed record never changes. Replacing or reversing a decision means a
new record; the old one gains a `Superseded by` line under its title and nothing else.

Factual errors elsewhere in a pushed record — Context, Consequences, a dead link — are corrected in
place, with a closing `Corrected:` line giving the date and what changed.

Before a record has passed the push review it is a draft, and is edited freely.

When it is unclear which applies, the test is whether the change touches the Decision section. If
it does, it is a new record.

## Consequences

The log reads as history — each decision as it was made — without ever asserting something known to
be false. A correction that would change what a reader does is a sign the decision itself was
wrong, and becomes a new record instead. Superseded rows stay in the index, marked, so the history
remains reachable.
