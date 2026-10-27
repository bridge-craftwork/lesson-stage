# CLAUDE.md

lesson-stage: iPadOS presenter for lesson PDFs, with Pencil annotation and a
tap-to-open bridge popout driven by the Contract 5 payload embedded in the PDF.
See [README.md](README.md) for status and build steps, [docs/PLAN.md](docs/PLAN.md)
for the phases, and `docs/adr/` for the decisions. ADR-003 is the big one: the
popout runs the Bridge-Classroom Vue components in a `WKWebView`, and nothing is
ported to SwiftUI or Rust.

## Contract 5

What this app reads is defined by Contract 5 (PDF lesson attachments), which
**lives here**: [docs/contracts/pdf-attachments.md](docs/contracts/pdf-attachments.md).
It moved from lesson-studio on 2026-10-27 and is shared by two producers:
lesson-studio (`lesson-dsl` profile, payload version 1) and pbn-to-pdf (`pbn`
profile, version 2, implementation pending). Changes either producer needs are
proposed here. `docs/contract-5-consumer.md` covers what it means for this app:
annotations for hit-testing, attachments once per load, and plain-PDF mode on
every failure.

`LessonPayload` accepts both versions. A pbn-to-pdf `board` block has a deal
and no body; the popout shows it like a hand, and plays it when the deal is
complete. Fixtures for each profile are in `fixtures/`. Two things to keep:
`PBN.records` splits only on blank lines outside `{…}`, because pbn-to-pdf
copies records verbatim, commentary included. And the popout bundle in
`app/LessonStage/Popout/Resources` is built by `popout/sync-to-app.sh`; rerun
it after any change under `popout/src`.

## Sister repos

- **lesson-studio** (`../lesson-studio`): the lesson editor, and Contract 5's
  producer today.
- **pbn-to-pdf** (`../pbn-to-pdf`): the Rust PBN → PDF renderer (hand records,
  declarer's plans, bidding sheets). It is planned to embed Contract 5, so its
  PDFs open here with tappable boards.
- **bridge-viewer** (`../bridge-viewer`): an iPhone/iPad/Mac app over
  pbn-to-pdf. It shows the renderer's PDFs and is planned to build a hand index
  from the same click map. It doesn't do card play. If it ever wants the popout,
  the choice is between a shared package and converging the two apps.
