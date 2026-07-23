// Pure functions implementing bridge cardplay rules.
// No Vue, no network, no module-level state — easy to unit-test.

const SUITS = ['S', 'H', 'D', 'C']
const RANK_VALUE = {
  'A': 14, 'K': 13, 'Q': 12, 'J': 11, 'T': 10,
  '9': 9, '8': 8, '7': 7, '6': 6, '5': 5, '4': 4, '3': 3, '2': 2,
}

// `hand` shape used throughout the codebase:
//   { spades: [...], hearts: [...], diamonds: [...], clubs: [...] }
// We convert to/from a flat [{suit, rank}] view internally because the rules
// logic doesn't care about suit-grouping.

const SUIT_KEY = { S: 'spades', H: 'hearts', D: 'diamonds', C: 'clubs' }

export function handToCards(hand) {
  const out = []
  if (!hand) return out
  for (const s of SUITS) {
    for (const r of hand[SUIT_KEY[s]] || []) out.push({ suit: s, rank: r })
  }
  return out
}

// "Trump strain" from a contract string like "4S", "3NT", "1NX", "2HXX".
// Returns 'S'|'H'|'D'|'C' or null for NT.
export function trumpFromContract(contract) {
  if (!contract || contract === 'Pass') return null
  const m = contract.match(/^\d([CDHSN])T?(X{0,2})$/)
  if (!m) throw new Error(`trumpFromContract: bad contract "${contract}"`)
  return m[1] === 'N' ? null : m[1]
}

// Legal cards a seat can play, given the seat's *remaining* cards and the
// current trick's plays so far.
//   - Empty trick (leading): every remaining card is legal.
//   - Trick in progress: must follow lead suit if any remains; else free.
export function getLegalCards(remaining, currentTrickPlays = []) {
  if (!Array.isArray(remaining)) throw new Error('getLegalCards: remaining must be an array')
  if (currentTrickPlays.length === 0) return remaining.slice()
  const leadSuit = currentTrickPlays[0].suit
  const ofSuit = remaining.filter(c => c.suit === leadSuit)
  return ofSuit.length > 0 ? ofSuit : remaining.slice()
}

// True if `card` is a legal play given the seat's remaining cards and trick.
export function isLegalPlay(card, remaining, currentTrickPlays = []) {
  const legals = getLegalCards(remaining, currentTrickPlays)
  return legals.some(c => c.suit === card.suit && c.rank === card.rank)
}

// Winner of a completed trick (4 plays). Returns the seat that won.
// `trump` is the suit letter or null for NT.
// `plays` shape: [{seat, suit, rank}], in chronological order. plays[0] led.
export function trickWinner(plays, trump) {
  if (!Array.isArray(plays) || plays.length !== 4) {
    throw new Error('trickWinner: plays must be a 4-element array')
  }
  const leadSuit = plays[0].suit
  let winnerIdx = 0
  for (let i = 1; i < 4; i++) {
    if (beats(plays[i], plays[winnerIdx], leadSuit, trump)) {
      winnerIdx = i
    }
  }
  return plays[winnerIdx].seat
}

// True if `a` beats `b` in the same trick. Trump beats non-trump; otherwise
// higher rank in the lead suit wins; off-suit non-trump can never win.
export function beats(a, b, leadSuit, trump) {
  const aTrump = trump && a.suit === trump
  const bTrump = trump && b.suit === trump
  if (aTrump && !bTrump) return true
  if (!aTrump && bTrump) return false
  if (aTrump && bTrump) return RANK_VALUE[a.rank] > RANK_VALUE[b.rank]
  // Neither is trump. Lead suit wins over off-suit.
  if (a.suit === leadSuit && b.suit !== leadSuit) return true
  if (a.suit !== leadSuit && b.suit === leadSuit) return false
  if (a.suit === leadSuit && b.suit === leadSuit) {
    return RANK_VALUE[a.rank] > RANK_VALUE[b.rank]
  }
  // Both off-suit, non-trump: neither can win; keep existing winner.
  return false
}

// Subtract `played` plays from `originalHands` to get remaining cards per seat.
// `originalHands` shape: { N: hand, E: hand, S: hand, W: hand }
// `played` shape: [{seat, suit, rank}, ...]
// Returns: { N: [{suit,rank},...], E: [...], S: [...], W: [...] } as flat arrays.
export function computeRemaining(originalHands, played) {
  const out = { N: [], E: [], S: [], W: [] }
  for (const seat of 'NESW') {
    out[seat] = handToCards(originalHands[seat])
  }
  for (const p of played) {
    const seatRemaining = out[p.seat]
    const idx = seatRemaining.findIndex(c => c.suit === p.suit && c.rank === p.rank)
    if (idx === -1) {
      throw new Error(`computeRemaining: ${p.seat} cannot have played ${p.suit}${p.rank}`)
    }
    seatRemaining.splice(idx, 1)
  }
  return out
}

// The seat to play next, given the current trick state and the trump suit.
// `state` shape:
//   { currentTrick: { leader, plays: [...] }, completedTricks: [...] }
// If the current trick is in progress, returns next-around-the-table seat.
// If the current trick is complete (4 plays), returns the winner of that
// trick (who will lead the next). If no trick is in progress yet, returns
// the leader of the next trick (from the last completed trick winner, or
// the configured opening leader if none completed).
const SEAT_ORDER = ['N', 'E', 'S', 'W']
export function nextSeatToPlay(state, trump, openingLeader) {
  const ct = state.currentTrick
  if (ct && ct.plays.length > 0 && ct.plays.length < 4) {
    const lastIdx = SEAT_ORDER.indexOf(ct.plays[ct.plays.length - 1].seat)
    return SEAT_ORDER[(lastIdx + 1) % 4]
  }
  if (ct && ct.plays.length === 4) {
    return trickWinner(ct.plays, trump)
  }
  // Trick not started.
  const completed = state.completedTricks || []
  if (completed.length === 0) return openingLeader
  const last = completed[completed.length - 1]
  return last.winner
}
