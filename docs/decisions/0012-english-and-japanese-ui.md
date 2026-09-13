# 0012 — The apps speak English and Japanese; tests pin the language

## Context

The project documents itself in both languages, English canonical
([0008](0008-bilingual-docs-checked-mechanically.md)), but the iOS app and the test RP spoke only
Japanese. A reference implementation has to be usable by people who do not read Japanese.

Once the wording follows the device, every test that reads the screen follows it too. The
simulators on CI are English; the ones this was developed on are not.

## Decision

Both follow the language the user already prefers — the device's for the app, the browser's for
the RP — and fall back to English. English is the source: the app's string catalog is keyed by the
English text, and the RP's HTML carries English before its script translates it. The RP adds a
switch in its header, remembered in the browser, and accepts `?lang=`.

A protocol value is never translated. Parameter names, claims and the values that arrive or will be
signed are shown exactly as they are.

Tests pin the language rather than follow the machine. The app's UI tests launch it in English, and
the end-to-end test opens the RP with `?lang=en`. The one thing that cannot be pinned — the app,
when Safari hands it a URL — is found by accessibility identifier.

## Consequences

New wording goes into both languages in the same change, as documentation does. Nothing checks the
catalog or the RP's dictionary for a missing Japanese entry; a missing one shows the English.

The UI mock stays in Japanese only. It records a design and is not kept in step with the apps.
Android follows the same terms: its strings are English in `values/` and Japanese in `values-ja/`,
and its screen tests show the screens in English. Its end-to-end test finds the app's buttons by
test tag, exposed as resource ids.

Corrected: 2026-09-13 — Android has been rebuilt; the consequences said it stayed Japanese.
