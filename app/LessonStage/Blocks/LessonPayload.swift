import PDFKit
import os

/// The parsed Contract 5 payload for one lesson: the click map (block bodies,
/// positions, and board join) plus the raw PBN.
///
/// `load` returns nil for every degraded case the contract names — no
/// attachments, attachments but no click map, an unknown version — so the caller
/// falls back to plain-PDF mode. The failure is always "popout unavailable,"
/// never a crash.
struct LessonPayload {
    let map: LessonBlockMap
    /// The deals, verbatim PBN. Nil when the lesson has no hands (the file is
    /// omitted entirely then). Parsing into a deal model is the popout's job.
    let pbn: String?

    static let supportedVersion = 1
    private static let logger = Logger(subsystem: "com.popperbiz.LessonStage", category: "contract5")

    static func load(from document: PDFDocument) -> LessonPayload? {
        let files = LessonAttachments.files(in: document)
        guard !files.isEmpty else { return nil } // plain PDF, or attachments stripped

        guard let blocksData = data("lesson-blocks.json", relationship: "Data", in: files) else {
            logger.notice("Lesson PDF has attachments but no click map; plain-PDF mode")
            return nil
        }

        let map: LessonBlockMap
        do {
            map = try JSONDecoder().decode(LessonBlockMap.self, from: blocksData)
        } catch {
            logger.error("Click map parse failed: \(error.localizedDescription)")
            return nil
        }
        guard map.version == supportedVersion else {
            // Do not best-effort-parse a future payload.
            logger.error("Click map version \(map.version) unsupported; plain-PDF mode")
            return nil
        }

        let pbn = data("lesson-hands.pbn", relationship: "Data", in: files)
            .flatMap { String(data: $0, encoding: .utf8) }

        return LessonPayload(map: map, pbn: pbn)
    }

    /// Locate a file by `AFRelationship` — the contract — with the filename
    /// disambiguating the two `Data` files, and a bare filename match as the
    /// documented fallback.
    private static func data(_ filename: String, relationship: String, in files: [LessonAttachments.File]) -> Data? {
        files.first { $0.relationship == relationship && $0.filename == filename }?.data
            ?? files.first { $0.filename == filename }?.data
    }
}
