// Single source of truth for AuctionTable's footprint at --table-scale: 1.0 (px).
// AuctionTable reads `minWidthPx` via a CSS var on its root, and the grid arranger
// imports `auctionReservePx()` to provision the auction region's scale — so the
// render and the provisioning share the numbers and can't drift (grid-arranger-
// spec Reconciliation 4, same pattern as handMetrics). Fixes the stale NE reserve
// that let the auction overflow its track at computed 1.0×.
export const AUCTION_UNIT = {
  // Four-column min-width at the component-standard 18px bid font (fix 1a). Down
  // from the old 308 (sized for the removed 26px enlargement) — the coupled fix:
  // a too-large reserve made the center-bidding auction shrink instead of grow
  // and over-shrank the NE reference. 220 lets the center grow toward its cap and
  // keeps NE ≈ 1.0 and contained.
  minWidthPx: 220,
  columns: 4,
  // Vertical footprint (px, 1.0×), measured from the gallery: the W/N/E/S header
  // band and one call-round row. Used by the arranger to reserve a BOUNDED growth
  // band above a bottom-anchored bidding auction (grid-arranger-spec §1) — the
  // auction grows upward into this reserve without moving the hand/BB.
  headerRowPx: 34,
  roundRowPx: 42,
}

// Natural width (px, 1.0×) the auction needs — its four-column grid min-width.
export function auctionReservePx(u = AUCTION_UNIT) {
  return u.minWidthPx
}

// Growth-reserve HEIGHT (px, 1.0×) for a bottom-anchored bidding auction: enough
// vertical room for a realistic `rounds`-round auction (default 6 — real lesson
// auctions rarely exceed it). This is the stage's reserved height; the auction
// bottom-anchors within it and grows upward into the reserve, so the hand/BB hold
// position through any normal auction and only displace on a freak one. Bounded by
// design — NOT the viewport (the grid never reads viewport dimensions; the shell
// owns placement).
export function auctionGrowthReservePx(rounds = 6, u = AUCTION_UNIT) {
  return u.headerRowPx + rounds * u.roundRowPx
}
