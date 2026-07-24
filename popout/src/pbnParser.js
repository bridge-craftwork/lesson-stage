// Parse one PBN game record (what native posts across the seam from
// lesson-hands.pbn) into the deal shape the popout renders.
//
// Partial deals are the norm, not an error: a lesson hand is usually a single
// seat, the rest written `-`. Unspecified seats come through as null — no cards
// are ever invented. Returns null if there's no [Deal] tag to build a table
// from (a block with no deal bound to it).

const CLOCKWISE = ['N', 'E', 'S', 'W']
const SUITS = ['spades', 'hearts', 'diamonds', 'clubs']
const LEFT_OF = { N: 'E', E: 'S', S: 'W', W: 'N' }

function tag(record, name) {
  const m = record.match(new RegExp(`\\[${name}\\s+"([^"]*)"\\]`))
  return m ? m[1] : null
}

function up(s) {
  return s ? s.toUpperCase() : null
}

function toInt(s) {
  const n = parseInt(s, 10)
  return Number.isNaN(n) ? null : n
}

/** "AQ954.K73.A5.J84" → { spades:[...], hearts:[...], diamonds:[...], clubs:[...] } */
function parseHolding(text) {
  const parts = text.split('.')
  const hand = {}
  SUITS.forEach((suit, i) => {
    hand[suit] = (parts[i] || '').split('').filter((c) => c !== '')
  })
  return hand
}

/** "S:AQ954.K73.A5.J84 - - -" → { N, E, S, W } with null for unspecified seats. */
function parseDeal(dealTag) {
  if (!dealTag) return null
  const colon = dealTag.indexOf(':')
  if (colon === -1) return null
  const first = dealTag.slice(0, colon).trim().toUpperCase()
  const start = CLOCKWISE.indexOf(first)
  if (start === -1) return null

  const holdings = dealTag.slice(colon + 1).trim().split(/\s+/)
  const hands = { N: null, E: null, S: null, W: null }
  holdings.forEach((h, i) => {
    if (i > 3) return
    const seat = CLOCKWISE[(start + i) % 4]
    hands[seat] = h === '-' || h === '' ? null : parseHolding(h)
  })
  return hands
}

/** The [Auction] section as a flat list of calls, annotation refs stripped. */
function parseAuction(record) {
  const lines = record.split('\n')
  const idx = lines.findIndex((l) => /^\s*\[Auction\b/.test(l))
  if (idx === -1) return { firstToCall: null, calls: [] }

  const firstToCall = up(tag(lines[idx], 'Auction'))
  const calls = []
  for (let i = idx + 1; i < lines.length; i++) {
    const line = lines[i].trim()
    if (line === '' || line.startsWith('[')) break
    for (const token of line.split(/\s+/)) {
      if (!token) continue
      if (token === 'AP') { calls.push('P', 'P', 'P'); continue } // all pass
      if (/^=\d+=$/.test(token)) continue // annotation reference marker
      if (token === '*' || token === '-') continue
      calls.push(token)
    }
  }
  return { firstToCall, calls }
}

function normalizeContract(c) {
  if (!c || c === '?') return null
  return c.replace(/\s+/g, '').toUpperCase()
}

export function parsePBN(text) {
  if (!text) return null
  const hands = parseDeal(tag(text, 'Deal'))
  if (!hands) return null

  const declarer = up(tag(text, 'Declarer'))
  const auction = parseAuction(text)

  return {
    board: toInt(tag(text, 'Board')),
    dealer: up(tag(text, 'Dealer')) || auction.firstToCall,
    vulnerable: tag(text, 'Vulnerable'),
    contract: normalizeContract(tag(text, 'Contract')),
    declarer: declarer === '?' ? null : declarer,
    openingLeader: declarer && declarer !== '?' ? LEFT_OF[declarer] : null,
    hands,
    auction: auction.calls,
  }
}
