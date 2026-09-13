# Specifications

**English** | [日本語](README.ja.md)

What the apps are supposed to do, and what counts as acceptance, kept apart from the code that
happens to implement it. This project implements one protocol several times over, so a
specification is the part that has to survive being implemented again in another language.

The audience is a person about to check the behaviour by hand, and a coding agent about to change
it. Everything here is a promise about observable behaviour — never a description of a class.

## What belongs here

- Behaviour only a person can judge: what a screen shows, what it says, what the user must see
  before a token is signed.
- Requirements agreed but not built yet. Each specification says where it stands, so an unbuilt
  promise is not mistaken for a description of the current app.
- Behaviour that must hold identically across implementations. Where one platform genuinely
  differs, the specification says which and why.

## What does not belong here

- Anything a test can decide on its own — signatures, thumbprints, claim checks, the RP's
  Section 7.5 validation. Those live in the suites the root [README](../../README.md) lists, and a
  specification that repeats them goes stale without anyone noticing.
- Why a design went the way it did. That is a decision record in [../decisions/](../decisions/),
  indexed by a coding-agent skill so only the records a task touches are read.
- Progress, build commands, and what implements what. Those are the READMEs.

## How each one is written

- One directory per subject, carrying `README.md` and `README.ja.md` like every other directory
  here.
- Behaviour a person walks through goes under **Behaviour**, in a fenced `gherkin` block.
- A requirement that holds at all times, and anything that must *not* happen, goes under
  **Constraints** as one EARS sentence each: `The <system> shall <response>`, or one of
  `When <trigger>, …`, `While <state>, …`, `If <trigger>, then …`, `Where <case>, …`. Gherkin can
  state an absence but never says when it is checked, which is how a step like "no key was
  created" ends up unverifiable.
- The same requirement is never written in both forms. A scenario that reads as a rule with a
  `When` bolted onto it is a constraint.
- Gherkin keywords and EARS sentences stay English on both sides; they are the artefact, not prose
  about it. The Japanese version translates the surrounding text and glosses each constraint in
  parentheses.
- Keep it to what is actually confirmed by hand. Exhaustive specifications stop being read, and a
  specification nobody reads is worse than none.

## The specifications

| Subject | Covers | State |
|---|---|---|
| [identity/](identity/) | Creating, listing, inspecting, editing, deleting, and choosing an identity | Built on iOS; Android uses a key per RP without offering a choice |
| [consent/](consent/) | What the user sees before anything is signed, and what declining means | Built on iOS; partly on Android |
| [parameters/](parameters/) | Showing each protocol value and where it came from, on both sides | Built on iOS and in the test RP; not on Android |
