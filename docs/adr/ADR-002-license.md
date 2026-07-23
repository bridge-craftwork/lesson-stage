# ADR-002 — License: the Unlicense

**Status:** Accepted
**Date:** 2026-07-22

## Context

The seed plan proposed "MIT or Apache-2.0 to match existing bridge-craftwork
repos." A scan of all 48 repos in the org shows that premise was wrong: the
house default is the **Unlicense**, and MIT appears only on forks.

| License | Repos | Character |
|---|---|---|
| Unlicense | 29 | Everything original |
| *(none set)* | 12 | Mostly small config/data repos and private infrastructure |
| GPL-3.0 | 3 | `ben`, `Bridge-Offline-Practice`, `Bridge-Dealer-Scripts` — inherited |
| MIT | 2 | `printpdf`, `bridge-bots` — forks of upstream MIT projects |
| CC0-1.0 | 1 | `lesson-library` — content, not code |
| GPL-2.0 | 1 | `bridge-solver-xray` — instrumented port of macroxue/bridge-solver |

The pattern is consistent: original work is released into the public domain,
and a different license appears only where an upstream's terms force it. The
Rust bridge stack this app depends on — `bridge-types`, `bridge-encodings`,
`Bridge-Parsers`, `bridge-solver`, `Dealer3`, `bridge-rulebot`,
`bridge-lesson-packaging` — is uniformly Unlicense. `lesson-studio`, which
produces the Contract 5 payloads this app consumes, is Unlicense too.

## Decision

`lesson-stage` stays under the **Unlicense**, already committed as `LICENSE`
and already reported as such by GitHub. No change is needed; the plan's
baseline table was corrected instead.

## Consequences

Every dependency currently in scope is public domain, so nothing constrains
the choice today. Two future dependencies could:

- **The Vue popout gallery.** It lives in `lesson-studio` (Unlicense), so
  vendoring or consuming it is unconstrained.
- **Third-party WASM or Swift packages** added later. A copyleft dependency
  would force a license change on this repo; a permissive one (MIT, Apache-2.0,
  BSD) would only require carrying its notice. Check before adding, and note
  it here — a `NOTICES.md` is the right home once there is anything to put in
  it.

`bridge-solver-xray` being GPL-2.0 is worth remembering: if double-dummy work
ever pulls from that lineage rather than from the Unlicense `bridge-solver`
port, this decision has to be revisited.
