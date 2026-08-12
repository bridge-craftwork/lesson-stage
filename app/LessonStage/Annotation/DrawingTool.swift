import PencilKit
import SwiftUI

/// The marking tools, deliberately few.
///
/// A minimal palette rather than `PKToolPicker`: the picker attaches to a
/// single first responder, and this app has one canvas *per page* — a dozen
/// live at once in a continuous scroll. Driving the picker's first-responder
/// dance across them costs more than the palette it replaces, and Phase 2b
/// needs custom stroke routing anyway.
enum DrawingTool: Equatable, Hashable, CaseIterable {
    case pen(PenColor)
    case highlighter(PenColor)
    case eraser

    static var allCases: [DrawingTool] {
        PenColor.penCases.map(DrawingTool.pen)
            + PenColor.highlighterCases.map(DrawingTool.highlighter)
            + [.eraser]
    }

    var pkTool: PKTool {
        switch self {
        case .pen(let color):
            // 4.5, up from 3, so a hard press lands ~50% thicker. PencilKit
            // scales the whole force range off this single width — there is no
            // separate max — so the light end comes up too, just less
            // noticeably. Tune here if the thin end feels heavy.
            PKInkingTool(.pen, color: color.uiColor, width: 4.5)
        case .highlighter(let color):
            // Marker ink is translucent by design, so lesson text stays
            // readable under a highlight.
            PKInkingTool(.marker, color: color.uiColor.withAlphaComponent(0.4), width: 18)
        case .eraser:
            // Stroke-erasing, not pixel-erasing: on a lesson the intent is
            // almost always "remove that mark", not "rub out part of it".
            PKEraserTool(.vector)
        }
    }

    var symbolName: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        }
    }

    var accessibilityName: String {
        switch self {
        case .pen(let color): "\(color.name) pen"
        case .highlighter(let color): "\(color.name) highlighter"
        case .eraser: "Eraser"
        }
    }

    var tint: Color? {
        switch self {
        case .pen(let color), .highlighter(let color): color.swiftUIColor
        case .eraser: nil
        }
    }
}

enum PenColor: String, Equatable, Hashable, CaseIterable {
    case black, red, blue, yellow, orange, lightBlue

    /// The pen inks. Yellow/orange/light-blue are highlighter colours, not pen
    /// colours — they are illegible as ink on a white lesson page.
    static var penCases: [PenColor] { [.black, .red, .blue] }

    /// The highlighter tints, in palette order.
    static var highlighterCases: [PenColor] { [.yellow, .orange, .lightBlue] }

    /// The next highlighter tint in the cycle — what tapping an existing
    /// highlight rotates it to. Wraps, and falls back to the first tint for a
    /// colour that isn't a highlighter one.
    static func nextHighlighter(after color: PenColor) -> PenColor {
        let cycle = highlighterCases
        guard let i = cycle.firstIndex(of: color) else { return cycle[0] }
        return cycle[(i + 1) % cycle.count]
    }

    var name: String {
        switch self {
        case .black: "Black"
        case .red: "Red"
        case .blue: "Blue"
        case .yellow: "Yellow"
        case .orange: "Orange"
        case .lightBlue: "Light Blue"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .black: .black
        case .red: UIColor(red: 0.80, green: 0.13, blue: 0.13, alpha: 1)
        case .blue: UIColor(red: 0.11, green: 0.36, blue: 0.78, alpha: 1)
        case .yellow: UIColor(red: 1.0, green: 0.94, blue: 0.32, alpha: 1)
        // Highlighter tints: the `.highlight` annotation multiplies these onto
        // the page, so a bright, light base reads as a soft wash over the text.
        case .orange: UIColor(red: 0.99, green: 0.62, blue: 0.20, alpha: 1)
        case .lightBlue: UIColor(red: 0.35, green: 0.74, blue: 0.96, alpha: 1)
        }
    }

    var swiftUIColor: Color { Color(uiColor) }
}
