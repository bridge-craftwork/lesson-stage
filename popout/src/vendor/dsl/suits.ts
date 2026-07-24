/** A run of text tagged as a red suit glyph (♥/♦) or plain. */
export interface SuitSegment {
  text: string
  red?: boolean
}

/** The red-suit glyphs. Spades/clubs render in the default color. */
export const RED_SUIT_GLYPHS = ['♥', '♦'] as const
const RED = new Set<string>(RED_SUIT_GLYPHS)

/** Regex matching a single red-suit glyph (for prose decorations). */
export const RED_SUIT_RE = /[♥♦]/g

/**
 * Split text so red-suit glyphs (♥/♦) can be colored wherever they appear —
 * response boxes, footnotes, quiz text. Consecutive plain characters coalesce
 * into one segment.
 */
export function splitRedSuits(text: string): SuitSegment[] {
  const out: SuitSegment[] = []
  let buffer = ''
  for (const ch of text) {
    if (RED.has(ch)) {
      if (buffer) {
        out.push({ text: buffer })
        buffer = ''
      }
      out.push({ text: ch, red: true })
    } else {
      buffer += ch
    }
  }
  if (buffer) out.push({ text: buffer })
  return out
}
