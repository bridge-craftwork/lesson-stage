<template>
  <!-- Pure holding renderer: cards + marks + HCP. No compass, name, presence, or
       turn state — those are seat identity (SeatChip). Geometry is a function of
       holding + marks + density, so it renders anywhere a holding appears.

       In-grid suit rows NEVER wrap and NEVER clip: a row is always exactly one
       line tall. When a suit is too long for its measured content zone even at
       the legibility floor, the leftmost cards that fit render and the row ends
       in a "+N" chip (the low cards of the suit — rendering is high→low). No
       capability is lost: the hidden cards stay viewable/selectable through the
       floating CardSelectorPopup, which floats above the layout and may wrap
       freely without pushing anything. SeatPanel supplies the box + frame. -->
  <div ref="rootEl" class="holding" :class="[densityClass, { compact, 'hide-played': hidePlayedCards, 'has-badges': hasBadges }]" :style="unitVars">
    <div v-if="hand" class="suits">
      <template v-for="suit in suits" :key="suit">
        <!-- Rank cells ALWAYS play their card directly — truncation never
             reroutes a rank tap (same-looking cell → same action; high cards
             render first, so the visible ones are the frequently played). The
             +N chip is the SOLE popup portal for the hidden low cards. -->
        <div
          v-if="!isPartialHand || hasSuitCards(suit)"
          class="suit-row"
          :class="{ truncated: hiddenCount(suit) > 0 }"
          :style="rowStyle(suit)"
          :ref="el => setRowRef(suit, el)"
        >
          <span class="suit-symbol" :class="suitClass(suit)">{{ suitSymbol(suit) }}</span>
          <span class="cards" :ref="el => setCardsRef(suit, el)"><template v-for="(card, i) in visibleRanks(suit)" :key="card"><span
            class="cell"
            :class="cellClass(suit, card)"
            :style="cellFill(suit, card)"
            @click.stop="onCellClick(suit, card)"
          >{{ formatCard(card) }}<span v-if="cardBadge(suit, card)" class="cell-badge">{{ cardBadge(suit, card) }}</span></span>{{ i < visibleRanks(suit).length - 1 ? ' ' : '' }}</template><span
            v-if="hiddenCount(suit) > 0"
            class="cell chip"
            :class="{ pill: clickable }"
            @click.stop="clickable ? openPopup(suit) : null"
          >+{{ hiddenCount(suit) }}<span v-if="hiddenMarked(suit)" class="chip-dot">•</span></span></span>
        </div>
      </template>
    </div>
    <div v-if="showHcp && hand && !isPartialHand" class="hcp">
      <template v-if="showTotalPoints && lengthPts > 0">{{ hcp }}+{{ lengthPts }} TP</template>
      <template v-else>{{ hcp }} HCP</template>
    </div>
    <!-- Hidden probe: each suit's FULL rendered cards + a worst-case chip at
         natural scale (1), one line. Its per-cell geometry is `needed` for the
         fit/truncation computation — stable regardless of the visible row's
         applied scale. Off-flow + hidden, so it never affects the holding. -->
    <div v-if="hand" class="hd-probe" aria-hidden="true">
      <template v-for="suit in suits" :key="'p' + suit">
        <div v-if="!isPartialHand || hasSuitCards(suit)" class="suit-row">
          <span class="suit-symbol">{{ suitSymbol(suit) }}</span>
          <span class="cards" :ref="el => setProbeRef(suit, el)"><template v-for="(card, i) in renderedRanks(suit)" :key="card"><span class="cell">{{ formatCard(card) }}</span>{{ i < renderedRanks(suit).length - 1 ? ' ' : '' }}</template></span>
          <span class="cell chip chip-probe" :class="{ pill: clickable }" :ref="el => setChipRef(suit, el)">+13</span>
        </div>
      </template>
    </div>
    <CardSelectorPopup
      v-if="popupSuit"
      :suit="popupSuit"
      :cards="popupCards"
      :anchor="popupAnchor"
      @select="onPopupSelect"
      @close="popupSuit = null"
    />
  </div>
</template>

<script setup>
import { computed, reactive, ref, onMounted, onBeforeUnmount, watch, nextTick } from 'vue'
import {
  SUIT_SYMBOLS,
  SUIT_ORDER,
  getSuitClass,
  formatCard,
  countHCP,
  sortSuitDescending
} from '../utils/cardFormatting.js'
import CardSelectorPopup from './CardSelectorPopup.vue'
import { computeFit, LEGIBILITY_FLOOR } from '../utils/handFit.js'
import { HAND_UNIT } from './handMetrics.js'

// Publish the shared unit geometry (handMetrics) as CSS vars so the full-density
// label zone + row gap read the SAME numbers the arranger provisions from. At
// 1.0× these equal the former literals (28px / 8px) → pixel-identical.
const unitVars = {
  '--hd-label-w': HAND_UNIT.labelPx + 'px',
  '--hd-gap': HAND_UNIT.gapPx + 'px',
}

const props = defineProps({
  hand: { type: Object, default: null },
  showHcp: { type: Boolean, default: false },
  // When true and lengthPts > 0, display "X+Y TP" instead of "X HCP".
  showTotalPoints: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
  // Interaction only: makes cells clickable (cursor + card-click emit).
  clickable: { type: Boolean, default: false },
  // Read-only "tap to inspect" mode (post-hand DD overlay). Independent of
  // `clickable` (which drives PLAY). When set, a cell click emits `card-inspect`
  // instead of playing — used at the reveal to open a card's DD alternatives.
  inspectable: { type: Boolean, default: false },
  // Annotation map: cards: { <code>: { played, badge, fill } } — per-card, keyed
  // by "SK"/"DT". (Seat-level marks like active-seat live on SeatPanel now.)
  marks: { type: Object, default: null },
  // Rendering budget: 'chip' | 'compact' | 'full'. Only 'full' wired (= today).
  density: { type: String, default: 'full' },
  // When true, played cards collapse out of the holding (live-play default);
  // when false they stay struck through (review / teaching).
  hidePlayedCards: { type: Boolean, default: false }
})

const emit = defineEmits(['card-click', 'card-inspect'])

// Cell click routes to PLAY when clickable, else to INSPECT when inspectable.
// The two modes are mutually exclusive in practice (play vs. post-hand review).
function onCellClick(suit, card) {
  if (props.clickable && !isCardPlayed(suit, card)) {
    emit('card-click', { suit: suitLetter(suit), rank: card })
  } else if (props.inspectable) {
    emit('card-inspect', { suit: suitLetter(suit), rank: card })
  }
}

const suits = SUIT_ORDER

// Cards ordered for display (A→2 per suit) regardless of the source's order.
const orderedHand = computed(() => {
  if (!props.hand) return props.hand
  const out = {}
  for (const suit of suits) out[suit] = sortSuitDescending(props.hand[suit] || [])
  return out
})

const hcp = computed(() => countHCP(props.hand))

const lengthPts = computed(() => {
  if (!props.hand) return 0
  let lp = 0
  for (const suit of suits) {
    const len = (props.hand[suit] || []).length
    if (len > 4) lp += len - 4
  }
  return lp
})

const totalCards = computed(() => {
  if (!props.hand) return 0
  return suits.reduce((sum, suit) => sum + (props.hand[suit]?.length || 0), 0)
})
// A "partial" hand drops void suits' rows so a tiny holding renders compactly.
// But during LIVE PLAY (`hidePlayedCards`) the hand started full and is depleting,
// and dropping rows as suits are exhausted makes it shrink top/bottom through the
// deal (2026-07-15 report) — the vertical twin of the width shrink. Keep the full
// 4-row structure in play so the hand's height sticks from the start of the deal
// (exhausted suits show an empty label row, as dealt voids already do at 5+ cards).
const isPartialHand = computed(() =>
  !props.hidePlayedCards && totalCards.value > 0 && totalCards.value < 5)

function hasSuitCards(suit) {
  return props.hand && props.hand[suit] && props.hand[suit].length > 0
}
function suitSymbol(suit) { return SUIT_SYMBOLS[suit] }
function suitClass(suit) { return getSuitClass(suit) }

const SUIT_LETTERS = { spades: 'S', hearts: 'H', diamonds: 'D', clubs: 'C' }
function suitLetter(suit) { return SUIT_LETTERS[suit] || suit }

const densityClass = computed(() => `density-${props.density}`)

function cardMark(suit, rank) {
  return props.marks?.cards?.[suitLetter(suit) + rank] || null
}
function isCardPlayed(suit, rank) { return !!cardMark(suit, rank)?.played }
// Current-trick card left in a shown hand (e.g. dummy's led card): highlighted, not
// struck. Non-interactive like a played card, but keeps its normal glyph.
function isCardCurrent(suit, rank) { return !!cardMark(suit, rank)?.current }
function cardBadge(suit, rank) { return cardMark(suit, rank)?.badge || null }
// Any card carrying a badge → reserve overhang room on the holding (below). Kept
// a whole-hand flag, not per-card, because the reservation is a holding-edge
// concern. Badge-free hands (all of production a1) never get the class.
const hasBadges = computed(() => {
  const cards = props.marks?.cards
  return !!cards && Object.values(cards).some((m) => m && m.badge)
})
function cellFill(suit, rank) {
  const fill = cardMark(suit, rank)?.fill
  return fill ? { backgroundColor: fill } : null
}
function cellClass(suit, rank) {
  return {
    played: isCardPlayed(suit, rank),
    current: isCardCurrent(suit, rank),
    interactive: props.clickable && !isCardPlayed(suit, rank) && !isCardCurrent(suit, rank),
    inspectable: props.inspectable && !(props.clickable && !isCardPlayed(suit, rank)),
    chosen: !!cardMark(suit, rank)?.chosen,
    'has-badge': !!cardBadge(suit, rank),
  }
}

// Ranks actually rendered in-grid for a suit: all of them, minus the played
// cards that collapse out in live play (hidePlayedCards). This is the set
// truncation operates on — playing a card removes it here, which only ever
// FREES width, so a formerly-hidden card can surface (monotone).
function renderedRanks(suit) {
  const cards = orderedHand.value?.[suit] || []
  if (!props.hidePlayedCards) return cards
  return cards.filter((c) => !isCardPlayed(suit, c))
}

// ── Measured per-row fit + truncation (math in ../utils/handFit) ────────────
const fit = reactive({})
const rootEl = ref(null)
const rowEls = {}
const cardsEls = {}
const probeEls = {}
const chipEls = {}
function setRowRef(suit, el) { if (el) rowEls[suit] = el; else delete rowEls[suit] }
function setCardsRef(suit, el) { if (el) cardsEls[suit] = el; else delete cardsEls[suit] }
function setProbeRef(suit, el) { if (el) probeEls[suit] = el; else delete probeEls[suit] }
function setChipRef(suit, el) { if (el) chipEls[suit] = el; else delete chipEls[suit] }

function rowStyle(suit) {
  const s = fit[suit]?.scale
  return s == null || s === 1 ? null : { '--suit-scale': s }
}
function hiddenCount(suit) { return fit[suit]?.hidden || 0 }
function visibleRanks(suit) {
  const list = renderedRanks(suit)
  const v = fit[suit]?.visible
  return v == null ? list : list.slice(0, v)
}
function hiddenMarked(suit) {
  const list = renderedRanks(suit)
  const v = fit[suit]?.visible ?? list.length
  return list.slice(v).some((c) => !!cardMark(suit, c))
}

// Overhang margin (natural px, pre-table-scale) shaved off available when
// compressing, so a compressed suit's last bold glyph clears the frame edge
// instead of spilling. Scaled by --table-scale at the call site.
const OVERHANG_MARGIN = 3

function measure() {
  if (!props.hand || !rootEl.value) return
  const rootStyle = getComputedStyle(rootEl.value)
  const tableScale = parseFloat(rootStyle.getPropertyValue('--table-scale')) || 1
  // Fit target = the region's ALLOCATED width (grid arranger publishes --alloc-width,
  // px at 1.0×), NOT the shrink-wrapped row. Measuring the fit off the rendered row is
  // circular — a compressed row measures narrow, so it stays compressed even when its
  // allocation has ample room (squeezed North to ~130px inside a 264px column,
  // 2026-07-13 report). The allocation is content-independent, breaking the loop.
  // Absent (legacy/console/server, or pre-first-ledger) → 0 → fall back to the row.
  const allocWidth = parseFloat(rootStyle.getPropertyValue('--alloc-width')) || 0
  for (const suit of suits) {
    const rowEl = rowEls[suit]
    const cardsEl = cardsEls[suit]
    const probeEl = probeEls[suit]
    if (!rowEl || !cardsEl || !probeEl) { if (fit[suit]) delete fit[suit]; continue }
    const probeRect = probeEl.getBoundingClientRect()
    const probeLeft = probeRect.left
    const cells = probeEl.querySelectorAll('.cell')
    // cumWidths[i] = natural width of the first (i+1) cards (right edge of cell,
    // excludes trailing letter-spacing) — drives the fit decision + trunc count.
    const cumWidths = Array.from(cells).map((c) => c.getBoundingClientRect().right - probeLeft)
    // natural = the probe `.cards` box: full content incl. the trailing letter-
    // spacing the last cell's right edge omits. Sizing compression against this
    // (not cumWidths[last]) is what stops the last card clipping past the edge.
    const natural = probeRect.width
    // available = fit width minus the fixed label zone (cards' left offset). The fit
    // width is the allocation (× table-scale, since alloc is 1.0× px and the row
    // renders scaled) when the arranger provides one, else the measured row.
    const rowRect = rowEl.getBoundingClientRect()
    const cardsRect = cardsEl.getBoundingClientRect()
    const labelZone = cardsRect.left - rowRect.left
    const available = (allocWidth > 0 ? allocWidth * tableScale : rowRect.width) - labelZone
    // Guard: a mid-transition / pre-layout measurement (the row not yet sized —
    // happens on client-side navigation back to a board) reads ~0 width. Never
    // commit a collapsed fit from it — skip, leaving the suit full until a real
    // (settled) measurement lands. Committing here is what stranded/compressed a
    // hand that a full refresh renders correctly.
    if (rowRect.width <= 0 || available <= 0) continue
    const chipReserve = chipEls[suit] ? chipEls[suit].getBoundingClientRect().width : 0
    // Truncate only when the popup is reachable (clickable) — otherwise the +N
    // strands cards with no way to see them. Non-clickable rows compress-to-fit.
    fit[suit] = computeFit({ cumWidths, available, natural, chipReserve, margin: OVERHANG_MARGIN * tableScale, floor: LEGIBILITY_FLOOR, allowTruncate: props.clickable })
  }
}

// Measure AFTER layout settles, not just after Vue's nextTick. On a fresh page
// load the layout is already settled when the component mounts, so a nextTick
// measure reads the right width — but on client-side navigation back to a board
// the container is still resolving at nextTick, so the measure reads a narrow box
// and, the box then being stable, the ResizeObserver never re-fires to correct
// it. A double rAF waits for the browser's layout/paint (the same settle the
// harness walk does before it screenshots).
function scheduleMeasure() {
  nextTick(() => {
    if (typeof requestAnimationFrame === 'undefined') { measure(); return }
    requestAnimationFrame(() => requestAnimationFrame(measure))
  })
}

let ro = null
onMounted(() => {
  scheduleMeasure()
  const el = rootEl.value?.parentElement || rootEl.value
  if (typeof ResizeObserver === 'undefined' || !el) return
  ro = new ResizeObserver(() => measure())
  ro.observe(el)
})
onBeforeUnmount(() => ro?.disconnect())
watch(() => [props.hand, props.density, props.compact, props.hidePlayedCards, props.marks], () => {
  scheduleMeasure()
}, { deep: true })

// ── Card-selector popup (reaches the truncated cards) ───────────────────────
const popupSuit = ref(null)
const popupAnchor = ref(null)
const popupCards = computed(() => {
  if (!popupSuit.value) return []
  return (orderedHand.value?.[popupSuit.value] || []).map((rank) => ({
    rank,
    played: isCardPlayed(popupSuit.value, rank),
    badge: cardBadge(popupSuit.value, rank),
    fill: cellFill(popupSuit.value, rank)?.backgroundColor || null,
  }))
})
function openPopup(suit) {
  if (!props.clickable || hiddenCount(suit) === 0) return
  const rowEl = rowEls[suit]
  if (rowEl) {
    const r = rowEl.getBoundingClientRect()
    popupAnchor.value = { top: r.bottom + window.scrollY + 4, left: r.left + window.scrollX }
  }
  popupSuit.value = suit
}
function onPopupSelect(rank) {
  const suit = popupSuit.value
  if (!suit || isCardPlayed(suit, rank)) return
  emit('card-click', { suit: suitLetter(suit), rank })
}
</script>

<style scoped>
.suits {
  display: flex;
  flex-direction: column;
  gap: calc(4px * var(--table-scale));
}

.suit-row {
  display: flex;
  align-items: center;
  gap: calc(var(--hd-gap, 8px) * var(--table-scale));
  font-family: 'Segoe UI', system-ui, sans-serif;
  /* --suit-scale (per row, default 1) compresses long suits horizontally to
     fit; below the floor the row truncates + shows a +N chip (never wraps or
     clips). At 1 this is calc(...*1) = today. */
  font-size: calc(24px * var(--table-scale) * var(--suit-scale, 1));
}
.suit-symbol {
  font-size: calc(27px * var(--table-scale));
  width: calc(var(--hd-label-w, 28px) * var(--table-scale));
  text-align: center;
  flex: 0 0 auto;
}

.suit-red { color: #d32f2f; }
.suit-black { color: #1a1a1a; }

.cards {
  min-width: 0;
  font-weight: 500;
  /* Always one line: compression + truncation keep it fitting, so it never
     wraps. letter-spacing scales with the row so a compressed suit fits. */
  white-space: nowrap;
  letter-spacing: calc(1px * var(--suit-scale, 1));
}

/* One card. Plain inline run (no box model), tight space-joined layout. */
.cell { display: inline; }

/* +N truncation chip. Non-clickable (console tiles): undressed, full-weight ink
   — it's information, not metadata-gray — and inert, so it never steals the
   tile's whole-surface click-through. A real left gap separates it from the last
   rank cell in both modes. */
.cell.chip {
  color: #1a1a1a;
  font-weight: 600;
  pointer-events: none;
  margin-left: calc(6px * var(--table-scale) * var(--suit-scale, 1));
}
/* Clickable: the sole popup portal, dressed in the tappable vocabulary (kin to
   bidding-box buttons + the popup's card cells) — bordered rounded pill, subtle
   background, NOT purple (purple is the badge/annotation channel). Padding and
   radius are in em so the pill compresses with the row like any cell. */
.cell.chip.pill {
  position: relative;
  display: inline-flex;
  align-items: center;
  padding: 0.04em 0.32em;
  border: 1px solid #cfd6ce;
  border-radius: 0.42em;
  background: #f2f6f1;
  pointer-events: auto;
  cursor: pointer;
  transition: background 0.15s, border-color 0.15s;
}
.cell.chip.pill:hover { background: #e3efe6; border-color: #7cc59b; }
.cell.chip.pill:active { background: #d3e7d9; }
/* Extend the hit area into the row's trailing slack (rightward + a vertical
   bleed) to a ≥44px effective target, WITHOUT crossing the pill's left edge:
   left:0 keeps the target off the last visible rank cell (the margin-left gap is
   real slack), so a tap near that boundary can't ambiguously play the last card
   vs open the popup. Absolute → overflows without affecting row height. */
.cell.chip.pill::after {
  content: '';
  position: absolute;
  left: 0;
  right: calc(-30px * var(--table-scale));
  top: calc(-8px * var(--table-scale));
  bottom: calc(-8px * var(--table-scale));
}
.cell.chip .chip-dot { color: #6a1b9a; font-size: 0.8em; vertical-align: 0.15em; }

.cell.played {
  opacity: 0.4;
  text-decoration: line-through;
  cursor: default;
  user-select: none;
}
/* Current-trick card left in a shown hand (e.g. dummy's led card): a light-blue
   highlight instead of the strikethrough — it's on the table now, not spent. The
   box-shadow pads the fill without changing the cell's box, so the fit probe (which
   measures the un-highlighted width) stays honest. */
.cell.current {
  background: #bbdefb;
  border-radius: 3px;
  box-shadow: 0 0 0 2px #bbdefb;
  cursor: default;
  user-select: none;
}
.holding.hide-played .cell.played { display: none; }
/* Tap-to-inspect (post-hand DD review): pointer affordance without the play
   hover styling. Error cards additionally carry a `fill` background + badge. */
.cell.inspectable { cursor: pointer; }
/* The specifically chosen card in a recoloured review trick: a dark ring over
   the green/pink fill so it reads as "this is the card that was played". */
.cell.chosen {
  border-radius: 3px;
  box-shadow: 0 0 0 2px #333;
}

.cell.interactive {
  cursor: pointer;
  border-radius: 3px;
  transition: background 0.15s;
  user-select: none;
}
.cell.interactive:hover { background: #bbdefb; }
.cell.interactive:active { background: #90caf9; }

.cell.has-badge { position: relative; }
/* Corner annotation chip. Offsets, font and padding ride BOTH scales —
   --table-scale (design scale) and --suit-scale (this row's compression, which
   custom props inherit into the cell) — so the badge stays glued to its glyph at
   every size instead of floating oversized on a compressed row. At table-scale 1
   / suit-scale 1 these equal the original px, so nothing shifts at 1×. */
.cell-badge {
  position: absolute;
  top: calc(-7px * var(--table-scale) * var(--suit-scale, 1));
  right: calc(-3px * var(--table-scale) * var(--suit-scale, 1));
  font-size: calc(10px * var(--table-scale) * var(--suit-scale, 1));
  line-height: 1;
  font-weight: 700;
  letter-spacing: 0;
  color: #fff;
  background: #6a1b9a;
  border-radius: 8px;
  padding: calc(1px * var(--table-scale) * var(--suit-scale, 1)) calc(4px * var(--table-scale) * var(--suit-scale, 1));
}
/* Containment: reserve the badge's overhang as holding padding, ONLY when the
   hand carries badges (badge-free a1 hands stay pixel-identical). This replaces
   the old first-row-only `top: 2px` nudge — the padding-top keeps a first-row
   badge below the frame edge on EVERY row uniformly, and the padding-right both
   keeps a right-edge badge inside the frame AND narrows the row's measured
   `available`, so the suit-fit leaves room for that badge automatically. Sized
   for the worst case (uncompressed) badge. */
.holding.has-badges {
  padding-top: calc(8px * var(--table-scale));
  padding-right: calc(7px * var(--table-scale));
}

.hcp {
  margin-top: calc(8px * var(--table-scale));
  text-align: center;
  font-size: calc(12px * var(--table-scale));
  color: #666;
}

.holding.compact .suit-row {
  font-size: calc(21px * var(--table-scale) * var(--suit-scale, 1));
  gap: calc(6px * var(--table-scale));
}
.holding.compact .suit-symbol {
  font-size: calc(24px * var(--table-scale));
  width: calc(24px * var(--table-scale));
}

/* Hidden natural-width probe — off-flow, unpainted, never affects layout. */
.hd-probe {
  position: absolute;
  left: -9999px;
  top: 0;
  visibility: hidden;
  pointer-events: none;
  white-space: nowrap;
}
</style>
