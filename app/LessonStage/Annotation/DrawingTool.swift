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
            + [.highlighter(.yellow), .eraser]
    }

    var pkTool: PKTool {
        switch self {
        case .pen(let color):
            PKInkingTool(.pen, color: color.uiColor, width: 3)
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
    case black, red, blue, yellow

    /// Yellow is a highlighter colour, not a pen colour — it is illegible as
    /// ink on a white lesson page.
    static var penCases: [PenColor] { [.black, .red, .blue] }

    var name: String { rawValue.capitalized }

    var uiColor: UIColor {
        switch self {
        case .black: UIColor(white: 0.1, alpha: 1)
        case .red: UIColor(red: 0.80, green: 0.13, blue: 0.13, alpha: 1)
        case .blue: UIColor(red: 0.11, green: 0.36, blue: 0.78, alpha: 1)
        case .yellow: UIColor(red: 0.98, green: 0.85, blue: 0.20, alpha: 1)
        }
    }

    var swiftUIColor: Color { Color(uiColor) }
}
