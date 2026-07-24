import Foundation
import os

/// Timestamped launch tracing, DEBUG-only. Each `mark` logs milliseconds since
/// the first mark, so a gap between two marks localises a startup stall — the
/// last mark before a jump is the phase that blocked.
///
/// Temporary instrumentation for the cold-launch black screen. Remove once the
/// stall is found and fixed.
enum LaunchLog {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.popperbiz.LessonStage", category: "launch")
    nonisolated(unsafe) private static var start: Date?

    static func mark(_ label: @autoclosure () -> String) {
        let now = Date()
        if start == nil { start = now }
        let ms = Int(now.timeIntervalSince(start ?? now) * 1000)
        let text = label()
        logger.log("LAUNCH +\(ms)ms — \(text, privacy: .public)")
    }
    #else
    @inline(__always) static func mark(_ label: @autoclosure () -> String) {}
    #endif
}
