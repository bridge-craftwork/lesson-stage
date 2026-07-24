<template>
  <div
    ref="root"
    class="auction-table"
    :class="{ dense, 'no-grid': !grid, 'two-column': twoColumn, condensed: !touch }"
    :style="{ '--at-min-w': AUCTION_UNIT.minWidthPx + 'px' }"
  >
    <!-- LESSON-STUDIO DELTA (pending upstream): two-column uncontested form.
         Review-mode decorations (turn indicator, wrong/correct, divergence)
         are deliberately absent — this is a lesson/print layout. -->
    <template v-if="twoColumn">
      <div class="header two-col">
        <div v-for="(label, i) in twoColumnHeaders" :key="i" class="header-cell">{{ label }}</div>
      </div>
      <div class="rounds">
        <div v-for="(round, roundIdx) in twoColumnRounds" :key="roundIdx" class="round two-col">
          <div v-for="(cell, colIdx) in round" :key="colIdx" class="bid-cell">
            <span v-if="cell" class="bid-with-note"><span v-html="formatBidHtml(cell.bid)"></span><sup
              v-if="alertFor(cell.idx) || noteFor(cell.idx) != null"
              class="bid-note"
            ><span v-if="alertFor(cell.idx)" class="bid-alert">!</span>{{ noteFor(cell.idx) }}</sup></span>
          </div>
        </div>
      </div>
    </template>
    <template v-else>
    <div class="header">
      <div class="header-cell">W</div>
      <div class="header-cell">N</div>
      <div class="header-cell">E</div>
      <div class="header-cell">S</div>
    </div>
    <div class="rounds">
      <div v-for="(round, roundIdx) in rounds" :key="roundIdx" class="round">
        <div
          v-for="(bid, bidIdx) in round"
          :key="bidIdx"
          class="bid-cell"
          :class="{
            'current-turn': isCurrentTurn(roundIdx, bidIdx),
            'wrong-bid': isWrongBid(roundIdx, bidIdx),
            'correct-bid': isCorrectBid(roundIdx, bidIdx),
            'stacked': bid && divergedBids[getBidIndexFromPosition(roundIdx, bidIdx)],
          }"
          @mouseenter="bid ? hoveredIdx = getBidIndexFromPosition(roundIdx, bidIdx) : null"
          @mouseleave="hoveredIdx = null"
        >
          <template v-if="bid && divergedBids[getBidIndexFromPosition(roundIdx, bidIdx)]">
            <div
              v-for="kind in ['user', 'bba']"
              :key="kind"
              class="stacked-row"
              :class="{
                rejected: divergedBids[getBidIndexFromPosition(roundIdx, bidIdx)][kind] !== bid,
                clickable: allowDivergenceToggle,
              }"
              @click.stop="allowDivergenceToggle && $emit('toggle-bid', getBidIndexFromPosition(roundIdx, bidIdx))"
            >
              <span class="stacked-head">
                <span class="stacked-marker">{{ divergedBids[getBidIndexFromPosition(roundIdx, bidIdx)][kind] === bid ? '●' : '○' }}</span>
                <span class="stacked-label">{{ kind === 'user' ? 'You' : 'BBA' }}</span>
              </span>
              <span class="stacked-bid" v-html="formatBidHtml(divergedBids[getBidIndexFromPosition(roundIdx, bidIdx)][kind])"></span>
            </div>
          </template>
          <span v-else-if="bid" class="bid-with-note"><span v-html="formatBidHtml(bid)"></span><sup
            v-if="alertFor(getBidIndexFromPosition(roundIdx, bidIdx)) || noteFor(getBidIndexFromPosition(roundIdx, bidIdx)) != null"
            class="bid-note"
          ><span v-if="alertFor(getBidIndexFromPosition(roundIdx, bidIdx))" class="bid-alert">!</span>{{ noteFor(getBidIndexFromPosition(roundIdx, bidIdx)) }}</sup></span>
          <span v-else-if="showTurnIndicator && isCurrentTurn(roundIdx, bidIdx)" class="turn-indicator">?</span>
          <div
            v-if="bid && hoveredIdx === getBidIndexFromPosition(roundIdx, bidIdx) && tooltipFor(getBidIndexFromPosition(roundIdx, bidIdx))"
            class="bid-tooltip"
            v-html="tooltipFor(getBidIndexFromPosition(roundIdx, bidIdx))"
          ></div>
        </div>
      </div>
    </div>
    </template>
  </div>
</template>

<script setup>
import { computed, ref, onMounted, onBeforeUnmount } from 'vue'
import { formatBid } from '../utils/cardFormatting.js'
import { getSeatOrder } from '../utils/seatOrder.js'
import { AUCTION_UNIT } from './auctionMetrics.js'

const hoveredIdx = ref(null)

// Density sensor: the auction reserves big, senior-legible bids at the rail
// width it actually ships at, but in a narrow console tile the full-size grid
// overflows and clips. Below ~280px, drop the min-width and shrink the bids so
// all four columns fit. ResizeObserver, never container-type (inline-size
// containment breaks shrink-wrap hosts — see #88). Starts wide so there's no
// shrink-flash before the observer measures.
const root = ref(null)
const tableWidth = ref(9999)
// Effective --table-scale — the dense threshold (and min-width floor) scale
// with it, so at 1.5× a 320px container is correctly "narrow" and goes dense
// instead of letting the scaled 462px grid overflow and clip. Read once on
// mount (scale is static per render); default 1 keeps the 1.0 case identical.
const uiScale = ref(1)
let ro = null
onMounted(() => {
  if (root.value) {
    const s = parseFloat(getComputedStyle(root.value).getPropertyValue('--table-scale'))
    if (s > 0) uiScale.value = s
  }
  // Observe the CONTAINER's available width, not our own: in a shrink-wrap
  // parent (e.g. A1's centered practice column) measuring our own width feeds
  // back — we'd shrink, read small, flip to dense, and collapse further (the
  // regression that compressed A1's pre-bid auction). The container width is
  // the honest "is this a console tile" signal.
  const el = root.value?.parentElement || root.value
  if (typeof ResizeObserver === 'undefined' || !el) return
  ro = new ResizeObserver((entries) => { tableWidth.value = entries[0].contentRect.width })
  ro.observe(el)
})
onBeforeUnmount(() => ro?.disconnect())
// LESSON-STUDIO DELTA (pending upstream): the two-column form is never dense.
// Dense answers "four columns won't fit a console tile"; the two-column layout
// is a lesson/print form that is *legitimately* half-width, and it excludes the
// review decorations a console tile is for. Left alone it would false-positive
// — its narrower footprint reads as a cramped container and shrinks the bids.
const dense = computed(() => !twoColumn.value && tableWidth.value < 280 * uiScale.value)

// Render BBOalert suit codes (!C !D !H !S) as colored unicode symbols.
function formatMeaningHtml(text) {
  const escaped = text.replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ))
  return escaped
    .replace(/!C/gi, '<span class="t-suit-c">&clubs;</span>')
    .replace(/!D/gi, '<span class="t-suit-d">&diams;</span>')
    .replace(/!H/gi, '<span class="t-suit-h">&hearts;</span>')
    .replace(/!S/gi, '<span class="t-suit-s">&spades;</span>')
}

// Useless meanings to skip: empty, natural/pass/double/redouble, or repeating the bid.
function isMeaningfulText(text, bid) {
  if (!text) return false
  const t = text.trim()
  if (!t) return false
  const lower = t.toLowerCase()
  if (lower === 'natural' || lower === 'pass' || lower === 'double' || lower === 'redouble') return false
  if (t === bid) return false
  return true
}

const props = defineProps({
  bids: {
    type: Array,
    default: () => []
  },
  dealer: {
    type: String,
    default: 'N'
  },
  currentBidIndex: {
    type: Number,
    default: -1
  },
  wrongBidIndex: {
    type: Number,
    default: -1
  },
  wrongBidIndices: {
    // Optional alternative to wrongBidIndex that highlights multiple wrong bids.
    type: Array,
    default: () => []
  },
  correctBidIndex: {
    type: Number,
    default: -1
  },
  showTurnIndicator: {
    type: Boolean,
    default: false
  },
  meanings: {
    // Optional [{position, bid, meaning, isAlert}, ...]; enables per-cell hover tooltip.
    type: Array,
    default: () => []
  },
  divergedBids: {
    // Optional map: { idx: { user: 'X', bba: 'Y' } } — when present, renders both
    // bids stacked in the cell with the rejected one struck-through.
    type: Object,
    default: () => ({})
  },
  allowDivergenceToggle: {
    // When true, clicking a stacked bid emits `toggle-bid` so the parent can
    // swap which is live. Off by default — toggling is only safe in review.
    type: Boolean,
    default: false
  },
  // LESSON-STUDIO DELTA (pending upstream): print/teaching display options.
  columns: {
    // 4 (default, the student-app grid) or 2 — the two-column uncontested form
    // used by teaching material. Falls back to 4 when the auction is
    // competitive, so passing 2 is always safe.
    type: Number,
    default: 4
  },
  labels: {
    // [left, right] header labels for the two-column form. Defaults to the
    // compass letters of the two seats shown.
    type: Array,
    default: null
  },
  grid: {
    // false drops the gridlines and dark header bar for an unruled table.
    type: Boolean,
    default: true
  },
  touch: {
    // Row sizing. true (default) keeps the generous rows the student and
    // teacher apps need as touch targets. false condenses them for reading
    // rather than tapping — printed and on-screen lesson material, at any
    // column count. Orthogonal to `columns`: a four-column auction in a lesson
    // wants condensed rows just as much as a two-column one.
    type: Boolean,
    default: true
  }
})

defineEmits(['toggle-bid'])

const seatOrder = computed(() => getSeatOrder(props.dealer))

// Figure out which column the dealer is in (0-3 for W-N-E-S display order)
const dealerColumn = computed(() => {
  const displayOrder = ['W', 'N', 'E', 'S']
  return displayOrder.indexOf(props.dealer)
})

const rounds = computed(() => {
  const result = []
  const bids = props.bids

  // First round might not have all 4 bids if dealer isn't West
  let bidIdx = 0
  let roundNum = 0

  while (bidIdx < bids.length || (roundNum === 0 && bids.length > 0)) {
    const round = [null, null, null, null]

    // Determine starting column for this round
    const startCol = roundNum === 0 ? dealerColumn.value : 0

    for (let col = startCol; col < 4 && bidIdx < bids.length; col++) {
      round[col] = bids[bidIdx]
      bidIdx++
    }

    // Only add round if it has any bids
    if (round.some(b => b !== null)) {
      result.push(round)
    }

    roundNum++

    // Safety break
    if (roundNum > 20) break
  }

  // Add an empty round for current turn indicator if needed
  if (props.currentBidIndex >= bids.length) {
    const lastRound = result[result.length - 1]
    const filledCount = lastRound ? lastRound.filter(b => b !== null).length : 0
    const startCol = result.length === 1 ? dealerColumn.value : 0
    const expectedNextCol = (startCol + filledCount) % 4

    if (filledCount === 4 || (result.length > 1 && filledCount === 4)) {
      // Need a new round
      const newRound = [null, null, null, null]
      result.push(newRound)
    }
  }

  return result
})

// ---------------------------------------------------------------------------
// LESSON-STUDIO DELTA (pending upstream): two-column uncontested layout.
// Print/teaching material shows only the bidding pair's columns and drops the
// opponents' passes, which carry no information. Everything here is derived
// from `bids` + `dealer` — the source stays a flat call list either way.
// ---------------------------------------------------------------------------
const PARTNER = { N: 'S', S: 'N', E: 'W', W: 'E' }
const isPassLike = (bid) => bid === 'P' || bid === 'Pass' || bid === 'AP'

/** The seat that made each call, by position in `bids`. */
const seatOfBid = computed(() => props.bids.map((_, i) => seatOrder.value[i % 4]))

/**
 * The partnership making every non-pass call, as [opener, partner] — or null
 * when the auction is competitive (both pairs bid) or nobody bid at all. Null
 * is the signal to fall back to the four-column grid.
 */
const activePair = computed(() => {
  const seats = seatOfBid.value
  const bidding = props.bids
    .map((bid, i) => i)
    .filter((i) => !isPassLike(props.bids[i]))
  if (!bidding.length) return null
  const opener = seats[bidding[0]]
  const pair = [opener, PARTNER[opener]]
  if (bidding.some((i) => !pair.includes(seats[i]))) return null
  return pair
})

const twoColumn = computed(() => props.columns === 2 && activePair.value !== null)

const twoColumnHeaders = computed(() =>
  props.labels && props.labels.length === 2 ? props.labels : (activePair.value || [])
)

/**
 * Rows of [leftCell, rightCell], each cell `{ bid, idx }` or null. Keeps the
 * active pair's own passes (a passed hand is information) but drops the other
 * pair's calls and any trailing run of passes, whose omission is the whole
 * point of the form.
 */
const twoColumnRounds = computed(() => {
  const pair = activePair.value
  if (!pair) return []
  const seats = seatOfBid.value

  let end = props.bids.length
  while (end > 0 && isPassLike(props.bids[end - 1])) end--

  const rows = []
  let row = [null, null]
  let lastCol = null
  for (let i = 0; i < end; i++) {
    const col = pair.indexOf(seats[i])
    if (col === -1) continue
    // A column that doesn't advance means the round wrapped — start a new row.
    // This also places a passed hand's opening pass correctly, in the right
    // column of its own row with the left cell empty.
    if (lastCol !== null && col <= lastCol) {
      rows.push(row)
      row = [null, null]
    }
    row[col] = { bid: props.bids[i], idx: i }
    lastCol = col
  }
  if (row.some((c) => c !== null)) rows.push(row)
  return rows
})

function alertFor(bidIdx) {
  const m = props.meanings?.find(x => x.position === bidIdx)
  return !!(m && m.isAlert)
}

function getBidIndexFromPosition(roundIdx, colIdx) {
  if (roundIdx === 0) {
    return colIdx - dealerColumn.value
  }
  // First round has (4 - dealerColumn) bids
  const firstRoundBids = 4 - dealerColumn.value
  return firstRoundBids + (roundIdx - 1) * 4 + colIdx
}

function isCurrentTurn(roundIdx, colIdx) {
  const bidIdx = getBidIndexFromPosition(roundIdx, colIdx)
  return bidIdx === props.currentBidIndex && bidIdx >= props.bids.length
}

function isWrongBid(roundIdx, colIdx) {
  const bidIdx = getBidIndexFromPosition(roundIdx, colIdx)
  if (props.wrongBidIndices && props.wrongBidIndices.includes(bidIdx)) return true
  if (props.wrongBidIndex < 0) return false
  return bidIdx === props.wrongBidIndex
}

function isCorrectBid(roundIdx, colIdx) {
  if (props.correctBidIndex < 0) return false
  const bidIdx = getBidIndexFromPosition(roundIdx, colIdx)
  return bidIdx === props.correctBidIndex
}

function formatBidHtml(bid) {
  const { html } = formatBid(bid)
  // Pass is a low-information call and doesn't need to be read like a contract
  // bid — render it a touch smaller/quieter so the real bids dominate and it
  // stops crowding the cell (it's otherwise nearly as wide as "3♣").
  if (html === 'Pass') return '<span class="bid-pass">Pass</span>'
  return html
}

// LESSON-STUDIO DELTA (pending upstream): a `meanings` entry may carry a `note`
// number, rendered as a superscript marker on the bid so printed lessons can
// key their numbered footnotes to specific calls (hover tooltips don't print).
function noteFor(bidIdx) {
  const m = props.meanings?.find(x => x.position === bidIdx)
  return m && m.note != null ? m.note : null
}

// Returns HTML-ready tooltip content, or '' to suppress the tooltip entirely.
// Prefers the longer `meaningExtended` (richer context: point ranges, suit
// lengths, etc.) when BBA returns it; falls back to the short `meaning`.
function tooltipFor(bidIdx) {
  if (!props.meanings || !props.meanings.length) return ''
  const m = props.meanings.find(x => x.position === bidIdx)
  if (!m) return ''
  const raw = m.meaningExtended || m.meaning
  if (!raw) return ''
  const text = raw.trim()
  const bid = props.bids[bidIdx]
  if (!isMeaningfulText(text, bid)) return ''
  return formatMeaningHtml(text)
}
</script>

<style scoped>
.auction-table {
  background: #fff;
  border: 2px solid #333;
  border-radius: 4px;
  overflow: hidden;
  /* Floor matches the BiddingBox's natural width (7×36 level buttons + gaps +
     padding = 308px) so a shrink-wrapped auction lines up with the bidding box
     below it and stays stable from empty through a full auction, instead of
     tracking bid content. `dense` (console tiles) drops this to 0. */
  min-width: calc(var(--at-min-w, 308px) * var(--table-scale));
}

/* Console-tile density (< 280px): drop the min-width floor so all four columns
   fit the tile, and shrink the bids to match. The rail width it ships at stays
   full-size big bids. */
.auction-table.dense { min-width: 0; }
.auction-table.dense .bid-cell {
  font-size: calc(15px * var(--table-scale));
  padding: calc(6px * var(--table-scale)) calc(3px * var(--table-scale));
  min-height: calc(32px * var(--table-scale));
}
.auction-table.dense .bid-cell :deep(.red),
.auction-table.dense .bid-cell :deep(.black) { font-size: 1.1em; }
.auction-table.dense .turn-indicator { font-size: calc(15px * var(--table-scale)); }
.auction-table.dense .header-cell { font-size: calc(11px * var(--table-scale)); padding: calc(5px * var(--table-scale)) calc(3px * var(--table-scale)); }
.auction-table.dense .bid-cell.stacked { font-size: calc(11px * var(--table-scale)); }

/* Header and every round share ONE set of four rigid column tracks. Because the
   tracks are defined on the grid container (not inferred from each row's
   content), a wide cell — e.g. a stacked "you vs BBA" bid — can never widen its
   column and skew the row. `minmax(0, 1fr)` (paired with min-width:0 on the
   cells) lets an over-wide cell shrink back into its quarter instead of pushing
   the others out. Divergence then costs HEIGHT (a taller cell), never width. */
.header {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  background: #333;
  color: white;
}

.header-cell {
  min-width: 0;
  text-align: center;
  padding: calc(8px * var(--table-scale)) calc(4px * var(--table-scale));
  font-weight: bold;
  font-size: calc(14px * var(--table-scale));
}

.rounds {
  display: flex;
  flex-direction: column;
}

.round {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  border-bottom: 1px solid #ddd;
}

.round:last-child {
  border-bottom: none;
}

.bid-cell {
  min-width: 0;
  text-align: center;
  padding: calc(10px * var(--table-scale)) calc(6px * var(--table-scale));
  /* Component-standard size, scaled by --table-scale so the arranger's clamp is
     the ONLY size authority (grid-arranger fix 1a). The former hardcoded 26px
     enlargement is removed — prominence is now the center region's generous cap
     under the grid; in the legacy bands layout the auction returns to standard
     size (a named a1-visible change). The rare 4-row diverged cell still
     overrides down to compact (.bid-cell.stacked). */
  font-size: calc(18px * var(--table-scale));
  font-weight: 500;
  min-height: calc(36px * var(--table-scale));
  display: flex;
  align-items: center;
  justify-content: center;
  border-right: 1px solid #eee;
  position: relative;
}

.bid-tooltip {
  position: absolute;
  bottom: calc(100% + 4px);
  left: 50%;
  transform: translateX(-50%);
  background: #fffbe6;
  color: #222;
  padding: calc(6px * var(--table-scale)) calc(10px * var(--table-scale));
  border: 1px solid #d4c97a;
  border-radius: 4px;
  font-size: calc(13px * var(--table-scale));
  line-height: 1.45;
  white-space: pre-line;
  pointer-events: none;
  z-index: 20;
  min-width: calc(90px * var(--table-scale));
  max-width: calc(240px * var(--table-scale));
  box-shadow: 0 2px 8px rgba(0,0,0,0.18);
}

.bid-tooltip::after {
  content: '';
  position: absolute;
  top: 100%;
  left: 50%;
  transform: translateX(-50%);
  border: 5px solid transparent;
  border-top-color: #d4c97a;
}

.bid-tooltip :deep(.t-suit-c),
.bid-tooltip :deep(.t-suit-s) { color: #1a1a1a; }
.bid-tooltip :deep(.t-suit-d),
.bid-tooltip :deep(.t-suit-h) { color: #d32f2f; }

.bid-cell:last-child {
  border-right: none;
}

.bid-cell :deep(.red) {
  color: #d32f2f;
}

.bid-cell :deep(.black) {
  color: #1a1a1a;
}

/* LESSON-STUDIO DELTA (pending upstream): footnote marker on an annotated bid. */
.bid-with-note {
  display: inline-flex;
  align-items: flex-start;
}
.bid-note {
  font-size: 0.6em;
  line-height: 1;
  margin-left: 0.1em;
  color: #555;
  font-weight: 600;
}

.bid-cell :deep(.bid-pass) {
  font-size: 0.72em;
  font-weight: 500;
  color: #555;
}

/* Suit symbol a touch larger than the level digit: at a bigger size the club vs
   spade shapes read apart, which is exactly what seniors confuse. */
.bid-cell :deep(.red),
.bid-cell :deep(.black) {
  font-size: 1.2em;
  line-height: 1;
}

.bid-cell :deep(.double) {
  color: #ff5722;
  font-weight: bold;
}

.bid-cell :deep(.redouble) {
  color: #2196f3;
  font-weight: bold;
}

.turn-indicator {
  color: #007bff;
  font-weight: bold;
  font-size: calc(26px * var(--table-scale));
  animation: pulse 1s ease-in-out infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.current-turn {
  background: #e3f2fd;
}

/* Stacked-bid display when both user's and BBA's bids are shown together. Each
   side is a two-line stack — a "○ BBA" head over the bid — so a diverged cell's
   horizontal footprint is only as wide as the bid itself (fits a quarter-track
   even at narrow widths); the cost of divergence is HEIGHT, not width. */
.bid-cell.stacked {
  flex-direction: column;
  padding: calc(4px * var(--table-scale)) calc(4px * var(--table-scale));
  font-size: calc(14px * var(--table-scale));
  gap: calc(3px * var(--table-scale));
}

.stacked-row {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0;
  width: 100%;
  line-height: 1.15;
}

.stacked-head {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: calc(3px * var(--table-scale));
}

.stacked-row.clickable {
  cursor: pointer;
  border-radius: 3px;
  padding: calc(1px * var(--table-scale)) calc(4px * var(--table-scale));
}

.stacked-row.clickable:hover {
  background: rgba(0, 0, 0, 0.05);
}

.stacked-row.rejected .stacked-bid {
  text-decoration: line-through;
  text-decoration-color: #b00;
  text-decoration-thickness: 2px;
  opacity: 0.6;
}

.stacked-marker {
  font-size: calc(10px * var(--table-scale));
  color: #1D9E75;
  width: calc(10px * var(--table-scale));
  display: inline-block;
}

.stacked-row.rejected .stacked-marker {
  color: #888;
}

.stacked-label {
  font-size: calc(10px * var(--table-scale));
  color: #666;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.wrong-bid {
  background: #ffcdd2;
  box-shadow: inset 0 0 0 2px #ef5350;
}

.correct-bid {
  background: #c8e6c9;
}

/* LESSON-STUDIO DELTA (pending upstream): two-column form and unruled variant. */

/* Two columns of tracks instead of four. The min-width floor exists to align a
   four-column auction with the BiddingBox below it; with half the columns it
   halves too, so a two-column auction stays narrow enough to sit beside prose
   in a print column. */
.header.two-col,
.round.two-col {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}
/* Two columns of bids stretched across a full print column put the pair far
   apart and hard to read as one auction. Shrink-wrap to the content and centre
   instead. Safe here where it isn't at four columns: the min-width floor exists
   to align with the BiddingBox, which this layout never sits above, and the
   two-column form is exempt from the density sensor that a narrow table would
   otherwise trip. */
.auction-table.two-column {
  min-width: 0;
  width: fit-content;
  margin-inline: auto;
}
.auction-table.two-column .header.two-col,
.auction-table.two-column .round.two-col {
  grid-template-columns: repeat(2, minmax(0, auto));
}
.auction-table.two-column .bid-cell,
.auction-table.two-column .header-cell {
  min-width: calc(56px * var(--table-scale));
  padding-inline: calc(10px * var(--table-scale));
}

/* Vertical air, driven by `touch` rather than by the column count. The default
   rows are touch targets — 10px of padding plus a 36px floor, landing a row at
   ~2.5x the type size. Reading material wants ~1.5x, which is where printed
   auction tables (BridgeBum, the ACBL Bulletin) sit, so `touch: false` trims
   the padding, drops the target floor and tightens the line-height the host
   document supplies. Applies at any column count: a four-column auction in a
   lesson is just as much reading material as a two-column one. */
.auction-table.condensed .bid-cell {
  padding-block: calc(2px * var(--table-scale));
  min-height: 0;
  line-height: 1.15;
}
.auction-table.condensed .header-cell {
  padding-block: calc(2px * var(--table-scale));
  line-height: 1.15;
}

/* Unruled: the convention in printed teaching material is a bare table — no
   gridlines, no dark header bar, just the calls under their headings. */
.auction-table.no-grid {
  border: none;
  border-radius: 0;
  background: transparent;
}
.auction-table.no-grid .header {
  background: transparent;
  color: inherit;
}
/* No rule under the headers either: a full-width underline reads as a single
   spanning header and re-links the two columns the layout just separated. The
   labels are bold and the calls are not, which is enough to tell them apart. */
.auction-table.no-grid .round {
  border-bottom: none;
}
.auction-table.no-grid .bid-cell {
  border-right: none;
}

/* The alert marker rides in the same superscript slot as the footnote number,
   ahead of it when a call carries both (`2♦!¹`). */
.bid-alert {
  font-weight: 700;
}
</style>
