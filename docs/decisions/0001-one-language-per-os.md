# 0001 — Each OS is implemented in its default language

## Context

The point of the project is to show what Section 7 costs to implement for real, on each platform,
to whoever has to build it there. A single cross-platform implementation would answer a different
question, and would hide platform-specific work — key storage, URL scheme registration — behind
someone else's abstraction.

## Decision

Each OS gets its own implementation in that OS's default language: Swift for iOS and macOS, Kotlin
for Android, C# for Windows. Cross-platform languages are optional additions, never the primary
implementation for a platform. The order of work is the table in the root README.

## Consequences

The same protocol is written several times, and the same bug can be fixed several times. That
duplication is accepted: it is what makes [0002](0002-verification-across-implementations.md)
possible, since implementations that share code cannot check each other.
