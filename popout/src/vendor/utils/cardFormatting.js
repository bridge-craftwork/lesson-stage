/**
 * Card and suit formatting utilities
 */

export const SUIT_SYMBOLS = {
  spades: '♠',
  hearts: '♥',
  diamonds: '♦',
  clubs: '♣',
  S: '♠',
  H: '♥',
  D: '♦',
  C: '♣'
}

export const SUIT_COLORS = {
  spades: 'black',
  hearts: 'red',
  diamonds: 'red',
  clubs: 'black'
}

export const SUIT_ORDER = ['spades', 'hearts', 'diamonds', 'clubs']

// Bridge display order for ranks within a suit: high to low.
export const RANK_ORDER = ['A', 'K', 'Q', 'J', 'T', '9', '8', '7', '6', '5', '4', '3', '2']

/**
 * Sort a suit's cards into bridge display order (A→2), tolerant of source order.
 * Some deal sources (e.g. BBO save/replay via ?pbn=) send suits low-to-high, so
 * the display layer normalizes rather than trusting the source to pre-order.
 * Accepts 'T' or '10' for the ten; unknown ranks sort to the end.
 * @param {string[]} cards e.g. ['4','8','J','A'] → ['A','J','8','4']
 * @returns {string[]} a new, sorted array
 */
export function sortSuitDescending(cards) {
  const rankIndex = (c) => {
    const r = String(c).toUpperCase() === '10' ? 'T' : String(c).toUpperCase()
    const i = RANK_ORDER.indexOf(r)
    return i === -1 ? RANK_ORDER.length : i
  }
  return [...(cards || [])].sort((a, b) => rankIndex(a) - rankIndex(b))
}

/**
 * Convert card character to display value
 * @param {string} card Single character (A, K, Q, J, T, 9-2)
 * @returns {string} Display value
 */
export function formatCard(card) {
  if (card === 'T') return '10'
  return card
}

/**
 * Format a bid for display with proper suit symbols
 * @param {string} bid e.g., "1S", "2NT", "Pass", "X"
 * @returns {Object} { text, html } formatted bid
 */
export function formatBid(bid) {
  if (!bid) return { text: '', html: '' }

  const upper = bid.toUpperCase()

  if (upper === 'PASS' || upper === 'P') {
    return { text: 'Pass', html: 'Pass' }
  }
  if (upper === 'X') {
    return { text: 'X', html: '<span class="double">X</span>' }
  }
  if (upper === 'XX') {
    return { text: 'XX', html: '<span class="redouble">XX</span>' }
  }

  // Level + suit/NT bids
  const match = bid.match(/^(\d)(C|D|H|S|NT?)$/i)
  if (match) {
    const level = match[1]
    const strain = match[2].toUpperCase()

    if (strain === 'NT' || strain === 'N') {
      return { text: `${level}NT`, html: `${level}NT` }
    }

    const symbol = SUIT_SYMBOLS[strain]
    const colorClass = strain === 'H' || strain === 'D' ? 'red' : 'black'

    return {
      text: `${level}${symbol}`,
      html: `${level}<span class="${colorClass}">${symbol}</span>`
    }
  }

  return { text: bid, html: bid }
}

/**
 * Get CSS class for a suit
 * @param {string} suit
 * @returns {string} CSS class name
 */
export function getSuitClass(suit) {
  const color = SUIT_COLORS[suit.toLowerCase()] || SUIT_COLORS[suit]
  return color === 'red' ? 'suit-red' : 'suit-black'
}

/**
 * Format vulnerability for display
 * @param {string} vul None, NS, EW, Both, All
 * @returns {string} Formatted vulnerability
 */
export function formatVulnerability(vul) {
  if (!vul) return 'None'
  const upper = vul.toUpperCase()
  if (upper === 'NONE' || upper === '-' || upper === 'LOVE') return 'None'
  if (upper === 'NS' || upper === 'N-S') return 'N-S Vul'
  if (upper === 'EW' || upper === 'E-W') return 'E-W Vul'
  if (upper === 'BOTH' || upper === 'ALL') return 'Both Vul'
  return vul
}

/**
 * Check if a seat is vulnerable
 * @param {string} seat N/E/S/W
 * @param {string} vul Vulnerability string
 * @returns {boolean}
 */
export function isVulnerable(seat, vul) {
  if (!vul) return false
  const upper = vul.toUpperCase()
  if (upper === 'BOTH' || upper === 'ALL') return true
  if (upper === 'NONE' || upper === '-' || upper === 'LOVE') return false
  if (upper === 'NS' || upper === 'N-S') return seat === 'N' || seat === 'S'
  if (upper === 'EW' || upper === 'E-W') return seat === 'E' || seat === 'W'
  return false
}

/**
 * Get full seat name
 * @param {string} seat N/E/S/W
 * @returns {string} Full name
 */
export function getSeatName(seat) {
  const names = { N: 'North', E: 'East', S: 'South', W: 'West' }
  return names[seat] || seat
}

/**
 * Count high card points in a hand
 * @param {Object} hand { spades, hearts, diamonds, clubs }
 * @returns {number} HCP
 */
export function countHCP(hand) {
  if (!hand) return 0

  const values = { A: 4, K: 3, Q: 2, J: 1 }
  let hcp = 0

  for (const suit of SUIT_ORDER) {
    for (const card of hand[suit] || []) {
      hcp += values[card] || 0
    }
  }

  return hcp
}

/**
 * Count total cards in a hand
 * @param {Object} hand
 * @returns {number}
 */
export function countCards(hand) {
  if (!hand) return 0
  return SUIT_ORDER.reduce((sum, suit) => sum + (hand[suit]?.length || 0), 0)
}

/**
 * Get distribution string (e.g., "5-4-3-1")
 * @param {Object} hand
 * @returns {string}
 */
export function getDistribution(hand) {
  if (!hand) return ''
  return SUIT_ORDER
    .map(suit => hand[suit]?.length || 0)
    .sort((a, b) => b - a)
    .join('-')
}

/**
 * Format a card code (e.g., "HK") for display
 * @param {string} code Card code like "HK", "DT", "S4"
 * @returns {Object} { text, html } formatted card
 */
export function formatCardCode(code) {
  if (!code) return { text: '', html: '' }

  const suit = code[0].toUpperCase()
  let rank = code.slice(1).toUpperCase()
  if (rank === 'T') rank = '10'

  const symbol = SUIT_SYMBOLS[suit] || suit
  const colorClass = suit === 'H' || suit === 'D' ? 'suit-red' : 'suit-black'

  return {
    text: `${symbol}${rank}`,
    html: `<span class="${colorClass}">${symbol}</span>${rank}`
  }
}

/**
 * Flow PBN text for display: collapse single newlines to spaces (like HTML),
 * preserve paragraph breaks (double+ newlines).
 * PBN files wrap lines at ~80 chars, so single newlines are just word wrapping.
 * @param {string} text Raw PBN text
 * @returns {string} Flowed text with only paragraph breaks preserved
 */
export function flowText(text) {
  if (!text) return ''
  // Normalize: sequences with 2+ newlines (with optional whitespace between) → \n\n
  let result = text.replace(/(\s*\n\s*){2,}/g, '\n\n')
  // Split into paragraphs on double newlines
  const paragraphs = result.split('\n\n')
  // Within each paragraph, collapse single newlines (and surrounding whitespace) to a single space
  return paragraphs
    .map(p => p.replace(/\s*\n\s*/g, ' ').replace(/\s+/g, ' ').trim())
    .filter(p => p.length > 0)
    .join('\n\n')
}

/**
 * Strip PBN control directives from text for display
 * Removes [BID xxx], [NEXT], [ROTATE], [PLAY ...], [SHOW ...] and similar markers
 * @param {string} text
 * @returns {string} Cleaned text
 */
export function stripControlDirectives(text) {
  if (!text) return ''
  return text
    .replace(/\[BID\s+[^\]]*\]/gi, '')
    .replace(/\[NEXT\]/gi, '')
    .replace(/\[ROTATE\]/gi, '')
    .replace(/\[PLAY\s+[^\]]*\]/gi, '')
    .replace(/\[SHOW\s+[^\]]*\]/gi, '')
    .replace(/\[choose-card\s+[^\]]*\]/gi, '')
    .replace(/\n{3,}/g, '\n\n')  // Collapse multiple newlines
    .trim()
}

/**
 * Convert suit symbols to colored HTML spans
 * ♠♣ = black, ♥♦ = red
 * @param {string} text Plain text with suit symbols
 * @returns {string} HTML with colored suit symbols
 */
export function colorizeSuits(text) {
  if (!text) return ''
  return text
    .replace(/♠/g, '<span class="suit-black">♠</span>')
    .replace(/♣/g, '<span class="suit-black">♣</span>')
    .replace(/♥/g, '<span class="suit-red">♥</span>')
    .replace(/♦/g, '<span class="suit-red">♦</span>')
}

const SUIT_CHAR = { S: '♠', H: '♥', D: '♦', C: '♣' }

/**
 * Normalize user-typed suit shorthand to actual suit characters.
 * Supported inputs:
 *   - "!S" / "!H" / "!D" / "!C" (case-insensitive) → ♠♥♦♣
 *   - Digit + suit letter at a word boundary ("2C", "3D", "1c")
 *     → digit + suit char ("2♣", "3♦", "1♣"). "2NT" is left alone
 *     because N is not in the suit-letter set.
 *   - Standalone uppercase S / H / D / C surrounded by word boundaries
 *     (so "S" or "S, H" converts, but "Spades" or "ASH" do not).
 *
 * Always safe to call on already-normalized text — it's idempotent.
 */
export function normalizeSuitShorthand(text) {
  if (!text) return text
  return String(text)
    .replace(/!\s*([SHDC])/gi, (_, l) => SUIT_CHAR[l.toUpperCase()])
    .replace(/([1-7])([SHDC])\b/gi, (_, n, l) => n + SUIT_CHAR[l.toUpperCase()])
    .replace(/\bS\b/g, '♠')
    .replace(/\bH\b/g, '♥')
    .replace(/\bD\b/g, '♦')
    .replace(/\bC\b/g, '♣')
}
