import CoreGraphics
import PDFKit

/// Where the rows of text on a page actually are, and which of them a
/// highlighter drag is running along.
///
/// Two things about PDFKit make this necessary, and both of them show up on a
/// bridge hand rather than on prose.
///
/// **Its line boxes are not where the text is.** A line's `bounds` come from the
/// font's metrics, and the suit symbols in a hand come from a font with enormous
/// ascent and descent: on a lesson handout the four suit rows are 14pt apart and
/// every one of their line boxes is 31pt tall. Each row's box therefore swallows
/// its neighbours. Selecting with one picks up three suits, and painting a
/// highlight with one covers the row above. So the rows here are built from
/// glyph bounds — `characterBounds`, which are tight and correctly placed —
/// grouped by the line PDFKit assigned them to, which keeps rotated text (a
/// sideways spine label) in one piece.
///
/// **Its selection spans in reading order.** `PDFDocument.selection(from:at:to:at:)`
/// resolves each end of the drag to the *nearest* character and takes everything
/// between. Suit rows are short and unequal, so a drag along one finishes in
/// blank paper past its last card, where the nearest character is on a longer
/// row — and if the two rows sit in different text blocks, the reading-order run
/// between them can be most of the page. So a drag is resolved to rows here,
/// geometrically, and PDFKit is only ever asked for the text inside a rect.
struct TextRowLayout {
    struct Row: Equatable {
        /// PDFKit's line box. Kept only to match a selection's lines back to
        /// their row — it is the wrong shape to select or paint with.
        let lineBox: CGRect
        /// Where this row's glyphs actually are. Selections and highlights are
        /// cut from this.
        let band: CGRect
        /// The y range that still counts as being *on* this row, reaching half
        /// way into the gap on each side so a drag drifting into the leading
        /// belongs to one row rather than to neither.
        let top: CGFloat
        let bottom: CGFloat

        func isOn(_ y: CGFloat) -> Bool { y >= bottom && y <= top }
        /// How well this row answers for a point. A row is preferred when the
        /// point is on its glyphs rather than merely within the slack it reaches
        /// into the gap; then by vertical nearness; and only then by horizontal
        /// nearness, which is what separates the two columns of a lesson at the
        /// same height. The first key matters because a suit symbol inflates its
        /// row's glyph band — an auction line like "2♠/3♠ Three-card" reaches
        /// down over the indented line beneath it.
        func rank(for point: CGPoint) -> (Int, CGFloat, CGFloat) {
            (coversGlyphs(at: point.y) ? 0 : 1,
             verticalDistance(to: point.y),
             horizontalDistance(to: point.x))
        }
        /// Whether the point is on the row's glyphs themselves, rather than
        /// merely within the slack it reaches into the gap.
        func coversGlyphs(at y: CGFloat) -> Bool { y >= band.minY && y <= band.maxY }
        func verticalDistance(to y: CGFloat) -> CGFloat { max(bottom - y, y - top, 0) }
        func horizontalDistance(to x: CGFloat) -> CGFloat { max(band.minX - x, x - band.maxX, 0) }
    }

    let rows: [Row]

    /// Where a drag between two page-space points should take its text from.
    enum Target: Equatable {
        /// The bands to select, top to bottom — one per row the drag ran
        /// through, each already trimmed to where the drag began and ended.
        case rows([CGRect])
        /// The drag passed no row at all, so it selects nothing. Asked for a
        /// span here, PDFKit would answer with whatever text lies nearest,
        /// however far away that is.
        case noText
    }

    /// Build the rows from each line's box and the glyphs found inside it,
    /// working out how far each row reaches towards its neighbours.
    init(lines: [(lineBox: CGRect, band: CGRect)]) {
        let placed = lines.filter { $0.band.width > 1 && $0.band.height > 1 }
        rows = placed.map { row in
            var above = CGFloat.infinity, below = CGFloat.infinity
            for other in placed
            where other.band.minX < row.band.maxX && row.band.minX < other.band.maxX {
                if other.band.minY > row.band.maxY {
                    above = min(above, other.band.minY - row.band.maxY)
                } else if other.band.maxY < row.band.minY {
                    below = min(below, row.band.minY - other.band.maxY)
                }
            }
            // Reach half way into the gap, but never further than the row is
            // tall — a row with a lot of white space around it must not claim
            // all of it, or a drag over blank paper would find a row to grab.
            let limit = row.band.height / 2
            return Row(lineBox: row.lineBox, band: row.band,
                       top: row.band.maxY + (above.isFinite ? min(above / 2, limit) : limit),
                       bottom: row.band.minY - (below.isFinite ? min(below / 2, limit) : limit))
        }
    }

    func target(from start: CGPoint, to end: CGPoint) -> Target {
        let lo = min(start.x, end.x), hi = max(start.x, end.x)

        // Only rows the drag overlaps horizontally are in play. Without this, a
        // drag down one column of a two-column lesson can adopt a row in the
        // other, which is often nearer as the crow flies than anything in its
        // own column.
        let reachable = rows.filter { $0.band.minX <= hi && lo <= $0.band.maxX }
        guard !reachable.isEmpty else { return .noText }

        func row(at point: CGPoint) -> Row? {
            reachable.filter { $0.isOn(point.y) }.min { $0.rank(for: point) < $1.rank(for: point) }
        }
        let startRow = row(at: start)
        // A drag is presumed to stay on the row it began on, leaving it only
        // when the far end is clearly past that row. This is what holds a suit
        // row together: such a drag ends in blank paper that is nearer the next
        // row than its own last card.
        let endRow = (startRow?.isOn(end.y) == true) ? startRow : row(at: end)

        // The rows the drag ran through: those whose band centre lies between
        // its two ends. Centres, not bands — bands sit next to each other, so
        // testing them catches the neighbour at the boundary.
        let startY = startRow?.band.midY ?? start.y
        let endY = endRow?.band.midY ?? end.y
        var crossed = reachable
            .filter { $0.band.midY >= min(startY, endY) - 0.5 && $0.band.midY <= max(startY, endY) + 0.5 }
            .sorted { $0.band.midY > $1.band.midY }
        if crossed.isEmpty, let only = startRow ?? endRow { crossed = [only] }
        guard !crossed.isEmpty else { return .noText }

        // Trim the ends: the top row starts where the upper end of the drag is,
        // the bottom row finishes where the lower end is, and any row between
        // the two is taken whole.
        let upper = start.y >= end.y ? start : end
        let lower = start.y >= end.y ? end : start
        let rects = crossed.enumerated().map { position, row -> CGRect in
            var left = row.band.minX, right = row.band.maxX
            if crossed.count == 1 {
                left = lo
                right = hi
            } else if position == 0 {
                left = upper.x
            } else if position == crossed.count - 1 {
                right = lower.x
            }
            return CGRect(x: left, y: row.band.minY,
                          width: max(right - left, 0), height: row.band.height)
        }
        return .rows(rects.filter { $0.width > 0 })
    }

    /// The row a single point is on, or nil for blank paper.
    ///
    /// This is what decides whether a pen hold switches to highlighting, so it
    /// is deliberately tighter than `target(from:to:)`: the point has to be on
    /// the row's own text horizontally, not merely at its height, or a hold out
    /// in the margin would stop inking.
    ///
    /// The row is the test rather than `PDFPage.characterIndex(at:)`, which
    /// answers with the nearest character everywhere on the page and whose
    /// bounds are *zero height* on the spaces between the cards of a suit — so
    /// gating on them left dead patches right where a card is being aimed at.
    func row(covering point: CGPoint) -> Row? {
        rows.filter {
            $0.isOn(point.y) && point.x >= $0.band.minX - Self.edgeSlack
                && point.x <= $0.band.maxX + Self.edgeSlack
        }
        .min { $0.rank(for: point) < $1.rank(for: point) }
    }

    /// How far past the end of a row still counts as being on it — enough to
    /// forgive starting a hair before the first card or after the last.
    static let edgeSlack: CGFloat = 2

    /// The glyph band for one line of a selection, found by the line box it came
    /// from. Used to pull a highlight's rect back onto the text: PDFKit reports
    /// a selected line's bounds as its line box, which on a hand is more than
    /// twice the row pitch and would paint over the suit above.
    func band(forSelectedLine rect: CGRect) -> CGRect? {
        rows.first {
            abs($0.lineBox.minY - rect.minY) < 0.5 && abs($0.lineBox.maxY - rect.maxY) < 0.5
                && $0.lineBox.minX - 0.5 <= rect.minX && rect.maxX <= $0.lineBox.maxX + 0.5
        }?.band
    }

    /// A selected line's rect, pulled back onto the glyphs it covers. Falls back
    /// to the rect unchanged when the line cannot be placed.
    func tighten(_ rect: CGRect) -> CGRect {
        guard let band = band(forSelectedLine: rect) else { return rect }
        return CGRect(x: rect.minX, y: band.minY, width: rect.width, height: band.height)
    }
}

extension TextRowLayout {
    /// Read a page's rows. This walks the page's whole text layout, so the
    /// caller caches the result — a drag rebuilds its selection every frame.
    init(page: PDFPage) {
        let lineBoxes = (page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? [])
            .map { $0.bounds(for: page) }
            .filter { $0.width > 0 && $0.height > 0 }
        guard !lineBoxes.isEmpty else { self.init(lines: []); return }

        // Group the glyphs by the line they belong to. A glyph is only ever
        // claimed by a line whose box it sits inside, so a line cannot vacuum up
        // text from elsewhere on the page; where the inflated boxes overlap, the
        // nearest line centre wins.
        var glyphs: [Int: CGRect] = [:]
        for index in 0..<page.numberOfCharacters {
            let glyph = page.characterBounds(at: index)
            guard glyph.width > 0.1, glyph.height > 0.1 else { continue }
            let centre = CGPoint(x: glyph.midX, y: glyph.midY)

            var claimed: Int?
            var nearest = CGFloat.infinity
            for (line, box) in lineBoxes.enumerated() where box.contains(centre) {
                let distance = abs(box.midY - glyph.midY)
                if distance < nearest { nearest = distance; claimed = line }
            }
            guard let line = claimed else { continue }
            glyphs[line] = glyphs[line].map { $0.union(glyph) } ?? glyph
        }

        // A line whose glyphs could not be placed keeps its own box: worse
        // geometry, but never a missing row.
        self.init(lines: lineBoxes.indices.map {
            (lineBox: lineBoxes[$0], band: glyphs[$0] ?? lineBoxes[$0])
        })
    }
}
