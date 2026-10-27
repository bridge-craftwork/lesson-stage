# CLAUDE.md

lesson-stage: iPadOS presenter for lesson PDFs, with Pencil annotation and a
tap-to-open bridge popout driven by the Contract 5 payload embedded in the PDF.
See [README.md](README.md) for status and build steps, [docs/PLAN.md](docs/PLAN.md)
for the phases, and `docs/adr/` for the decisions. ADR-003 is the big one: the
popout runs the Bridge-Classroom Vue components in a `WKWebView`, and nothing is
ported to SwiftUI or Rust.

## Contract 5

What this app reads is defined by Contract 5 (PDF lesson attachments). The
normative text is still in lesson-studio, at
`../lesson-studio/documentation/contracts/pdf-attachments.md`.
`docs/contract-5-consumer.md` covers what it means here: annotations for
hit-testing, attachments once per load, and plain-PDF mode on every failure.

**Planned:** the contract moves here and becomes shared, with pbn-to-pdf as a
second producer (a PBN profile, payload version 2) and bridge-viewer as a
second consumer. See [docs/contract-5-shared-plan.md](docs/contract-5-shared-plan.md).
Until then, `LessonPayload` accepts version 1 only. That's correct, not a gap.

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
