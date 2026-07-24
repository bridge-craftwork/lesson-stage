import type { Seat } from './types'
import { isCall, stripAnnotationMarker, annotationIndex, hasAlert } from './call'

/** A parsed `auction` block (Contract 1). */
export interface AuctionBlock {
  dealer: Seat
  /** Calls in bidding order (dealer first). `AP` is kept verbatim. */
  calls: string[]
  /** Numbered annotation notes, keyed by marker index. */
  notes: Record<number, string>
  /** Display: 4 (default) or 2, the uncontested two-column print form. */
  columns: 2 | 4
  /** Display: explicit header labels for the two-column form, left then right. */
  labels?: [string, string]
  /** Display: false drops gridlines and the header bar. Default true. */
  grid: boolean
  /**
   * Which hand this auction is bid on: the `id` of a `hand`/`hands` block, or
   * `none` to opt out of the default pairing. Absent means "nearest preceding
   * hand" — resolved across the document by `resolveDealLinks`, not here, since
   * a block parser only ever sees its own body.
   */
  deal?: string
}

/** One `meanings` entry (Contract 2). `meaning`/`note` absent on a bare alert. */
export interface AuctionMeaning {
  position: number
  bid: string
  meaning?: string
  note?: number
  isAlert?: boolean
}

/** Component props for `AuctionTable` (Contract 2): flat bids + meanings. */
export interface AuctionProps {
  dealer: Seat
  bids: string[]
  /** `note` is the annotation number, shared by the superscript and the list. */
  meanings: AuctionMeaning[]
  columns: 2 | 4
  labels?: [string, string]
  grid: boolean
}

const SEATS: Seat[] = ['N', 'E', 'S', 'W']
const NOTE_LINE = /^(\d+)\.\s*(.*)$/

/**
 * Parse an `auction` block body: a `dealer:` key, a flat whitespace-separated
 * list of calls, and optional numbered notes after a `---` separator.
 *
 * Annotations follow the PBN convention — a `=n=` marker after the call it
 * annotates (`2D =1=`), as in PBN auction sections. The marker may also be
 * written attached (`2D=1=`), and the legacy `2D^1` form is still accepted.
 */
export function parseAuctionBlock(body: string): AuctionBlock {
  const [callPart, notePart = ''] = body.split(/^---\s*$/m)

  let dealer: Seat | undefined
  let columns: 2 | 4 = 4
  let labels: [string, string] | undefined
  let grid = true
  let deal: string | undefined
  const calls: string[] = []
  for (const rawLine of callPart.split('\n')) {
    const line = rawLine.trim()
    if (line === '') continue
    const dealerMatch = line.match(/^dealer:\s*(.*)$/)
    if (dealerMatch) {
      const d = dealerMatch[1].trim().toUpperCase()
      if (!SEATS.includes(d as Seat)) throw new Error(`illegal dealer "${dealerMatch[1]}"`)
      dealer = d as Seat
      continue
    }
    const columnsMatch = line.match(/^columns:\s*(.*)$/)
    if (columnsMatch) {
      const n = Number(columnsMatch[1].trim())
      if (n !== 2 && n !== 4) throw new Error(`illegal columns "${columnsMatch[1].trim()}" (2 or 4)`)
      columns = n
      continue
    }
    const labelsMatch = line.match(/^labels:\s*(.*)$/)
    if (labelsMatch) {
      const parts = labelsMatch[1].split(',').map((s) => s.trim())
      if (parts.length !== 2 || parts.some((s) => s === ''))
        throw new Error(`labels needs exactly two comma-separated entries`)
      labels = [parts[0], parts[1]]
      continue
    }
    const dealMatch = line.match(/^deal:\s*(.*)$/)
    if (dealMatch) {
      const d = dealMatch[1].trim()
      if (!d) throw new Error('deal: needs a hand id, or "none"')
      deal = d
      continue
    }
    const gridMatch = line.match(/^grid:\s*(.*)$/)
    if (gridMatch) {
      const g = gridMatch[1].trim().toLowerCase()
      if (g !== 'on' && g !== 'off') throw new Error(`illegal grid "${gridMatch[1].trim()}" (on or off)`)
      grid = g === 'on'
      continue
    }
    for (const token of line.split(/\s+/)) {
      // A standalone PBN marker annotates the call before it: `2D =1=`.
      const standalone = token.match(/^=(\d+)=$/)
      if (standalone) {
        if (calls.length === 0) throw new Error(`annotation "${token}" precedes any call`)
        calls[calls.length - 1] = `${calls[calls.length - 1]}=${standalone[1]}=`
        continue
      }
      if (token === 'AP' || isCall(stripAnnotationMarker(token))) calls.push(token)
      else throw new Error(`illegal call "${token}" in auction`)
    }
  }
  if (!dealer) throw new Error('auction block missing dealer')

  const notes: Record<number, string> = {}
  for (const rawLine of notePart.split('\n')) {
    const m = rawLine.trim().match(NOTE_LINE)
    if (m) notes[Number(m[1])] = m[2]
  }

  return { dealer, calls, notes, columns, labels, grid, deal }
}

/** Adapt a parsed auction to `AuctionTable` props (Contract 2). */
export function toAuctionProps(block: AuctionBlock): AuctionProps {
  const bids = block.calls.map(stripAnnotationMarker)
  const meanings = block.calls
    .map((call, position) => {
      const idx = annotationIndex(call)
      const note = idx != null && block.notes[idx] ? idx : undefined
      const alert = hasAlert(call)
      // A bare `!` still earns an entry — it carries no text, but the component
      // needs one to know the cell is alerted.
      if (note == null && !alert) return null
      const m: AuctionMeaning = { position, bid: stripAnnotationMarker(call) }
      if (note != null) {
        m.meaning = block.notes[note]
        m.note = note
      }
      if (alert) m.isAlert = true
      return m
    })
    .filter((m): m is AuctionMeaning => m !== null)
  return {
    dealer: block.dealer,
    bids,
    meanings,
    columns: block.columns,
    labels: block.labels,
    grid: block.grid,
  }
}
