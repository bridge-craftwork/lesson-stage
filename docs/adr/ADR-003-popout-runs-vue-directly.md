# ADR-003 — The popout runs the Vue components directly; nothing is ported

**Status:** Accepted — **proven by a running spike**, not by argument
**Date:** 2026-07-22
**Extends:** [ADR-001](ADR-001-webview-popout.md)

## Context

ADR-001 decided the popout would be a webview rather than a SwiftUI port, but
decided it on reasoning alone. Two questions were still open, and both governed
weeks of work:

1. Can the existing Vue components run *directly* in the iPad app, or must they
   be ported to SwiftUI?
2. Does the popout need the Rust libraries compiled to WASM to supply bridge
   semantics?

An inventory of Bridge-Classroom answered the second before any code was
written, and changed the shape of the first.

## What the inventory found

Every Phase 4 popout priority already exists in Vue/JS in Bridge-Classroom:

| Popout priority | Existing implementation |
|---|---|
| Deal table from PBN | `BridgeTable.vue`, `HandDisplay.vue`, `pbnParser.js`, `pbnDeal.js` |
| **Card play with trick history** | `TrickArea.vue`, `cardplayRules.js`, `cardplayBots.js`, `defenseTrick.js` |
| Auction stepper | `AuctionTable.vue`, `BiddingBox.vue` |
| DD analysis | `DoubleDummyTable.vue`, `ddsClient.js` (service-backed) |

The headline feature — trick history, the thing GoodReader cannot do — is not
merely present but *structural*. `cardplayRules.js` derives all state from an
ordered list of plays (`computeRemaining(originalHands, played)`,
`nextSeatToPlay({ currentTrick, completedTricks }, …)`). In that model,
stepping back through tricks is truncating an array. There is nothing to build.

**The Rust libraries and the JS components are parallel lineages, not layers.**
Rust serves the CLI and service side; JS serves the interactive client. The
gallery has never consumed the Rust libraries, so WASM would not be *feeding*
the components — it would be *replacing* working, tested JS.

## Decision

**The popout loads the Vue build directly in a `WKWebView`. Nothing is ported
— not to SwiftUI, and not to Rust.**

Corollaries:

- **DD analysis goes through solver-service** via the existing `ddsClient.js`.
  Classroom Wi-Fi is reliable, which removes the only real argument for
  on-device DD.
- **WASM is deferred indefinitely**, not scheduled. If it ever returns, the
  target is `bridge-solver` alone, behind one call — the narrow escape hatch
  ADR-001 already describes. `/wasm` is dropped from the repo layout until then.
- **Components are vendored as a snapshot**, not referenced, matching what
  lesson-studio did and for the same reason: Bridge-Classroom is mid-refactor.
  Replace the snapshot with Contract 2's `@bridge-craftwork/bridge-components`
  package once it exists.

## The spike that proved it

`/popout` is a Vite + Vue app that mounts **unmodified** `HandDisplay.vue` and
`TrickArea.vue` from Bridge-Classroom `6b7b10a`, driven by the real
`cardplayRules.js`. It builds to 79 KB of JS and 8 KB of CSS, is bundled as app
resources, and is served over a `lesson-popout://` custom scheme.

Verified running on an iPad Pro 13" simulator:

- Four hands render with correct HCP, suit symbols, and colours.
- Native posted five plays across the seam; the popout formed one completed
  trick, awarded it correctly (N won with ♦A → NS 1 · EW 0), removed the played
  cards from all four hands, recomputed HCP (N 21 → 13), and put E on lead to
  the second trick.
- The round trip works in both directions: JS → native `{type: "ready"}` on
  mount, native → JS `window.lessonStage.load(payload)` in response.

### What the spike changed

**The components carry a light-surface visual contract.** They use scoped
styles with literal colours — `.suit-black { color: #1a1a1a }`. Mounted on the
app's dark surround, the black suits were invisible. The fix is for the popout
to *supply the light surface the components expect*, not to override them:
overriding means forking, which is the drift this whole ADR exists to prevent.
So the app chrome stays dark and the popout is a lit table sitting inside it.

**The coupling audit passed.** The closure — `HandDisplay`, `TrickArea`,
`CardSelectorPopup`, `handMetrics`, `cardFormatting`, `handFit`,
`cardplayRules` — imports nothing from stores, router, API, or env. No
credential or session surface follows the components into the popout, which
matters because the popout will have neither.

## Consequences

Phase 4 shrinks from "build a bridge UI" to "extract components, wire the
seam, and style a surface." The remaining work is integration, not
implementation.

**A custom scheme, not `file://`.** File URLs put the webview in a unique
opaque origin where module scripts and `fetch` are blocked. Owning the scheme
means owning the response headers — which is also the lever for the CORS
question below, and the only route to cross-origin isolation if the popout ever
needs `SharedArrayBuffer`.

**One warm `WKWebView`, reused.** First load pays process spin-up and Vue's
mount; paying that on every tap in front of a class is the failure mode being
avoided.

**Everything crossing the seam is JSON.** No live object can span the boundary.
That is a constraint on future design, not just current code.

### Now the top integration risk: CORS to solver-service

`ddsClient.js` will call `https://…` from a `lesson-popout://` origin. That is
cross-origin, and the service may not recognise the origin it presents. Two
fixes, both acceptable: allowlist the origin server-side, or proxy the call
through native over the message bridge. The second keeps credentials out of the
webview entirely and is probably right for that reason.

This replaces WASM performance as the thing most likely to bite, and it is
much cheaper to fix.

### Still open

- **Partial deals.** The spike uses a full deal because trick play needs four
  hands. Real lesson hands are usually a single seat, with the rest written
  `-`. That is Contract 5 open item 3 and remains ours to close.
- **Pencil inside the popout** stays the one scenario that would justify a
  native component, per ADR-001. Unchanged.
