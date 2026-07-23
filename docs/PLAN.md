# Project Plan — Bridge Lesson Presenter (working name)

An iPadOS app for classroom bridge presentation: a tabbed PDF presenter with
Apple Pencil annotation, Contract 5 awareness (embedded lesson payloads), and
a tap-to-open interactive bridge popout powered by the existing Vue component
gallery and Rust bridge libraries.

Replaces GoodReader in the classroom workflow. Adds what GoodReader can never
have: bridge knowledge.

---

## Architecture at a glance

```
┌─────────────────────────────────────────────────────┐
│ SwiftUI shell                                       │
│  ├─ Tab strip (6–8 open lessons)                    │
│  ├─ PDFKit PDFView per tab                          │
│  │    ├─ PencilKit overlay (PDFPageOverlayViewProvider)
│  │    └─ Link-annotation tap handling (lesson-block:)
│  ├─ Contract 5 reader (CGPDF attachment extraction) │
│  ├─ iCloud lessons folder (bookmark + discovery)    │
│  └─ Bridge popout: WKWebView                        │
│       └─ Vue gallery components + Rust-as-WASM      │
└─────────────────────────────────────────────────────┘
```

Two worlds, one seam:

- **Native (Swift/SwiftUI):** everything that touches PDF rendering, Pencil,
  files, and iCloud. No web substitute exists for PDFKit + PencilKit.
- **Web (Vue + WASM):** the bridge popout. Existing gallery components and the
  Rust PBN/double-dummy libraries ship as bundled static assets in a
  `WKWebView`. Nothing is ported.
- **The seam:** native extracts the Contract 5 payload, hit-tests taps against
  `lesson-block:` annotations, and posts `{ blockBody, pbn, kind }` into the
  webview. The webview owns all bridge semantics.

## Baseline decisions

| Decision | Choice | Why |
|---|---|---|
| Minimum OS | iPadOS 17 | `PDFPageOverlayViewProvider` needs 16; 17 gives a comfortable API floor and covers any iPad worth presenting from |
| UI framework | SwiftUI shell, UIKit-backed where PDFKit demands it | PDFView is UIKit; wrap once, stay SwiftUI elsewhere |
| Bridge popout | WKWebView + bundled Vue build | Reuse, not port (see ADR-001 below) |
| Rust libraries | wasm32 build into the webview bundle | One build of dealer3/bridge-solver logic serves web gallery and iPad both |
| Annotation persistence | Sidecar file per PDF, keyed by content hash | GoodReader-style: fast, editable, original PDF untouched; hash key survives renames and fits deal-repo conventions |
| Distribution | Personal/TestFlight first | One user, one iPad; App Store is a later question |
| License | Public repo — the Unlicense, the org's house default (see ADR-002) | Original work goes public domain; permissive/copyleft licenses appear in the org only where an upstream forces them |

## Phases

Ordered so every phase ends with something usable in the Tuesday class.

### Phase 0 — Scaffold (a day)

- Create repo, Xcode project, SwiftUI app target, iPadOS 17 baseline.
- Decide bundle ID under existing Apple Developer account.
- `docs/` seeded with this plan and ADR-001 (webview popout decision).
- Stub CI later; not worth it before there's code to build.

**Exit:** app launches to an empty tab strip on the iPad.

### Phase 1 — PDF presentation shell — **built**

- Tabbed documents: open from Files (`.fileImporter`, multi-select), tab strip
  with close and drag-to-reorder. Reopening an open file selects its tab
  rather than duplicating it.
- One reused `PDFView` across tabs — not one per tab, since eight open lessons
  is the working set and Phase 6 already plans a performance pass at that size.
  Continuous vertical scroll, pinch zoom, page thumbnails sidebar.
- Session restore: tabs and page positions persist to
  `Application Support/session.json` as security-scoped bookmarks. Files that
  moved or were deleted are dropped rather than reopened broken; stale
  bookmarks are re-issued.
- Presentation mode: hides tab strip, controls, and status bar; page goes
  edge-to-edge on the dark surround.

**Verified on an iPad Pro 13" simulator:** rendering, thumbnails, page
restore, presentation mode, and a full quit-and-relaunch session restore.

**Covered by tests** — 34 in total, split by what each kind can reach:
`LessonStageTests` (22, ~0.15s) over tab-management rules and session
persistence; `LessonStageUITests` (12, ~90s) over everything needing real
touch — tab switch, close, close-selects-neighbour, drag-to-reorder, pinch
zoom, swipe-scroll page tracking, sidebar toggle, presentation mode, and the
popout's tap-to-play. Run with:

```bash
xcodebuild test -project app/LessonStage.xcodeproj -scheme LessonStage \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

Tests generate their own PDFs rather than carrying binary fixtures; the two
differ in page count so "Page 1 of N" proves which document is on screen.
PDF page *text* is not dependably exposed to the accessibility tree, so it
makes a poor assertion target — the page count is the sturdy one.

**Exit:** GoodReader-parity for *viewing*. Usable in class read-only.

### Phase 2 — Apple Pencil (2–3 weeks)

Two sub-phases, shippable independently:

**2a — Draw mode. Built.** `PKCanvasView` per page via
`PDFPageOverlayViewProvider`; per-page `PKDrawing` storage; sidecar
persistence keyed by content hash; undo; eraser; a minimal custom palette.

- **A minimal palette, not `PKToolPicker`.** The picker attaches to a single
  first responder, and this app has one canvas *per page* — a dozen live at
  once in continuous scroll. Driving the picker's first-responder dance across
  them costs more than the palette it replaces, and 2b needs custom stroke
  routing anyway.
- **`.pencilOnly` drawing policy**, so a finger still scrolls and zooms while
  the Pencil marks — no mode switching. A toggle turns marking off entirely
  for when the Pencil should scroll instead.
- **Two non-obvious requirements**, both found by running it: the PDF's pan
  gesture must be made to `require(toFail:)` the canvas's drawing gesture in
  `willDisplayOverlayView`, or strokes never reach the canvas; and
  `PDFView.pageOverlayViewProvider` is a **weak** property, so the provider
  has to be owned elsewhere.
- Saves are debounced (a file write inside the Pencil's input path is the one
  place latency is unforgivable) and flushed on close and on backgrounding.

**Verification split:** everything except stroke creation is covered — the
sidecar, hashing, per-page storage, versioning, and the palette. Strokes
themselves cannot be tested in the simulator: PencilKit does not build strokes
from synthesized touches, confirmed by instrumenting a running build. Those
three tests are written and skip on the simulator; they run on a paired iPad,
where `-fingerDrawing` lets a finger draw.

**2b — Copy mode (the GoodReader gesture). Mechanism built; feel iteration
pending on device.** Each stroke is routed at touch-down in
`PageCanvasView.touchesBegan`: hit-test the point against the page's text
layout — on a character, run a PDFKit selection and commit a `.highlight`
annotation from the selection's per-line bounds; on whitespace, fall through
to the PencilKit canvas as ink. Highlights persist in the same content-hash
sidecar as the ink (never touching the source PDF), and the eraser removes a
highlight under a tap as well as ink.

Two findings, both from running it on the simulator with the diagnostics tab:

- **`PDFPage.characterIndex(at:)` returns the *nearest* glyph, not −1 off
  text** — so it reports "on text" everywhere, margins included, which would
  make inking in copy mode impossible. The real test is whether that
  character's `characterBounds(at:)` actually contains the point. That is the
  whole routing decision and it was silently wrong until the on-screen
  diagnostics showed a margin drag reporting "on text".
- **Points must be converted through `PDFView`, not assumed to be page space.**
  The canvas overlay is UIKit (top-left); a PDF page is bottom-left. Routing
  the touch through `pdfView.convert(_:to: page)` is what keeps the hit-test
  where the finger is.

**Still to iterate (the plan always had this as the open-ended half):**
- **Selection geometry.** `document.selection(from:at:to:at:)` selects the
  text *flow* between two points, so a drag along one line can catch the next.
  GoodReader feels like it highlights what the swipe passed over. Tuning this
  — and rotated pages, two-column lessons, selection ends — is device-and-
  Pencil work.
- A colour picker for highlights (the model already carries a colour).

**Verification.** The routing decision, the highlight lifecycle (commit →
render → persist → reload), and remove-by-point are covered — 49 unit tests
and simulator-reachable UI tests, since the highlight path is our own touch
handling plus PDFKit selection, *not* PencilKit's stroke builder. Only the
touch-precise erase-tap and ink strokes need a device (4 skipped tests).

**Exit:** GoodReader-parity for the annotation workflow actually used in
class. GoodReader retired for ordinary lessons.

### Phase 3 — Contract 5 consumer (1 week)

- CGPDF attachment extraction: walk the catalog `/AF` array and
  `/EmbeddedFiles` name tree via `PDFDocument.documentRef`; locate by
  `AFRelationship`, filename fallback. (~150 lines; the least pleasant code
  in the app.)
- Parse `lesson-blocks.json` (version-dispatch first) and `lesson-hands.pbn`.
- Surface `lesson-block:` link annotations as tap targets — PDFKit gives
  these first-class (`page.annotations`), so hit-testing is free; the
  attachment parse runs once per document load for bodies + PBN.
- Join via `blocks[].board` — *not* `index`. PBN boards are renumbered
  sequentially from 1, so index-to-board is not an identity. Respect
  `unlocated`; prefer `fragments` over `rect` for hit-testing when present.
- Debug overlay: outline tappable blocks (reuse the layout-debug overlay
  habit from the grid arranger work).

**Exit:** tapping a board in a lesson PDF logs the right block body and deal.
Nothing visible to students yet, but the seam is proven.

### Phase 4 — Bridge popout (1–2 weeks; **de-risked by the Phase 0 spike**)

The plumbing is already built and proven — see
[ADR-003](adr/ADR-003-popout-runs-vue-directly.md). Vue build bundled as app
resources, served over a `lesson-popout://` custom scheme, one warm
`WKWebView`, and a working two-way message bridge. What remains is breadth,
not architecture.

- Extend the vendored closure to the components each priority needs
  (`BridgeTable`, `AuctionTable`, `BiddingBox`, `DoubleDummyTable`), running
  the same coupling audit on each.
- Message bridge carries the real payload: native → JS
  `{ kind, blockBody, pbn }` from the Contract 5 attachment; JS → native for
  close/resize.
- Popout UI, in priority order:
  1. Deal table from PBN — **partial deals must work**; one-seat hands are the
     norm per Contract 5, and the spike used a full deal only because trick
     play needs four hands.
  2. Card play with **proper trick history** — largely existing behaviour:
     `cardplayRules.js` derives state from an ordered play list, so stepping
     back is truncation.
  3. Auction stepper: bid-by-bid advance with explanations from the block
     body. Degrades on multi-auction lessons — Contract 5 emits `[Auction]`
     only when a lesson has exactly one.
  4. DD analysis on demand, via solver-service through `ddsClient.js`.
     **Resolve the CORS question first** — a custom-scheme origin calling the
     service either needs allowlisting or a native proxy.

Rust-to-WASM is **not** part of this phase; see ADR-003.

**Exit:** the motivating demo — tap a hand on the projector, play it out
trick by trick.

### Phase 5 — iCloud lessons folder (1 week)

- Folder picker → security-scoped bookmark, persisted.
- On launch: enumerate the lessons folder, `startDownloadingUbiquitousItem`
  for anything not local, surface "today's lessons" (date-named folder or
  most-recent, whichever matches the library's layout).
- One-tap "open today's set as tabs" replacing the weekly import/discard
  ritual.

**Exit:** Tuesday morning is: open app, tap today, teach.

### Phase 6 — Classroom polish (ongoing)

- External display: default mirroring works day one; later, a dedicated
  `UIWindowScene` on the projector (clean student view) while the iPad shows
  tools — presenter-mode territory, only if mirroring ever feels limiting.
- Performance pass with 8 large PDFs open.
- Export: flatten Pencil drawings into a PDF copy for sharing marked-up
  lessons.

## Risks and open questions

| Risk | Mitigation |
|---|---|
| Copy-mode feel is fiddly (rotated pages, columns, selection ends) | Phase 2b is explicitly iterative; 2a ships value first |
| CGPDF attachment walking is low-level C API | Isolate in one module with tests against known lesson PDFs; failure mode is "popout unavailable," never a crash |
| ~~Contract 5 `rect` may fragment across columns~~ **Resolved** in the 2026-07-23 contract review | `rect` is the largest piece, `fragments` carries every piece in reading order, never unioned. Consumer hit-tests `fragments` when present and treats duplicate `lesson-block:` URIs as multiple tap targets for one block |
| ~~WASM build of Rust libs not yet proven~~ **Dropped** — the popout needs no Rust (ADR-003) | Bridge semantics already exist in JS in Bridge-Classroom; DD goes to solver-service. The replacement risk is CORS from a custom-scheme origin to that service |
| Bridge-Classroom is mid-refactor while the popout depends on its components | Vendor a snapshot rather than reference it, as lesson-studio did; swap to `@bridge-craftwork/bridge-components` when Contract 2's package lands |
| pdf-handouts may strip attachments | Already decided direction: `pdf:attach` runs as final pipeline stage; this app should still degrade gracefully to plain-PDF mode |
| One-person project, many phases | Every phase exits classroom-usable; stopping after Phase 2 still beats GoodReader for this workflow |

## ADR-001 (seed): Bridge popout is a webview, not a port

**Context.** A mature Vue component gallery (board display, DD tables,
auction views) and Rust bridge libraries already exist and are tested.
**Decision.** The popout hosts the Vue build + Rust-as-WASM in `WKWebView`.
Components are not ported to SwiftUI.
**Consequences.** One implementation, no drift, gallery-first testing carries
over; cost is slightly non-native feel and a warm-instance startup cost,
both acceptable for projected tap-driven interaction. Revisit per-component
only if a component needs native input (e.g., Pencil inside the popout).

## Repo layout (proposed)

```
/app            Xcode project (SwiftUI shell)
/popout         Vue popout: Vite build + vendored Bridge-Classroom components
/docs           This plan, ADRs, Contract 5 consumer notes
/fixtures       Known-good lesson PDFs for tests
```

`/wasm` is gone — the popout needs no Rust (ADR-003).

`/popout` **vendors** the components rather than referencing them, because
Bridge-Classroom is mid-refactor and lesson-studio already hit the same wall.
Swap to Contract 2's `@bridge-craftwork/bridge-components` package when it
exists.
