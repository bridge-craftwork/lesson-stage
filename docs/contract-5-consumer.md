# Contract 5 — consumer notes

Working notes for the consumer side of **Contract 5: PDF Lesson Attachments**.

**The contract itself lives in lesson-studio**, at
`documentation/contracts/pdf-attachments.md` — payload version `1`, last
reviewed 2026-07-23. That document is normative; this one is not. This is only
what the contract means *for this app*, plus the iOS-specific details it does
not cover.

> **Pending handover.** The contract's own *Ownership handover* section says it
> should move to sit beside the presentation tool once that tool exists, since
> this app becomes its primary consumer. This repo is that tool. The production
> side stays in lesson-studio — the click map can only be generated where the
> print engine runs. Move the document here when Phase 3 lands, not before:
> owning a contract you cannot yet honour helps nobody.

---

## What a lesson PDF carries

Four embedded files (the `/EmbeddedFiles` name tree, as PDF/A-3 and ZUGFeRD
invoices use):

| File | `AFRelationship` | What this app does with it |
|---|---|---|
| `lesson-source.md` | `/Source` | Nothing yet. Reconstruction is not a Phase 3–4 need |
| `lesson-provenance.json` | `/Supplement` | Read `dslSpec` to know what grammar the bodies are in |
| `lesson-blocks.json` | `/Data` | **The click map.** Block bodies, positions, board join |
| `lesson-hands.pbn` | `/Data` | The deals. Omitted entirely when a lesson has no hands |

Locate by **`AFRelationship`**, not filename — that is the contract; filenames
are a fallback. Leave every attachment this contract does not name alone;
lesson PDFs are expected to carry the author's own PBN files too.

## The two routes in, and why we use both

The payload is deliberately redundant: `lesson-block:<index>` link annotations
are left in the PDF, carrying the same rects as the click map.

This exists because the consumer cost is asymmetric, and the split falls out
of it directly:

- **Hit-testing is the hot path** — it runs on every touch. Link annotations
  are first-class in PDFKit: `page.annotations`, filter for links, read the URI
  and bounds. Cheap.
- **Attachments are not.** PDFKit exposes no attachments API at all. Getting
  the four files means dropping to `CGPDFDocument` through
  `PDFDocument.documentRef` and walking the `/Names` tree and `/AF` array by
  hand — the least pleasant code in the app, and the reason Phase 3 exists as
  its own phase.

**So: annotations on every touch, attachments once per document load.** The
annotation gives us the block index; the click map turns that index into a
body and a board number.

## Reading the click map

```json
{
  "version": 1,
  "pageCount": 1,
  "pageSize": [[612, 792]],
  "coordinateSpace": "pdf-points, origin bottom-left",
  "blocks": [
    { "index": 0, "kind": "auction", "page": 1,
      "rect": [42, 235.5, 201, 366], "body": "dealer: N\ncolumns: 2\n…" }
  ],
  "unlocated": []
}
```

Dispatch on `version` **before trusting anything else**. Unknown fields must be
ignored — adding one is a MINOR change and will happen.

### Coordinates need no conversion on iOS

`coordinateSpace` is `pdf-points, origin bottom-left`, which is exactly
`PDFPage` coordinate space. Map to view space with `PDFView.convert(_:to:)`
and nothing else.

The `y_screen = pageHeight − y_pdf` flip in the contract is **for web and
canvas consumers only**. Applying it here flips twice and puts every hit target
in the wrong half of the page. This is the single easiest mistake to make in
Phase 3; the debug overlay exists partly to make it obvious immediately.

### Observed in a real payload (2026-07-23, `new-minor-forcing.pdf`)

Confirmed against the first real lesson PDF, and worth pinning down because the
example above leaves two things implicit:

- **`rect` is `[minX, minY, maxX, maxY]`**, not `[x, y, width, height]`. Block 0's
  `rect: [45, 261, 198, 352.5]` matches its `lesson-block:0` annotation bounds of
  `(x: 45, y: 261, w: 153, h: 91.5)` exactly. Build the `CGRect` as
  `(minX, minY, maxX − minX, maxY − minY)`.
- **`page` is 1-based** (subtract 1 for a `PDFDocument` page index).
- **`kind`** seen so far: `auction`, `hand`, `response-box`.
- **The PBN join splits by kind.** A `hand` block carries `board` (→ PBN
  `[Board "n"]`); an `auction` block carries `deal` (a board number, or `null`
  when no deal is bound to it). Both are board numbers, matching the
  "`board` is the join" rule — the key name just differs by block kind.
- A `fragmented: []` array appears alongside `unlocated: []` — an unknown field
  to ignore per the version-dispatch rule.
- The four attachments and their `AFRelationship`s (`Source`/`Supplement`/
  `Data`/`Data`) are exactly as specified; `lesson-block:` link annotations are
  `PDFActionURL`s with the bare `lesson-block:<index>` URI, one per fragment.

### Three fields that are easy to get wrong

**`blocks[].board` is the join — not `index`.** PBN boards are renumbered
sequentially from 1 with no gaps, deliberately *not* by document position,
because only hand blocks produce records and position-numbering would emit
boards 3, 7, 12. Legal PBN, but many readers assume sequential. `board` is
present only on blocks that produced a deal.

**`unlocated` is normative, not diagnostic.** A block that could not be
positioned appears in `blocks` with its `body` but no `page`/`rect`, and its
index is listed in `unlocated`. Never infer a position for one — fall back to
non-positional use of the body. The field exists so the map can never quietly
imply coverage it does not have.

**`fragments` beats `rect` for hit-testing.** `break-inside: avoid` is a
request, not a guarantee: a block taller than its column fragments anyway and
the print engine emits one annotation per piece. When that happens `rect` is
the **largest** piece and `fragments` carries every piece in reading order.
They are never unioned — a union across two columns would cover the text
between them. Hit-test `fragments` when present, and treat duplicate
`lesson-block:` URIs as several tap targets for one block.

**Leaf blocks only.** A `row` is a layout container; the map records what is
inside it. No entry in `blocks` ever contains another, so hit-testing needs no
containment resolution.

## Reading the PBN

One game record per `hand`/`hands` block, in document order.

**Partial deals are the norm, not an error case.** Lesson hands are usually a
single seat; unspecified hands are written `-` per PBN, and no cards are ever
invented to complete a deal. The popout must accept a one-seat deal — this is
open item 3 in the contract, and it is *our* item to close. A deal display that
requires four hands fails on the majority of real lessons.

Mandatory PBN tags carry `?` placeholders where the lesson has nothing to say.

**`[Auction]` appears only when the lesson has exactly one auction.** With
several, the auction-to-hand pairing is not determinable from the source, and a
guess would be worse than nothing. This blocks the "step through this auction
on this deal" case — which is open item 2 in the contract, a **Contract 1**
change (an optional `deal:` key on auction blocks), not something this app can
fix. Phase 4's auction stepper should be built to degrade: single-auction
lessons get the full stepper, multi-auction lessons get the auction without a
deal bound to it.

## Failure modes

The contract's own unresolved risk is the pipeline: `pdf-handouts` preservation
is **unverified**, and anything that reconstructs the PDF catalog drops
attachments. Mitigation upstream is attach-last (`pdf:attach` as the final
stage), so preservation is defense-in-depth rather than load-bearing.

Downstream, this app must assume it will eventually meet a stripped PDF:

- **No attachments** → plain-PDF mode. Full viewing and annotation, no popout.
- **Annotations but no click map** → still plain-PDF mode. The `lesson-block:`
  URIs give tap targets with no bodies behind them; suppress the targets rather
  than opening an empty popout.
- **Unknown `version`** → plain-PDF mode, with a diagnostic. Do not
  best-effort-parse a future payload.

The failure mode is always *"popout unavailable"*, **never a crash**. The
extraction code is low-level C API against untrusted-shaped input, so it gets
isolated in one module with tests against known-good fixtures in `/fixtures`.

## Identity across revisions — not yet our problem

`index` and `board` are positional and shift when a lesson is edited. That is
fine while the join only has to hold *within one PDF*, which it does by
construction.

It stops being fine the moment something outside the PDF references a block
across revisions — and Phase 2's annotation sidecar is exactly that. The
sidecar is keyed by *PDF* content hash, which is a different question, but the
two meet if Pencil drawings ever need to survive a lesson being re-rendered.

The contract's answer (open item 4) is a **content hash of the block body**,
derivable rather than authored, paired with an occurrence index since a lesson
may legitimately contain two identical blocks. Worth adopting if and when
sidecars need to survive re-renders. Not before.
