import Foundation
import XCTest
@testable import Sortwell

final class PreferencesTests: XCTestCase {
    func testPreferencesRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortwellPreferencesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PreferencesRepository(fileURL: directory.appendingPathComponent("Preferences.json"))
        let preferences = SortwellPreferences(
            schemaVersion: SortwellPreferences.currentSchemaVersion,
            customCategories: [.init(id: "receipts", title: "Receipts", icon: "receipt")],
            customRules: [
                .init(
                    id: "receipt-rule",
                    categoryID: "receipts",
                    matchKind: .contentContains,
                    pattern: "payment received",
                    target: .files,
                    isEnabled: true
                )
            ],
            recoveryRetentionDays: 60,
            contentAnalysisEnabled: true,
            ocrEnabled: false
        )

        try repository.save(preferences)

        XCTAssertEqual(try repository.load(), preferences)
    }

    @MainActor
    func testStorePersistsCategoryAndRuleChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortwellStorePreferencesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PreferencesRepository(fileURL: directory.appendingPathComponent("Preferences.json"))
        let store = PrototypeStore(loadPersistedActivity: false, preferencesRepository: repository)

        try store.addCustomCategory(title: "Receipts", icon: "receipt")
        let categoryID = try XCTUnwrap(store.preferences.customCategories.first?.id)
        try store.addCustomRule(
            categoryID: categoryID,
            matchKind: .filenameContains,
            pattern: "receipt",
            target: .files
        )

        let reloaded = PrototypeStore(loadPersistedActivity: false, preferencesRepository: repository)
        XCTAssertEqual(reloaded.preferences.customCategories.map(\.title), ["Receipts"])
        XCTAssertEqual(reloaded.preferences.customRules.map(\.pattern), ["receipt"])

        try reloaded.removeCustomCategory(categoryID)
        let afterRemoval = PrototypeStore(loadPersistedActivity: false, preferencesRepository: repository)
        XCTAssertTrue(afterRemoval.preferences.customCategories.isEmpty)
        XCTAssertTrue(afterRemoval.preferences.customRules.isEmpty)
    }

    @MainActor
    func testCategoryAndRuleValidationRejectsUnsafeValues() throws {
        let repository = PreferencesRepository.temporary()
        let store = PrototypeStore(loadPersistedActivity: false, preferencesRepository: repository)

        XCTAssertThrowsError(try store.addCustomCategory(title: String(repeating: "a", count: 201), icon: "folder"))
        XCTAssertThrowsError(try store.addCustomCategory(title: "Bad\nName", icon: "folder"))
        XCTAssertThrowsError(try store.addCustomCategory(title: "Receipts", icon: "not.a.real.symbol.name"))

        try store.addCustomCategory(title: "Receipts", icon: "receipt")
        let categoryID = try XCTUnwrap(store.preferences.customCategories.first?.id)
        XCTAssertThrowsError(
            try store.addCustomRule(
                categoryID: categoryID,
                matchKind: .contentContains,
                pattern: "receipt",
                target: .folders
            )
        )
    }

    @MainActor
    func testProductionActivityDoesNotIncludeSampleHistory() {
        let store = PrototypeStore(loadPersistedActivity: true, preferencesRepository: .temporary())

        XCTAssertFalse(store.activity.contains { $0.id == "downloads" })
    }

    @MainActor
    func testStorePreservesUnreadablePreferencesAndReportsFallback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortwellInvalidPreferencesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferencesURL = directory.appendingPathComponent("Preferences.json")
        try Data("not valid JSON".utf8).write(to: preferencesURL)

        let store = PrototypeStore(
            loadPersistedActivity: false,
            preferencesRepository: .init(fileURL: preferencesURL)
        )

        XCTAssertEqual(store.preferences, .defaults)
        XCTAssertTrue(store.showNoticeAlert)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferencesURL.path))
        let preservedFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("Preferences.invalid-") }
        XCTAssertEqual(preservedFiles.count, 1)
    }
}
