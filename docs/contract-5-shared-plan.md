# Plan: Contract 5 becomes a shared contract

**Status:** Approved 2026-10-27. Step 1 is done: all eight decisions were
accepted as recommended, and the contract has moved to
[contracts/pdf-attachments.md](contracts/pdf-attachments.md). Steps 2–4 aren't
started.
**Repos involved:** lesson-stage (new home), lesson-studio (current home,
producer), pbn-to-pdf (new producer), bridge-viewer (new producer and consumer).

## Why

Contract 5 (PDF lesson attachments) was written for one producer,
lesson-studio, and one consumer, this app. Its own *Ownership handover* section
says it moves to the presentation tool once that exists. That's this repo.

Since then a second producer has turned up. **pbn-to-pdf** renders PBN files to
PDFs (hand records, declarer's plans, bidding sheets, analysis), used by its
CLI, its web app, and **bridge-viewer**: an iPhone/iPad/Mac app that runs the
renderer natively and shows the result in PDFKit. A bridge-viewer discussion
(2026-10-26) asked for a hand index and, eventually, an editor. The conclusion
was to keep the PDF as what you see and print, and carry the bridge data inside
it. That's what Contract 5 already does.

If pbn-to-pdf follows the contract:

- every PDF it makes opens in lesson-stage with tappable boards, from the CLI,
  the web app or bridge-viewer;
- bridge-viewer gets its hand index from the click map;
- one contract, and one consumer implementation, covers both kinds of PDF.

## What changes in the contract

The v1 text assumes the source is lesson markdown: `/Source` is `lesson-source.md`,
`blocks[].body` is Contract 1 DSL, `kind` comes from Contract 1. A PBN-sourced
PDF has none of that. These decisions were settled in the 2026-10-27 review, all as recommended.
The contract's *Resolved* section records them.

1. **Home.** Move to `lesson-stage/docs/contracts/pdf-attachments.md`.
   lesson-studio keeps a short stub at the old path that points here, because
   its code comments and CLAUDE.md cite it. *Alternative:* a neutral contracts
   repo. Not worth it for two producers and two consumers.
2. **A source profile.** `lesson-provenance.json` gains `sourceFormat`:
   `"lesson-dsl"` (what v1 means) or `"pbn"`. Absent means `"lesson-dsl"`.
3. **Payload version 2 for the PBN profile.** In that profile `blocks[].body` is
   absent and `board` is always present. Removing a required field isn't a
   MINOR change, so call it version 2: version 1 plus profiles. lesson-studio
   can keep emitting version 1 unchanged. Consumers accept both. A v1-only
   consumer that meets a v2 PDF falls back to plain-PDF mode, which the
   contract already requires.
4. **Kinds for the PBN profile.** Start with one kind, `board`: the whole figure
   for one board on the page. Finer kinds (`hand`, `auction`, `commentary`)
   can come later as MINOR additions, once a consumer needs them.
5. **The board join stays as in v1.** `lesson-hands.pbn` holds the rendered
   boards renumbered sequentially from 1, and `blocks[].board` is the join.
   `/Source` is the original `.pbn` byte for byte, so nothing is lost. Add an
   optional `sourceBoard` (the original `[Board]` value) so a consumer can label
   boards the way the page does (MINOR).
6. **`renderedAt` becomes optional.** pbn-to-pdf promises byte-identical output
   for identical input (Baker Bridge commits its PDFs), so it must omit
   `renderedAt` or the payload breaks that promise. lesson-studio keeps writing it.
7. **Names stay.** Keep the `lesson-*` attachment filenames and the
   `lesson-block:` link scheme even for PBN sources. Renaming is MAJOR, and
   discovery is by `AFRelationship` anyway. `/Source` uses the input's own
   filename and MIME `application/x-pbn`.
8. **On by default, with an opt-out.** pbn-to-pdf embeds unless told not to
   (`--no-embed`, matching lesson-studio). Baker Bridge's committed PDFs are
   rewritten once on their next rebuild, like a version bump.

## Steps

### 1. Review and move the contract (lesson-stage, lesson-studio) — done

- Settle the eight decisions above. Record the outcome in a dated *Resolved*
  section, as the 2026-07-23 review did.
- Copy the contract here with the revision applied. Replace the lesson-studio
  copy with a stub that points here.
- Update `docs/contract-5-consumer.md`: remove the *Pending handover* note.
  That note said to move the contract when Phase 3 lands. The Phase 3 reader
  (`LessonPayload`, `LessonAttachments`, `LessonBlockLinks`) is already in
  `app/LessonStage/Blocks/`, so confirm the Phase 3 exit has been met first.
- Update lesson-studio's CLAUDE.md contracts table (item 5).

### 2. pbn-to-pdf produces it

- **Link annotations at draw time.** Each layout knows where it puts each
  board, so it adds one `lesson-block:<index>` link annotation per board, or per
  fragment when a board splits across columns or pages. printpdf supports link
  annotations. Unlike lesson-studio, nothing has to be recovered from a print
  engine: the renderer is the print engine.
- **Attachments in the lopdf pass.** printpdf can't write embedded files.
  `render/helpers/compress.rs` already post-processes every PDF with lopdf, so
  the `/EmbeddedFiles` name tree and `/AF` array go there.
- **Keep the existing guarantees.** `rendering_is_byte_reproducible_across_runs`
  must still pass with the payload included. Add a test that extracts all four
  files and checks the click map's rects against the annotations.
- **Every entry point.** CLI flag, wasm bindings option and web app
  pass-through, all on by default.
- **Fixtures.** Commit a PBN-profile PDF to `lesson-stage/fixtures/` for the
  consumer tests.

### 3. lesson-stage reads the PBN profile

- `LessonPayload.supportedVersion` becomes a set `{1, 2}`. `LessonBlockMap`
  decodes `body` as optional, and dispatches on `sourceFormat`.
- A tapped `board` block sends `{ kind: "board", pbn }` with no `blockBody`.
  The popout's deal table already takes PBN.
- Tests against the new fixture, including the plain-PDF fallback for a v1-only
  build.

### 4. bridge-viewer adheres

- **Render with the payload.** PDFs that bridge-viewer saves, prints or shares
  carry the payload, so they open in lesson-stage with tappable boards.
- **The hand index from the click map.** The FFI returns the click map JSON
  alongside the PDF bytes, so the app never has to read attachments back out
  with `CGPDFDocument`. A sidebar lists the boards, and tapping one goes to its
  page and rect. Hit-testing on the page uses the `lesson-block:` annotations
  through PDFKit, the same way lesson-stage does.
- **Bridge Viewer's own traps:** the C header is hand-written and must change
  with `lib.rs`, every new entry point goes through `boundary`, and the
  xcframework must be rebuilt after the renderer change.
- **Not in scope:** opening lesson-studio PDFs, and the card-play popout. If
  either is wanted, the questions are whether the popout becomes a shared
  package or whether the two apps converge. That's a separate decision.

### 5. Later, not now

- **A shared Swift reader.** lesson-stage and bridge-viewer would both parse
  the click map. A small Swift package could serve both once bridge-viewer's
  needs are clear. Before then it would be speculative.
- **Stable identity across revisions** (contract open item 4). This is unchanged
  by this plan and matters as soon as bridge-viewer annotations or an editor
  need to survive a re-render.
- **An editor.** It follows lesson-studio's pattern (JS components for editing,
  pbn-to-pdf through wasm for the preview) and needs a PBN writer that
  round-trips. That writer doesn't exist yet.

## Order and dependencies

Step 1 blocks everything else. Steps 2 and 3 can run in parallel once the
revision is agreed, with the fixture from step 2 unblocking step 3's tests.
Step 4 needs step 2 merged, because bridge-viewer builds against pbn-to-pdf's
`main`, unpinned.
