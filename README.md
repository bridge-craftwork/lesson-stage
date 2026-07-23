# lesson-stage

Presentation tool for PBN-embedded PDF lesson files. An iPadOS app for
classroom bridge teaching: a tabbed PDF presenter with Apple Pencil
annotation, and a tap-to-open interactive bridge popout driven by the lesson
payload embedded in the PDF itself.

It replaces GoodReader in the classroom workflow, and adds the thing
GoodReader can never have: bridge knowledge. Tap a hand on the projector and
play it out, trick by trick.

## Status

**Phase 0 — scaffold.** The app launches to an empty tab strip. No PDF
handling yet.

Also done, early and out of order: a **working bridge popout spike**. Real
unmodified Bridge-Classroom components (`HandDisplay`, `TrickArea`) run in a
`WKWebView`, driven by the real `cardplayRules.js`, with a two-way native↔JS
message bridge. It exists because it settled the project's biggest open
question — see [ADR-003](docs/adr/ADR-003-popout-runs-vue-directly.md).

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
