# lesson-stage

Presentation tool for PBN-embedded PDF lesson files. An iPadOS app for
classroom bridge teaching: a tabbed PDF presenter with Apple Pencil
annotation, and a tap-to-open interactive bridge popout driven by the lesson
payload embedded in the PDF itself.

It replaces GoodReader in the classroom workflow, and adds the thing
GoodReader can never have: bridge knowledge. Tap a hand on the projector and
play it out, trick by trick.

## Status

**Phase 2 — Apple Pencil annotation.** Marking with a Pencil: pen in three
colours, highlighter, stroke eraser, and undo. In copy mode (highlighter), a
stroke that starts on text becomes a text highlight and one that starts on
whitespace becomes ink — the GoodReader gesture. Annotations are stored in a
sidecar keyed by the PDF's content hash — the original file is never modified,
and marks survive a rename or re-download. A finger still scrolls and zooms
while the Pencil draws.

Copy mode is confirmed on device: a drag selects the text it spans with a live
preview, forgiving of where it starts. Undo covers ink and highlights together,
and "clear all marks" wipes everything in one undoable step.

**Phase 1 — PDF presentation shell.** Tabbed PDF viewing with continuous
scroll, pinch zoom, a page thumbnail sidebar, drag-to-reorder tabs, a
presentation mode that strips all chrome, and session restore that reopens
last session's tabs on the page each was left on.

Touch-driven interactions are covered by the `LessonStageUITests` target.
Stroke creation is the one thing that cannot be: PencilKit ignores synthesized
touches in the simulator, so those tests skip there and run on a device.

Also done, early and out of order: a **working bridge popout spike**. Real
unmodified Bridge-Classroom components (`HandDisplay`, `TrickArea`) run in a
`WKWebView`, driven by the real `cardplayRules.js`, with a two-way native↔JS
message bridge. It exists because it settled the project's biggest open
question — see [ADR-003](docs/adr/ADR-003-popout-runs-vue-directly.md).

### Debug launch arguments

Neither the document picker nor a tap can be scripted, so debug builds accept:

| Argument | Effect |
|---|---|
| `-open <path>…` | Open PDFs directly, bypassing the picker |
| `-page <n>` | Put the active tab on 1-based page `n` |
| `-thumbnails` | Start with the page sidebar showing |
| `-present` | Start in presentation mode |
| `-popout` | Open the bridge popout immediately |
| `-reset` | Discard the saved session before restoring |
| `-fingerDrawing` | Let a finger draw, not just a Pencil (tests, and the simulator) |

See [docs/PLAN.md](docs/PLAN.md) for the full phase plan. Each phase is
ordered to end with something usable in a Tuesday class.

## Layout

```
/app        Xcode project (SwiftUI shell)          ← Phase 0
/popout     Vue popout + vendored components       ← spiked
/docs       Plan, ADRs, Contract 5 consumer notes
/fixtures   Known-good lesson PDFs for tests       ← Phase 3
```

## Building

Requires Xcode 16 or later and an iPad or simulator running iPadOS 17+.

```bash
open app/LessonStage.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project app/LessonStage.xcodeproj -scheme LessonStage \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

After changing anything under `popout/src`, rebuild the web bundle and copy it
into the app's resources:

```bash
./popout/sync-to-app.sh
```

## Tests

```bash
xcodebuild test -project app/LessonStage.xcodeproj -scheme LessonStage \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

Two test targets, split by what they can reach:

- **`LessonStageTests`** — 22 unit tests over the tab-management rules and
  session persistence. Runs in under a fifth of a second, so it is the one to
  run constantly. Add to it by default.
- **`LessonStageUITests`** — 12 tests driving the app through real synthesized
  touches: the only way to cover tab switching, closing, drag-to-reorder,
  pinch zoom, and the popout's tap-to-play. ~90 seconds.

Either can be run alone with `-only-testing:LessonStageTests`. Both generate
their own PDFs rather than carrying binary fixtures.

On a paired iPad, swap the destination for
`-destination 'platform=iOS,name=<device name>'`.

Launching with `-popout` opens the bridge popout straight from launch, which
is how the spike is driven without a tap.

The bundle identifier is `com.popperbiz.LessonStage` with automatic signing
under team `8H3FX5B8KD`, matching the sister apps in `harmonic-systems-home`.

## How it fits together

Two worlds, one seam:

- **Native (Swift/SwiftUI)** owns everything touching PDF rendering, Pencil,
  files, and iCloud. There is no web substitute for PDFKit + PencilKit.
- **Web (Vue)** owns the bridge popout — the existing Bridge-Classroom
  components, bundled as static assets and served to a `WKWebView` over a
  `lesson-popout://` custom scheme. Nothing is ported, to SwiftUI or to Rust.
  See [ADR-001](docs/adr/ADR-001-webview-popout.md) and
  [ADR-003](docs/adr/ADR-003-popout-runs-vue-directly.md).
- **The seam:** native extracts the Contract 5 payload, hit-tests taps against
  `lesson-block:` link annotations, and posts `{ kind, blockBody, pbn }` into
  the webview. The webview owns all bridge semantics.

Lesson PDFs carry their own source, click map, and deals as embedded files —
see [Contract 5 consumer notes](docs/contract-5-consumer.md). PDFs without a
payload still open and annotate normally; the popout is simply unavailable.

## License

Released into the public domain under [the Unlicense](LICENSE), matching the
bridge-craftwork house default. See
[ADR-002](docs/adr/ADR-002-license.md).
