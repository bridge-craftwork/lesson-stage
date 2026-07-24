import type { Call } from './types'

/** A legal call: pass/double/redouble, or level 1-7 + strain. */
export const CALL_RE = /^(P|X|XX|[1-7](C|D|H|S|NT))$/

export function isCall(token: string): token is Call {
  return CALL_RE.test(token)
}

// Annotation marker on a call. PBN style `=1=` is canonical; `^1` is the
// legacy form and is still accepted. An alert `!` sits between the call and the
// marker (`2D! =1=`), so strip it too when recovering the bare call.
const ANNOTATION_MARKER = /!?(?:=(\d+)=|\^(\d+))$|!$/

/** Strip a trailing alert and/or annotation marker: `"2C! =1="` -> `"2C"`. */
export function stripAnnotationMarker(call: string): string {
  return call.replace(ANNOTATION_MARKER, '')
}

/** The annotation index on a call, or null: `"2C=1="` -> `1`, `"2C!"` -> null. */
export function annotationIndex(call: string): number | null {
  const digits = call.match(ANNOTATION_MARKER)?.slice(1).find((g) => g != null)
  return digits == null ? null : Number(digits)
}

// An alert marks a call as conventional. Teaching material (BridgeBum,
// BridgeComposer) and BBO write it `2D!`, with no note text required. PBN
// accepts the same suffix syntactically but reads it as a move-quality glyph
// ("a good call") — we take the teaching meaning; see Contract 1.
const ALERT_MARKER = /!(?:=\d+=|\^\d+)?$/

/** Whether a call carries an alert marker: `"2D!"`, `"2D! =1="` -> true. */
export function hasAlert(call: string): boolean {
  return ALERT_MARKER.test(call)
}

const STRAIN_GLYPH: Record<string, string> = { C: '♣', D: '♦', H: '♥', S: '♠' }

/**
 * Human display for a call: strains become suit glyphs, calls become words.
 * `"1C"` -> `"1♣"`, `"3NT"` -> `"3NT"`, `"P"` -> `"Pass"`, `"X"` -> `"Dbl"`,
 * `"XX"` -> `"Rdbl"`. Input may carry an annotation marker, which is dropped.
 */
export function formatCall(call: string): string {
  const c = stripAnnotationMarker(call)
  if (c === 'P') return 'Pass'
  if (c === 'X') return 'Dbl'
  if (c === 'XX') return 'Rdbl'
  const m = c.match(/^([1-7])(C|D|H|S|NT)$/)
  if (!m) return c
  return m[2] === 'NT' ? `${m[1]}NT` : `${m[1]}${STRAIN_GLYPH[m[2]]}`
}

/** Whether a strain in a call renders in the red suits (for coloring). */
export function isRedCall(call: string): boolean {
  const c = stripAnnotationMarker(call)
  return /[1-7](D|H)$/.test(c)
}

/** One display segment of a call; `red` is true only for a red suit glyph. */
export interface CallSegment {
  text: string
  red?: boolean
}

// A bid-like token in free text: one or more levels then a strain, e.g. "3D",
// "2NT", or the shorthand "2/3H" ("two or three hearts"). The lookahead keeps
// it from firing inside words ("1st", "3Diamonds").
const BID_TOKEN = /(\d+(?:\/\d+)*)(NT|[CDHS])(?![A-Za-z0-9])/g
const RED_GLYPH = /[♥♦]/

/**
 * Segment free-form bid notation for display: bid-like tokens render their
 * strain as a suit glyph (red for ♦/♥) while the levels stay black, and any
 * literal glyphs already in the text are colored too. Handles the compound
 * shorthand used in convention tables — `"2/3H"` -> `2/3♥`.
 *
 * Only for columns that are bid notation by convention (e.g. a response-box's
 * left column); running it over prose would mangle words.
 */
export function bidTextSegments(text: string): CallSegment[] {
  const out: CallSegment[] = []
  const pushPlain = (chunk: string) => {
    for (const ch of chunk) {
      if (RED_GLYPH.test(ch)) out.push({ text: ch, red: true })
      else if (out.length && !out[out.length - 1].red) out[out.length - 1].text += ch
      else out.push({ text: ch })
    }
  }

  let last = 0
  for (const m of text.matchAll(BID_TOKEN)) {
    pushPlain(text.slice(last, m.index))
    out.push({ text: m[1] })
    if (m[2] === 'NT') out.push({ text: 'NT' })
    else out.push({ text: STRAIN_GLYPH[m[2]], red: m[2] === 'D' || m[2] === 'H' })
    last = m.index + m[0].length
  }
  pushPlain(text.slice(last))
  return out.filter((s) => s.text !== '')
}

/**
 * Split a call into display segments so only the suit glyph is colored: the
 * level digit, `NT`, and non-bid calls stay black. `"2D"` ->
 * `[{text:"2"},{text:"♦",red:true}]`; `"3NT"` -> `[{text:"3NT"}]`;
 * `"P"` -> `[{text:"Pass"}]`. Any annotation marker is dropped.
 */
export function callSegments(call: string): CallSegment[] {
  const c = stripAnnotationMarker(call)
  if (c === 'P') return [{ text: 'Pass' }]
  if (c === 'X') return [{ text: 'Dbl' }]
  if (c === 'XX') return [{ text: 'Rdbl' }]
  const m = c.match(/^([1-7])(C|D|H|S|NT)$/)
  if (!m) return [{ text: c }]
  if (m[2] === 'NT') return [{ text: `${m[1]}NT` }]
  return [{ text: m[1] }, { text: STRAIN_GLYPH[m[2]], red: m[2] === 'D' || m[2] === 'H' }]
}
