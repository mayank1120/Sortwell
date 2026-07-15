import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

struct LocalContentAnalysis: Sendable {
    let text: String
    let metadataText: String
    let evidenceDescription: String?

    static let empty = LocalContentAnalysis(text: "", metadataText: "", evidenceDescription: nil)

    var searchableText: String {
        "\(text) \(metadataText)".lowercased()
    }
}

actor LocalContentAnalyzer {
    private let contentAnalysisEnabled: Bool
    private let ocrEnabled: Bool

    init(preferences: SortwellPreferences) {
        contentAnalysisEnabled = preferences.contentAnalysisEnabled
        ocrEnabled = preferences.ocrEnabled
    }

    func analyse(_ url: URL) throws -> LocalContentAnalysis {
        guard contentAnalysisEnabled else { return .empty }
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        var metadataParts = [type?.localizedDescription, formattedDate(values.creationDate), formattedDate(values.contentModificationDate)]
            .compactMap { $0 }

        if type?.conforms(to: .pdf) == true {
            return try analysePDF(url, metadataParts: &metadataParts, fileSize: Int64(values.fileSize ?? 0))
        }
        if type?.conforms(to: .image) == true {
            return try analyseImage(url, metadataParts: &metadataParts, fileSize: Int64(values.fileSize ?? 0))
        }
        if type?.conforms(to: .plainText) == true || ["csv", "md", "json", "xml", "yaml", "yml", "rtf"].contains(url.pathExtension.lowercased()) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 200_000) ?? Data()
            try Task.checkCancellation()
            let text = String(decoding: data, as: UTF8.self)
            return .init(text: text, metadataText: metadataParts.joined(separator: " "), evidenceDescription: "local text content and file metadata")
        }
        return .init(text: "", metadataText: metadataParts.joined(separator: " "), evidenceDescription: metadataParts.isEmpty ? nil : "local file metadata")
    }

    private func analysePDF(_ url: URL, metadataParts: inout [String], fileSize: Int64) throws -> LocalContentAnalysis {
        guard fileSize <= 100 * 1_024 * 1_024, let document = PDFDocument(url: url), !document.isLocked else {
            return .init(text: "", metadataText: metadataParts.joined(separator: " "), evidenceDescription: "PDF metadata")
        }
        if let attributes = document.documentAttributes {
            metadataParts += [
                attributes[PDFDocumentAttribute.titleAttribute] as? String,
                attributes[PDFDocumentAttribute.authorAttribute] as? String,
                attributes[PDFDocumentAttribute.subjectAttribute] as? String,
                (attributes[PDFDocumentAttribute.keywordsAttribute] as? [String])?.joined(separator: " ")
            ].compactMap { $0 }
        }

        var text = ""
        let pageLimit = min(document.pageCount, 50)
        for index in 0..<pageLimit {
            try Task.checkCancellation()
            guard let pageText = document.page(at: index)?.string else { continue }
            append(pageText, to: &text, limit: 200_000)
            if text.count >= 200_000 { break }
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40, ocrEnabled {
            for index in 0..<min(document.pageCount, 5) {
                try Task.checkCancellation()
                guard let page = document.page(at: index),
                      let image = page.thumbnail(of: .init(width: 1800, height: 2400), for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                append(try recogniseText(in: image), to: &text, limit: 200_000)
            }
        }
        let evidence = text.isEmpty ? "PDF metadata" : (ocrEnabled ? "local PDF text/OCR and metadata" : "local PDF text and metadata")
        return .init(text: text, metadataText: metadataParts.joined(separator: " "), evidenceDescription: evidence)
    }

    private func analyseImage(_ url: URL, metadataParts: inout [String], fileSize: Int64) throws -> LocalContentAnalysis {
        guard fileSize <= 25 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .init(text: "", metadataText: metadataParts.joined(separator: " "), evidenceDescription: "image metadata")
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value ?? 0
        metadataParts.append("\(width) by \(height) pixels")
        guard ocrEnabled, width > 0, height > 0, width <= 12_000, height <= 12_000, width * height <= 40_000_000 else {
            return .init(text: "", metadataText: metadataParts.joined(separator: " "), evidenceDescription: "image metadata")
        }
        let orientationRaw = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let handler = VNImageRequestHandler(url: url, orientation: .init(rawValue: orientationRaw) ?? .up)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try handler.perform([request])
        try Task.checkCancellation()
        let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
        return .init(text: String(text.prefix(50_000)), metadataText: metadataParts.joined(separator: " "), evidenceDescription: "local image OCR and metadata")
    }

    private func recogniseText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
    }

    private func append(_ value: String, to output: inout String, limit: Int) {
        guard output.count < limit else { return }
        if !output.isEmpty { output.append("\n") }
        output.append(contentsOf: value.prefix(limit - output.count))
    }

    private func formattedDate(_ date: Date?) -> String? {
        date?.formatted(date: .abbreviated, time: .omitted)
    }
}
