# Vendored Bridge-Classroom components (snapshot)

A **snapshot copy** of the Bridge-Classroom rendering components the popout
needs, plus their dependency closure. Copied rather than referenced for the
same reason lesson-studio copied its own set: Bridge-Classroom is mid-refactor,
and a spike should not be able to break when it lands.

- **Source:** `bridge-craftwork/Bridge-Classroom` @ `6b7b10a`
  (`src/components/`, `src/utils/`), 2026-07-22.
- **Closure:** `HandDisplay.vue`, `TrickArea.vue`, `CardSelectorPopup.vue`,
  `handMetrics.js`, `cardFormatting.js`, `handFit.js`, `cardplayRules.js`.
- **Edits:** none. Byte-for-byte upstream.

## Auction rendering (added 2026-07-24)

The auction is drawn by the same component the PDFs are built with, so the
popout matches the printed lesson. Snapshotted from **`lesson-studio`**'s own
vendored set (which in turn snapshots Bridge-Classroom, with `getSeatOrder`
lifted into `utils/seatOrder.js`):

- **`components/AuctionTable.vue`**, `components/auctionMetrics.js`,
  `utils/seatOrder.js` — the renderer + its footprint constants.
- **`dsl/auction-block.ts`, `dsl/call.ts`** — lesson-studio's Contract 1 auction
  DSL parser. `parseAuctionBlock(body)` → `toAuctionProps` feeds `AuctionTable`.
  Their `import type { … } from './types'` is type-only and erased by esbuild,
  so `types.ts` is not vendored.
- **Edits:** none.

The directory layout mirrors upstream (`components/` beside `utils/`) precisely
so the relative imports inside these files resolve unchanged — that is what
makes "no edits" possible.

**Coupling audit** (the thing this spike had to establish): the closure imports
nothing from stores, router, API, or env. `HandDisplay` and `TrickArea` are
props-in / events-out, and `cardplayRules.js` is pure functions over plain
objects. No credential or session surface follows them into the popout.

**Do not hand-edit these files.** To update, re-copy from Bridge-Classroom.
When Contract 2's `@bridge-craftwork/bridge-components` package exists, this
directory should be replaced by a dependency on it.
