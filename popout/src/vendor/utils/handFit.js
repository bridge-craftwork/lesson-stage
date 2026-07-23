// Pure per-row fit / truncation math for HandDisplay, extracted so the
// play-state invariants can be unit-tested without a layout engine (jsdom has
// none). All widths are in natural (scale-1) pixels; `available` is the row's
// content zone (container minus the fixed label zone).
//
// Cascade:
//   needed ≤ available          → scale 1 (no-op)
//   floor ≤ scale < 1           → one line at the computed scale (compress)
//   scale < floor               → hold at floor, TRUNCATE the tail, +N chip
// The truncation TEST excludes the chip (only the cards decide if truncation
// is needed); the COUNT of how many cards fit INCLUDES the chip reserve —
// computing in that order avoids truncating one card too many.

export const LEGIBILITY_FLOOR = 0.65

/**
 * @param {object} o
 * @param {number[]} o.cumWidths  natural cumulative widths: cumWidths[i] = right
 *   edge of the first (i+1) cards (excludes trailing letter-spacing/overhang).
 *   Ascending; drives the fit DECISION and the truncation count.
 * @param {number} o.available    content-zone width in px.
 * @param {number} o.chipReserve  natural width the "+N" chip needs (0 if none).
 * @param {number} [o.natural]    full content width incl. the trailing letter-
 *   spacing after the last card (probe `.cards` box width). Used only to SIZE
 *   compression so the last card doesn't spill; defaults to cumWidths[last].
 * @param {number} [o.margin]     px shaved off `available` when compressing, to
 *   clear the last glyph's right overhang. NOT applied to the fit decision, so
 *   hands that already fit stay byte-identical. Default 0 (unit tests).
 * @param {number} [o.floor]      legibility floor (default LEGIBILITY_FLOOR).
 * @param {boolean} [o.allowTruncate]  may this row truncate to a +N chip?
 *   Truncation's ONLY escape hatch is the card-selector popup, which opens only
 *   on clickable rows — so a non-clickable row that truncates strands its hidden
 *   cards with no way to see them. When false, never truncate: compress the whole
 *   suit to fit even below the floor (small-but-complete beats stranded). Default
 *   true.
 * @returns {{scale:number, visible:number, hidden:number}}
 */
export function computeFit({ cumWidths, available, chipReserve = 0, natural, margin = 0, floor = LEGIBILITY_FLOOR, allowTruncate = true }) {
  const total = cumWidths.length
  const contentRight = total ? cumWidths[total - 1] : 0
  if (contentRight <= 0) return { scale: 1, visible: total, hidden: 0 }

  // Fit decision on the last card's right edge (unchanged): if the cards already
  // fit, render at 1 — no compression, no margin — preserving a1 pixel identity.
  if (contentRight <= available) return { scale: 1, visible: total, hidden: 0 }

  // Compressing: size against the FULL content width (incl. trailing space) and
  // leave the overhang margin, so the last card sits inside the frame edge.
  const naturalFull = natural != null ? natural : contentRight
  const room = Math.max(0, available - margin)
  const scaleFull = Math.min(1, room / naturalFull)
  // Chip EXCLUDED from the truncation test — only the cards decide it. And with
  // no popup to reach hidden cards (allowTruncate=false), NEVER truncate: compress
  // the whole suit to fit even below the floor rather than strand cards behind an
  // unreachable +N. This also breaks the shrink-wrap feedback loop that let a
  // non-clickable a1 hand collapse (truncate → narrower content → measure narrower
  // → truncate more).
  if (scaleFull >= floor || !allowTruncate) return { scale: scaleFull, visible: total, hidden: 0 }

  // Truncate at the floor; the COUNT includes the chip's reserved width.
  const budget = room / floor // natural units at floor scale
  let visible = 0
  for (let i = 0; i < total; i++) {
    if (cumWidths[i] + chipReserve <= budget) visible = i + 1
    else break
  }
  return { scale: floor, visible, hidden: total - visible }
}
