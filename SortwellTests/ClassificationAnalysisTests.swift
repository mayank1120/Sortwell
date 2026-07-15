import Foundation
import XCTest
@testable import Sortwell

final class ClassificationAnalysisTests: XCTestCase {
    func testBuiltInClassificationUsesWordBoundaries() {
        let classifier = FileClassifier()

        XCTAssertEqual(classifier.classify(name: "current.pdf", isDirectory: false)?.category, "Other Documents")
        XCTAssertEqual(classifier.classify(name: "unemployment.pdf", isDirectory: false)?.category, "Other Documents")
        XCTAssertEqual(classifier.classify(name: "rent receipt.pdf", isDirectory: false)?.category, "Finance & Bills")
    }

    func testCustomRulesAreOrderedAndNormaliseExtensions() {
        let preferences = SortwellPreferences(
            schemaVersion: SortwellPreferences.currentSchemaVersion,
            customCategories: [
                .init(id: "first", title: "First", icon: "folder"),
                .init(id: "second", title: "Second", icon: "folder")
            ],
            customRules: [
                .init(id: "first-rule", categoryID: "first", matchKind: .fileExtension, pattern: ".PDF", target: .files, isEnabled: true),
                .init(id: "second-rule", categoryID: "second", matchKind: .fileExtension, pattern: "pdf", target: .files, isEnabled: true)
            ],
            recoveryRetentionDays: 30,
            contentAnalysisEnabled: true,
            ocrEnabled: true
        )

        let result = FileClassifier(preferences: preferences).classify(name: "Statement.PDF", isDirectory: false)

        XCTAssertEqual(result?.category, "First")
        XCTAssertTrue(result?.explanation.contains(".PDF") == true)
    }

    func testContentRuleHonoursTargetAndEnabledState() {
        var preferences = SortwellPreferences.defaults
        preferences.customCategories = [.init(id: "receipts", title: "Receipts", icon: "receipt")]
        preferences.customRules = [
            .init(
                id: "content-rule",
                categoryID: "receipts",
                matchKind: .contentContains,
                pattern: "payment received",
                target: .files,
                isEnabled: true
            )
        ]
        let analysis = LocalContentAnalysis(text: "Your payment received confirmation", metadataText: "", evidenceDescription: nil)
        let classifier = FileClassifier(preferences: preferences)

        XCTAssertEqual(classifier.classify(name: "scan.bin", isDirectory: false, analysis: analysis)?.category, "Receipts")
        XCTAssertNotEqual(classifier.classify(name: "Folder", isDirectory: true, analysis: analysis)?.category, "Receipts")

        preferences.customRules[0].isEnabled = false
        XCTAssertNotEqual(
            FileClassifier(preferences: preferences).classify(name: "scan.bin", isDirectory: false, analysis: analysis)?.category,
            "Receipts"
        )
    }

    func testTextAnalysisCapsDecodedContent() async throws {
        let fileURL = try makeTemporaryFile(
            name: "large.txt",
            data: Data((String(repeating: "a", count: 200_000) + "END-MARKER").utf8)
        )
        let analysis = try await LocalContentAnalyzer(preferences: .defaults).analyse(fileURL)

        XCTAssertEqual(analysis.text.utf8.count, 200_000)
        XCTAssertFalse(analysis.text.contains("END-MARKER"))
    }

    func testDisabledContentAnalysisDoesNotReadMissingFile() async throws {
        var preferences = SortwellPreferences.defaults
        preferences.contentAnalysisEnabled = false
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")

        let analysis = try await LocalContentAnalyzer(preferences: preferences).analyse(missingURL)

        XCTAssertTrue(analysis.text.isEmpty)
        XCTAssertTrue(analysis.metadataText.isEmpty)
    }

    private func makeTemporaryFile(name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortwellAnalysisTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
