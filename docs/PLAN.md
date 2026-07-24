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

**2b — Copy mode (the GoodReader gesture). Built and confirmed on device.**
With the highlighter selected, a drag selects whatever text it spans and
commits a `.highlight` on release; the selection is previewed live in the
tool's colour as it grows. A drag that crosses no text does nothing. Highlights
persist in the same content-hash sidecar as the ink (never touching the source
PDF), the eraser removes a highlight under a tap, undo steps back through ink
and highlights together, and "clear all marks" wipes everything in one
undoable step. Plus a colour picker's worth of pen colours; a *highlight*
colour picker is the one deferred nicety (the model already carries the
colour).

This was the hardest part of the app so far — not in volume of code but in the
number of PDFKit behaviours that are invisible to the simulator and only
surface on a device. Recorded here because every one cost a device round-trip
and would cost another if forgotten:

- **`PDFPageView` ships with `isUserInteractionEnabled = false`.** PDFKit
  hit-tests at the `PDFView` level, so it disables its page views — and a
  disabled view drops touches for its whole subtree, so the overlay canvas
  never saw a touch. Interaction is re-enabled on the ancestors up to the
  `PDFView`. This is why the Pencil did nothing at first.
- **`PDFPage.characterIndex(at:)` returns the *nearest* glyph, not −1 off
  text.** It reports "on text" everywhere, margins included. The real test is
  whether that character's `characterBounds(at:)` contains the point.
- **`quadrilateralPoints` are bounds-origin-relative, not page space** —
  despite the SDK header saying "page space." Absolute coordinates offset every
  highlight up and to the right, worse for larger selections.
- **Points must be converted through `PDFView`** (`convert(_:to: page)`): the
  canvas overlay is UIKit top-left, a PDF page is bottom-left.
- **The live preview saturates the main thread.** A normal drag fires hundreds
  of coalesced move events; rebuilding the preview annotation on each starves
  the render pass, so nothing paints until release. Throttled to one rebuild
  per frame, with the final span always applied unthrottled on release.
- **Remove-then-add flickers.** PDFKit can paint the removal and the addition
  on separate frames. Add the new annotation before removing the old.
- **Ink is disabled for the highlighter**, so it is a pure text tool: a Pencil
  on whitespace does nothing, a finger still scrolls. (Under `-fingerDrawing`
  the tests keep ink on so a test finger can reach the canvas past the
  fingers-only scroll pan; that path leaves a stray marker, so the erase-tap
  and undo-highlight UI tests are device-only.)

The diagnostics tab (a debug-only tab showing touch routing and canvas
placement, with a Copy button) is what made this tractable — it put on the
glass the facts a simulator could not. Worth keeping.

**Verification.** Routing (span text vs nothing, forgiving margin start), the
highlight lifecycle (commit → render → persist → reload), de-overlap geometry,
remove-by-point, and clear-all-then-undo are covered — the highlight path is
our own touch handling plus PDFKit selection, *not* PencilKit's stroke builder,
so it runs under synthesized touches. Only ink strokes and the touch-precise
erase/undo taps need a device (5 skipped tests).

**Exit:** GoodReader-parity for the annotation workflow actually used in
class. GoodReader retired for ordinary lessons. **Met** — 2a and 2b both
confirmed on device.

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

### Phase 5 — iCloud lessons folder — **built**

Folder-structure-agnostic and config-driven throughout, so it can ship
publicly rather than being wired to one person's Drive layout.

- **Discovery engine** (`Library/`): `LessonLibrary.discoverDays` recurses a
  chosen root reading folder and file *names* only — never downloading from
  iCloud — and finds folders whose name carries a date, taking the date from
  that folder's name (walking through year/month folders without parsing
  them). `window(_:around:before:after:)` anchors on today-or-next; globs and
  window sizes come from a persisted `LibraryConfiguration`, nothing hardcoded.
- **Settings sheet** (`SettingsView`, a gear in the tab strip): a toggle
  "Enable Load from Library", off by default so ordinary users never see the
  feature. Enabling reveals a directory picker (`fileImporter` over `.folder`
  → security-scoped bookmark) and, once configured, editable ignore-globs and
  before/after window sizes.
- **Day list** (`LibraryDayListView`, a calendar button shown only when
  enabled): the window of days around today — date, handout count, the
  today-or-next anchor badged, precreated-but-empty days dimmed "Not planned".
  Tapping a populated day replaces the open tabs with its handouts and kicks
  off `startDownloadingUbiquitousItem` for any that are still remote.
- **Persistence** (`LibraryStore`): the enabled flag and the configuration
  (with its root bookmark) in `library.json`, resolved and refreshed-if-stale
  on launch, exactly as `SessionStore` does for the open tabs.

**Verification.** Discovery, windowing, glob filtering, the store round-trip,
the manager's configure→discover and resolve-on-relaunch, and the
replace-all-tabs path are unit-tested against a local temp tree; the settings
toggle and day list are UI-tested (root handed in by `-libraryRoot`, since the
directory picker is a system UI a test cannot drive). iCloud download *state*
cannot be simulated, so `openDay`'s remote path is confirmed on device; every
local-file path is covered.

**Exit:** Tuesday morning is: open app, tap today, teach. **Met** — pending a
device pass over the iCloud download path.

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
