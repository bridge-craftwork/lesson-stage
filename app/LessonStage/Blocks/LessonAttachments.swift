import PDFKit

/// Pulls Contract 5's embedded files out of a lesson PDF.
///
/// PDFKit exposes no attachments API, so this drops to `CGPDFDocument`: walk the
/// catalog's `/Names /EmbeddedFiles` name tree and read each filespec's
/// `/AFRelationship`, filename, and `/EF /F` stream. This is the low-level C API
/// the contract warns about — isolated here, returning plain `Data`, so the
/// unpleasantness stays in one file and the failure mode is "no files," never a
/// crash.
enum LessonAttachments {
    struct File {
        /// The filename from the filespec (`/UF`, or `/F`).
        let filename: String
        /// The `/AFRelationship` name — `Source`, `Supplement`, `Data`, …
        let relationship: String
        /// The decoded file contents (`CGPDFStreamCopyData` applies the stream's
        /// filter, so this is the plain bytes, not the Flate-compressed stream).
        let data: Data
    }

    /// Every embedded file the document carries, read from the
    /// `/Names /EmbeddedFiles` name tree.
    static func files(in document: PDFDocument) -> [File] {
        guard let catalog = document.documentRef?.catalog else { return [] }

        var names: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "Names", &names), let names else { return [] }
        var embeddedFiles: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(names, "EmbeddedFiles", &embeddedFiles), let embeddedFiles else { return [] }
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(embeddedFiles, "Names", &array), let array else { return [] }

        // A leaf name tree is a flat array of alternating name / filespec — the
        // shape the print engine emits for a lesson's handful of files. (Large
        // trees can nest under /Kids; lesson PDFs never do.)
        var files: [File] = []
        let count = CGPDFArrayGetCount(array)
        var i = 0
        while i + 1 < count {
            var spec: CGPDFDictionaryRef?
            if CGPDFArrayGetDictionary(array, i + 1, &spec), let spec, let file = file(from: spec) {
                files.append(file)
            }
            i += 2
        }
        return files
    }

    private static func file(from spec: CGPDFDictionaryRef) -> File? {
        let filename = string(spec, "UF") ?? string(spec, "F") ?? ""
        let relationship = name(spec, "AFRelationship") ?? ""
        guard let data = streamData(spec) else { return nil }
        return File(filename: filename, relationship: relationship, data: data)
    }

    private static func streamData(_ spec: CGPDFDictionaryRef) -> Data? {
        var ef: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(spec, "EF", &ef), let ef else { return nil }
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(ef, "F", &stream), let stream else { return nil }
        var format = CGPDFDataFormat.raw
        return CGPDFStreamCopyData(stream, &format) as Data?
    }

    private static func string(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dict, key, &value), let value,
              let text = CGPDFStringCopyTextString(value) else { return nil }
        return text as String
    }

    private static func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, key, &value), let value else { return nil }
        return String(cString: value)
    }
}
