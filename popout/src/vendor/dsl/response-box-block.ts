/** A parsed `response-box` block (Contract 1). */
export interface ResponseBoxBlock {
  title: string
  rows: { left: string; right: string }[]
  note?: string
}

/**
 * Parse a `response-box` block body: a `title:` key, `left | right` rows, and
 * an optional footer note after a `---` separator.
 */
export function parseResponseBox(body: string): ResponseBoxBlock {
  const [rowPart, notePart] = body.split(/^---\s*$/m)

  let title = ''
  const rows: { left: string; right: string }[] = []
  for (const rawLine of rowPart.split('\n')) {
    const line = rawLine.trim()
    if (line === '') continue
    const titleMatch = line.match(/^title:\s*(.*)$/)
    if (titleMatch) {
      title = titleMatch[1].trim()
      continue
    }
    const pipe = line.indexOf('|')
    if (pipe === -1) throw new Error(`response-box row missing "|": "${line}"`)
    rows.push({ left: line.slice(0, pipe).trim(), right: line.slice(pipe + 1).trim() })
  }
  if (!title) throw new Error('response-box block missing title')

  const note = notePart?.trim() || undefined
  return { title, rows, note }
}
