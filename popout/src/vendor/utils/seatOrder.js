// Extracted verbatim from Bridge-Classroom src/utils/pbnParser.js — the only
// symbol AuctionTable needs from that 753-line module. Kept as a tiny module so
// the vendored snapshot doesn't drag in the whole PBN parser. (The single edit
// to the snapshot: AuctionTable imports getSeatOrder from here instead.)
export function getSeatOrder(dealer) {
  const seats = ['N', 'E', 'S', 'W']
  const startIdx = seats.indexOf(dealer)
  return [...seats.slice(startIdx), ...seats.slice(0, startIdx)]
}
