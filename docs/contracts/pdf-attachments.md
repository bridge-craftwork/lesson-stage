# Contract 5: PDF Lesson Attachments

**Status:** Approved (reviews 2026-07-23, 2026-10-27)
**Owner:** lesson-stage, the primary consumer. Moved here from lesson-studio
on 2026-10-27. See *Ownership* below.
**Producers:** lesson-studio (`lesson-dsl` profile), pbn-to-pdf (`pbn`
profile, implementation pending).
**Consumers:** lesson-stage; bridge-viewer (planned); the pdf-handouts
pipeline (must preserve); any PBN-reading tool the author already runs.
**Payload versions:** `1` and `2` (`version` in `lesson-blocks.json`). See
*Profiles*.
**Date:** 2026-10-27

---

## Purpose

Defines what a lesson PDF carries **inside itself**, so a downstream tool can
work from the PDF alone — reconstruct the lesson, locate each bridge figure on
the page, and hand a specific deal to a card-playing tool — without re-rendering
the lesson or reaching back to the library.

The motivating case: a lesson PDF on a projector, where tapping a hand opens it
in a card-play tool so individual cards can be played from the lesson.

Two kinds of PDF carry it. Lesson PDFs, printed by lesson-studio from the
lesson DSL. And PBN renderings, such as hand records, declarer's plans and
bidding sheets, made by pbn-to-pdf from a `.pbn` file. They differ in what the
source is and what a figure's body means. That difference is the *profile*.

## Why attachments and not the text layer

The source is carried as **PDF embedded files** (the `/EmbeddedFiles` name tree,
the mechanism PDF/A-3 and ZUGFeRD invoices use), never as hidden or
small-print text on the page.

This is a correctness decision, not a preference. PDF text extraction does not
reliably preserve newlines, leading whitespace, or run order — and the lesson
DSL is whitespace-sensitive: suit holdings, fence indentation, and the `---`
separator between an auction's calls and its notes all carry meaning. A
text-layer copy would appear recoverable and silently not be. An attachment is
byte-exact by construction.

## The four attachments (normative)

| File | `AFRelationship` | MIME | Contents |
|---|---|---|---|
| `lesson-source.md` | `/Source` | `text/markdown` | The lesson file, byte-for-byte |
| `lesson-provenance.json` | `/Supplement` | `application/json` | What produced this PDF |
| `lesson-blocks.json` | `/Data` | `application/json` | Where each block is, and its DSL |
| `lesson-hands.pbn` | `/Data` | `application/x-pbn` | The lesson's hands as PBN deals |

`lesson-hands.pbn` is **omitted** when a lesson contains no hands. The other
three are always present on an embedded render.

### Profiles (normative)

`sourceFormat` in `lesson-provenance.json` names the profile. It's absent in
PDFs made before profiles existed, and absent means `lesson-dsl`.

| | `lesson-dsl` | `pbn` |
|---|---|---|
| Producer | lesson-studio | pbn-to-pdf |
| Payload `version` | `1` | `2` |
| `/Source` | `lesson-source.md`, `text/markdown` | the input file under its own name, `application/x-pbn` |
| `blocks[].kind` | Contract 1 block tags | `board` (see below) |
| `blocks[].body` | always present | **absent** |
| `blocks[].board` | on blocks that produced a deal | **always present** |

The other three attachments keep their v1 names in both profiles, even though
`lesson-` reads oddly on a hand record: renaming is MAJOR, and discovery is by
`AFRelationship` anyway.

**Version 2 is version 1 plus profiles.** Everything in version 1 holds in
version 2 except the two rows marked above. A producer of the `lesson-dsl`
profile MAY keep emitting version `1`. A consumer accepts every version it
knows and falls back to plain-PDF mode for one it doesn't, so a version-1-only
consumer meets a version 2 PDF safely.

**`pbn` profile kinds.** One kind for now: `board`, the whole figure for one
board as laid out on the page (its diagram, plus auction and commentary where
the layout draws them). Finer kinds (`hand`, `auction`, `commentary`) are
MINOR additions, made when a consumer needs them.

### Discovery (normative)

A consumer SHOULD locate the source by **`AFRelationship`**, not by filename:
find the entry in the document catalog's `/AF` array whose relationship is
`/Source`. Filenames are stable within this version and are a reasonable
fallback, but the relationship tag is the contract.

Attachments this contract does not name MUST be left untouched by any producer
implementing it. Lesson PDFs are expected to carry the author's own PBN files
alongside these.

### `lesson-provenance.json`

```json
{
  "generator": "lesson-studio",
  "generatorVersion": "0.1.0",
  "dslSpec": "contract-1/v1",
  "sourceFile": "new-minor-forcing.md",
  "renderedAt": "2026-07-23T01:02:27.521Z"
}
```

`sourceFormat` (`"lesson-dsl"` or `"pbn"`) names the profile. `dslSpec` is
present in the `lesson-dsl` profile only. **`renderedAt` is optional.** A
producer that promises byte-identical output for identical input omits it.
pbn-to-pdf does, because Baker Bridge commits its rendered PDFs.

A PDF outlives the context that produced it. `dslSpec` says which grammar the
embedded markdown was valid against, so a consumer meeting a future DSL knows
whether it can parse what it found rather than guessing.

### `lesson-blocks.json` — the click map

```json
{
  "version": 1,
  "pageCount": 1,
  "pageSize": [[612, 792]],
  "coordinateSpace": "pdf-points, origin bottom-left",
  "blocks": [
    {
      "index": 0,
      "kind": "auction",
      "page": 1,
      "rect": [42, 235.5, 201, 366],
      "body": "dealer: N\ncolumns: 2\nlabels: Opener, Responder\n…"
    }
  ],
  "unlocated": []
}
```

| Field | Meaning |
|---|---|
| `version` | Contract 5 payload version, `1` or `2`. Dispatch on this before trusting the rest. |
| `pageCount` | Pages in the PDF. |
| `pageSize` | `[width, height]` in points, **per page** — pages need not match. |
| `coordinateSpace` | Always `pdf-points, origin bottom-left` in version 1. |
| `blocks[].index` | Document order of leaf blocks, 0-based. |
| `blocks[].kind` | The Contract 1 block tag (`hand`, `auction`, `response-box`, …) in the `lesson-dsl` profile; `board` in the `pbn` profile. |
| `blocks[].page` | 1-based page number. **Absent** if unlocated. |
| `blocks[].rect` | `[x1, y1, x2, y2]` in PDF points, origin bottom-left. **Absent** if unlocated. |
| `blocks[].body` | The block's DSL body verbatim — parse with Contract 1. **Absent in the `pbn` profile**: the deal itself is the content. |
| `blocks[].board` | The `[Board]` number in `lesson-hands.pbn`. Present only on blocks that produced a deal; always present in the `pbn` profile. |
| `blocks[].sourceBoard` | Optional. The board's original `[Board]` value in the source file, so a consumer can label it as the page does. |
| `blocks[].deal` | On an `auction`: the `index` of the hand it's bid on, or `null` if unpaired. Absent on other kinds. |
| `blocks[].fragments` | `[{page, rect}]` for a block split across columns/pages. Absent when it wasn't. |
| `unlocated` | Indices with no position. Empty in the normal case. |
| `fragmented` | Indices that split. Empty in the normal case. |

**`unlocated` is normative, not diagnostic.** A block whose position could not
be determined appears in `blocks` with its `body` but no `page`/`rect`, and its
index is listed here. A consumer MUST NOT infer a position for such a block; it
should fall back to non-positional use of the body. This exists so the map can
never quietly imply full coverage it does not have.

**A block may occupy more than one rect.** `break-inside: avoid` is a request,
not a guarantee: a block taller than its column fragments anyway, and the print
engine emits one annotation per piece. When that happens, `rect` is the
**largest** piece — so a consumer that understands only one rect gets the most
useful one rather than an arbitrary one — and `fragments` carries every piece in
reading order. Producers MUST NOT union the pieces: a union across two columns
covers the text between them. A consumer wanting exact hit-testing SHOULD use
`fragments` when present.

**Coordinates are PDF-space, not DOM-space.** Origin bottom-left, y increasing
upward.

This is **PDFKit-native**: it is exactly `PDFPage` coordinate space, so an iOS
consumer does no conversion at all and maps to view space with
`PDFView.convert(_:to:)`. The conversion below is for web/DOM consumers only —
applying it on iOS would flip the rects twice:

```
y_screen = pageHeight − y_pdf     // web/canvas consumers only
```

**Leaf blocks only.** A `row` block is a layout container; the map records the
blocks *inside* it, since those are what a reader would tap. No entry in
`blocks` ever contains another.

**Layout-control blocks are omitted.** `pagebreak` and `columnbreak` shape the
page but render nothing tappable, so they never appear in `blocks` — block
indices run over content blocks only.

### `lesson-hands.pbn`

One PBN game record per `hand`/`hands` block, in document order.

- `[Board "n"]` numbers the emitted deals **sequentially from 1**, with no gaps.
  It is deliberately *not* the block's document position: only hand blocks
  produce records, so position-numbering would emit boards 3, 7, 12 — legal PBN,
  but many readers assume boards run sequentially from 1.
- **The join lives in the click map**, not in the PBN: `blocks[].board` gives the
  board number for the block that produced it. A non-standard PBN tag would have
  been the alternative, and a map field is the better place for it.
- Hands the lesson does not specify are written `-`, per PBN. Lesson hands are
  usually a single seat, and **no cards are ever invented** to complete a deal.
- The mandatory PBN tag set is emitted with `?` placeholders where a lesson has
  nothing to say, which is conventional for PBN exporters.
- **Small cards are emitted as a literal `x`, which is off-spec.** PBN §3.4.11
  defines the rank set as `AKQJT` + `9`–`2`; `x` is not in it, and a strict
  parser will reject such a record. It is written anyway: lessons routinely
  hold `AKQxx`, and the downstream stage app click-tests cards against this
  sidecar, so dropping the placeholders would leave those cards untappable and
  silently shorten the suit — a wrong deal is worse than an unparseable one.
  Lowercase is load-bearing: every real rank is uppercase, so a consumer can
  tell a placeholder from an unknown rank with a case test. Only affects
  records whose lesson block used `x`; deals of real cards stay strictly valid.
- An `[Auction]` section is included when the deal has an auction paired with
  it — Contract 1's `deal:` key, defaulting to the nearest preceding hand. A
  deal with several auctions on it takes the first; the others still render on
  the page, they just don't go into that record. A deal with none gets no
  `[Auction]` section and `[Dealer "?"]`.
- `blocks[].deal` in the click map gives the same pairing from the other
  direction, so a consumer can go from a tapped auction to its hand without
  reading the PBN.

**In the `pbn` profile** the file holds the rendered boards, in the order they
appear in the PDF, renumbered sequentially from 1 by the same rule, so the
`board` join is identical in both profiles. Records are otherwise copied as
the source has them (all four hands, auction, play, and the rest).
Renumbering loses nothing: `/Source` is the original file byte for byte, and
`blocks[].sourceBoard` carries each board's original number.

## Positions come from the print engine (normative rationale)

Producers MUST NOT derive `rect`/`page` by measuring the DOM.

The print view is CSS multi-column under `@page`; the browser's print engine
decides where pages break, and `break-inside: avoid` on bridge blocks moves them
between columns and pages. None of that is observable from JavaScript, so DOM
measurement is correct only for a single-page lesson and silently wrong beyond
it.

This rule is about lesson-studio, whose layout is done by a browser. A
producer that lays out pages itself, as pbn-to-pdf does, *is* the print engine.
It records each rect as it draws and emits the link annotation at the same
time.

lesson-studio's implementation instead wraps each leaf block in a
`lesson-block:<index>` link before printing and reads back the **link
annotations** the print engine emits — one per link, attributed to the page it
was actually laid out on, with a rect in PDF space. The engine that did the
layout reports the layout.

### Link annotations are part of the artifact

Those `lesson-block:<index>` links are **left in the PDF**. Consumers MAY use
either the annotations or `lesson-blocks.json`; they carry the same rects and
are generated together. The JSON additionally carries the DSL body, which
annotations cannot.

The redundancy is deliberate, and it is worth more than the
standalone-handout argument alone:

- **Link annotations are cheap to read.** In PDFKit they are first-class —
  `page.annotations`, filter for links, read the URI and bounds.
- **Attachments are not.** PDFKit exposes no attachments API; extracting the
  four files on iOS means dropping to `CGPDFDocument` via
  `PDFDocument.documentRef` and walking the `/Names` tree and `/AF` array by
  hand.

So a consumer can hit-test taps entirely from annotations — the hot path, run on
every touch — and parse attachments once per document load to get the bodies and
PBN. Producers SHOULD keep the links for that reason.

## Pipeline placement (pdf-handouts and other rewriters)

**Attach last.** A pipeline that rewrites lesson PDFs — adding headers, footers,
page numbers, merging handouts — SHOULD run `pdf:attach` as its **final stage**,
after every rewrite.

This is architectural, not stylistic. Whether a rewriter preserves attachments
depends entirely on its PDF library: document-level manipulation generally keeps
the `/Names` tree intact, while anything that re-renders or reconstructs the
catalog drops it. Making attachment the last step means the pipeline never has
to care, and stays order-independent.

Stated as an obligation for stages that *do* rewrite after attachment: they MUST
preserve the `/EmbeddedFiles` name tree and the `/AF` array, or the artifact
stops being reconstructable and the projection tool loses its input. That
remains in the contract as defense-in-depth, but **the architecture should not
depend on it holding**.

**Unverified as of this writing.** pdf-handouts is not yet wired up. Check any
stage's output with `npm run pdf:extract -- --pdf <output>` before relying on
it. If a stage cannot preserve attachments, re-attach downstream — never move
the payload into the text layer.

## Producing and consuming

lesson-studio (`lesson-dsl` profile):

```bash
npm run print:pdf   -- --lesson lesson.md --out out.pdf   # render + attach
npm run print:pdf   -- --lesson lesson.md --out out.pdf --no-embed
npm run pdf:attach  -- --pdf out.pdf --lesson lesson.md   # attach after the fact
npm run pdf:extract -- --pdf out.pdf --out recovered.md   # read back
npm run pdf:extract -- --pdf out.pdf --info               # provenance only
```

pbn-to-pdf (`pbn` profile, pending) embeds by default on every entry point:
CLI, wasm bindings and the web app. It has a `--no-embed` opt-out matching
lesson-studio's.

lesson-studio has two ways to attach: `pdf:attach` (CLI) and the in-browser
**drop-to-attach** bar on the print view — print to PDF, drop it back, and the
same shared pdf-lib core embeds all four files client-side, no server. The
click map's positions survive a browser print because the print view wraps the
`lesson-block:` anchors on `beforeprint`, so Chrome emits the link annotations
whether the PDF came from Playwright or from Cmd+P.

Both exist because **the browser's own print dialog cannot attach files**. Nothing in HTML, CSS, or JavaScript can add an attachment to a PDF the
browser generates; a lesson printed with Cmd+P must have its payload added
afterwards.

**Re-attaching MUST be idempotent in file size.** A producer replaces its own
attachments rather than appending, and MUST emit output from which the
superseded streams have been **reclaimed** — not merely unlinked.

Unlinking alone is not enough, and the distinction is easy to miss. Removing an
object from the `/Names` tree makes it logically gone, but an incremental-update
writer leaves the old bytes in the file: it grows on every render even though
the entry counts look right, and a superseded copy of the lesson source stays
recoverable in the dead bytes. **Producers SHOULD write full-rewrite output**,
which reclaims unreferenced objects. The reference implementation does (pdf-lib
`save()` serializes the whole document), and its test asserts file size across
repeated embeds rather than only entry counts — the counts alone would not catch
this.

Attachments a producer did not itself write MUST be left alone.

## Versioning and evolution

- Adding an attachment, or an optional field to an existing one, is **MINOR**.
  Consumers MUST ignore fields they do not recognize.
- Renaming or removing an attachment, changing `coordinateSpace`, or changing
  the meaning of `rect`, `index`, or `board` is **MAJOR** and reviewed here.
  (Adding `fragments` alongside `rect` was MINOR; redefining `rect` to mean a
  union of fragments would not have been.)
- The block `kind` values and `body` grammar of the `lesson-dsl` profile are
  Contract 1's; this contract does not restate them and changing them is a
  Contract 1 change. The `pbn` profile's kinds are defined here.
- Version `2` was a MAJOR change, for one reason: the `pbn` profile omits
  `blocks[].body`, which version 1 always carries. Adding a profile in future
  is MAJOR if it removes or redefines a field, and MINOR otherwise.

## Ownership

This contract lives in lesson-stage, its primary consumer. It moved here from
lesson-studio on 2026-10-27, as the original *Ownership handover* section
provided, once lesson-stage's Phase 3 reader had landed. lesson-studio keeps a
pointer at its old path.

Production stays with the producers: lesson-studio generates the `lesson-dsl`
click map where its print engine runs, and pbn-to-pdf generates the `pbn`
one as it draws. A change either producer needs is proposed here.

## Resolved (2026-10-27 review)

The `pbn` profile, for pbn-to-pdf as a second producer:

1. **Home:** moved to lesson-stage, with a pointer left in lesson-studio.
2. **Profiles:** `sourceFormat` in provenance, `lesson-dsl` or `pbn`; absent
   means `lesson-dsl`.
3. **Payload version 2** for the `pbn` profile, because it omits `body`.
   lesson-studio may keep emitting version 1, and consumers accept both.
4. **One `pbn` kind, `board`,** with finer kinds left as MINOR additions.
5. **The board join is unchanged:** `lesson-hands.pbn` is renumbered from 1,
   `/Source` is the original file, and there is an optional `sourceBoard`.
6. **`renderedAt` is optional,** so reproducible producers can omit it.
7. **Names are kept:** the `lesson-*` filenames and the `lesson-block:`
   scheme. The `pbn` profile's `/Source` uses the input's own filename.
8. **Embedding is on by default** in pbn-to-pdf, with `--no-embed` to opt out.

## Resolved (2026-07-23 review)

- **Link annotations are kept.** Beyond the standalone-handout argument, the
  consumer cost is asymmetric: annotations are first-class in PDFKit while
  attachments require dropping to `CGPDFDocument`. Keeping them gives the hot
  path (hit-testing every touch) the cheap route. A `--no-links` producer flag
  remains the escape hatch if stray URIs confuse ordinary viewers.
- **Fragmented blocks are specified** rather than left silent: largest piece as
  `rect`, all pieces in `fragments`, never unioned.
- **PBN boards renumbered sequentially**, with the join moved to
  `blocks[].board`, so gap-intolerant PBN readers are unaffected.
- **Attach-last adopted** as the pipeline architecture, so preservation is
  defense-in-depth rather than load-bearing.
- **Auction-to-hand pairing is implemented** (Contract 1 `deal:`, defaulting to
  the nearest preceding hand), so "step through this auction on this deal" is
  now expressible. Existing lessons needed no edits: New Minor Forcing pairs its
  closing auction with its hand by proximity, and leaves the opening convention
  illustration unpaired, which is correct.

## Open items for review

1. **pdf-handouts preservation — unverified.** Lower risk now that attach-last
   is the intended order, but still worth confirming what its PDF library does,
   since anything reconstructing the catalog drops attachments.
2. **Several auctions on one deal.** The PBN record takes the first, since a PBN
   game has one `[Auction]`. If lessons routinely bid one hand several ways
   (an auction and its alternative), the deal may deserve one PBN record per
   auction rather than per hand. The click map already carries all the pairings.
3. **Partial-hand PBN.** `-` for unknown hands is valid PBN, but confirm the
   card-play tool accepts a one-hand deal rather than requiring all four.
4. **Stable identity across revisions.** `index` and `board` are positional, so
   they shift when a lesson is edited. That is fine while the join only has to
   hold *within one PDF*, which it does by construction. It stops being fine
   once something outside the PDF references a block across revisions —
   annotations drawn on a board, notes keyed to a deal, records of which deals
   were taught. The cheap answer then is a **content hash of the block body**,
   which is derivable rather than authored and so needs no Contract 1 grammar
   change; pair it with an occurrence index, since a lesson may legitimately
   contain two identical blocks.
