import CryptoKit
import Foundation
import XCTest
@testable import Sortwell

final class FunctionalSafetyTests: XCTestCase {
    func testScannerRejectsSelectedProjectRoot() async throws {
        let rootURL = try makeTemporaryDirectory()
        try write("{}", to: rootURL.appendingPathComponent("package.json"))
        try write("notes", to: rootURL.appendingPathComponent("README.md"))

        let scanner = FolderScanner()
        do {
            _ = try await scanner.scan(rootURL: rootURL) { _ in }
            XCTFail("Expected a selected project root to be rejected")
        } catch let error as FolderScanError {
            guard case .selectedRootIsProject = error else {
                return XCTFail("Unexpected scan error: \(error)")
            }
        }
    }

    func testScannerProtectsGitOnlyProjectFolder() async throws {
        let rootURL = try makeTemporaryDirectory()
        let projectURL = rootURL.appendingPathComponent("Repository", isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectURL.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try write("notes", to: projectURL.appendingPathComponent("README.md"))

        let result = try await FolderScanner().scan(rootURL: rootURL) { _ in }

        XCTAssertEqual(result.protectedProjects.map(\.name), ["Repository"])
        XCTAssertFalse(result.organisationItems.contains { $0.name == "Repository" })
        XCTAssertFalse(result.needsReviewItems.contains { $0.name == "Repository" })
    }

    func testScannerProtectsXcodeProjectFolder() async throws {
        let rootURL = try makeTemporaryDirectory()
        let projectURL = rootURL.appendingPathComponent("Mac App", isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectURL.appendingPathComponent("Sortwell.xcodeproj", isDirectory: true),
            withIntermediateDirectories: true
        )
        try write("source", to: projectURL.appendingPathComponent("App.swift"))

        let result = try await FolderScanner().scan(rootURL: rootURL) { _ in }

        XCTAssertEqual(result.protectedProjects.map(\.name), ["Mac App"])
    }

    func testScannerProtectsMarkerlessSourceTree() async throws {
        let rootURL = try makeTemporaryDirectory()
        let projectURL = rootURL.appendingPathComponent("Source Tree", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)
        try write("print(1)", to: projectURL.appendingPathComponent("main.swift"))
        try write("struct App {}", to: projectURL.appendingPathComponent("App.swift"))

        let result = try await FolderScanner().scan(rootURL: rootURL) { _ in }

        XCTAssertEqual(result.protectedProjects.map(\.name), ["Source Tree"])
        XCTAssertFalse(result.organisationItems.contains { $0.name == "Source Tree" })
    }

    func testScannerRejectsSelectedProjectBundle() async throws {
        let parentURL = try makeTemporaryDirectory()
        let projectURL = parentURL.appendingPathComponent("Sortwell.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try write("// project", to: projectURL.appendingPathComponent("project.pbxproj"))

        do {
            _ = try await FolderScanner().scan(rootURL: projectURL) { _ in }
            XCTFail("Expected the selected project bundle to be rejected")
        } catch let error as FolderScanError {
            guard case .selectedRootIsProject = error else {
                return XCTFail("Unexpected scan error: \(error)")
            }
        }
    }

    func testScannerFailsClosedWhenProjectInspectionLimitIsReached() async throws {
        let rootURL = try makeTemporaryDirectory()
        let largeFolderURL = rootURL.appendingPathComponent("Large Folder", isDirectory: true)
        for index in 0...100 {
            try FileManager.default.createDirectory(
                at: largeFolderURL.appendingPathComponent("Folder \(index)", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let result = try await FolderScanner().scan(rootURL: rootURL) { _ in }

        XCTAssertEqual(result.protectedProjects.map(\.name), ["Large Folder"])
        XCTAssertTrue(result.protectedProjects[0].reason.localizedCaseInsensitiveContains("could not be fully inspected"))
    }

    func testScannerMarksProjectDuplicateCopyProtected() async throws {
        let rootURL = try makeTemporaryDirectory()
        let projectURL = rootURL.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try write("{}", to: projectURL.appendingPathComponent("package.json"))
        try write("same bytes", to: projectURL.appendingPathComponent("data.txt"))
        try write("same bytes", to: rootURL.appendingPathComponent("loose.txt"))

        let scanner = FolderScanner()
        let result = try await scanner.scan(rootURL: rootURL) { _ in }

        XCTAssertEqual(result.protectedProjects.count, 1)
        let duplicateGroup = try XCTUnwrap(result.duplicateGroups.first)
        XCTAssertEqual(duplicateGroup.copies.count, 2)
        XCTAssertTrue(duplicateGroup.copies.contains { $0.name == "data.txt" && $0.isProtected })
        XCTAssertTrue(duplicateGroup.copies.contains { $0.name == "loose.txt" && !$0.isProtected })
    }

    func testScannerExcludesTopLevelSymbolicLinks() async throws {
        let rootURL = try makeTemporaryDirectory()
        let outsideURL = try makeTemporaryDirectory().appendingPathComponent("outside.txt")
        try write("outside", to: outsideURL)
        try FileManager.default.createSymbolicLink(
            at: rootURL.appendingPathComponent("linked.txt"),
            withDestinationURL: outsideURL
        )
        try write("inside", to: rootURL.appendingPathComponent("inside.txt"))

        let result = try await FolderScanner().scan(rootURL: rootURL) { _ in }

        XCTAssertFalse(result.organisationItems.contains { $0.name == "linked.txt" })
        XCTAssertFalse(result.needsReviewItems.contains { $0.name == "linked.txt" })
        XCTAssertEqual(result.scannedFileCount, 1)
    }

    func testScannerExcludesTopLevelSymbolicDirectories() async throws {
        let rootURL = try makeTemporaryDirectory()
        let outsideURL = try makeTemporaryDirectory()
        try write("outside", to: outsideURL.appendingPathComponent("invoice.pdf"))
        try FileManager.default.createSymbolicLink(
            at: rootURL.appendingPathComponent("Linked Folder"),
            withDestinationURL: outsideURL
        )

        let result = try await FolderScanner().scan(rootURL: rootURL) { _ in }

        XCTAssertFalse(result.organisationItems.contains { $0.name == "Linked Folder" })
        XCTAssertFalse(result.needsReviewItems.contains { $0.name == "Linked Folder" })
        XCTAssertEqual(result.scannedFileCount, 0)
    }

    func testScannerDetectsEmptyFileDuplicates() async throws {
        let rootURL = try makeTemporaryDirectory()
        try Data().write(to: rootURL.appendingPathComponent("empty-a.txt"))
        try Data().write(to: rootURL.appendingPathComponent("empty-b.txt"))

        let result = try await FolderScanner().scan(rootURL: rootURL) { _ in }

        let group = try XCTUnwrap(result.duplicateGroups.first)
        XCTAssertEqual(group.copies.map(\.name), ["empty-a.txt", "empty-b.txt"])
        XCTAssertEqual(group.copies.map(\.size), [0, 0])
    }

    func testExecutorMovesWithoutOverwritingAndUndoRestores() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sourceURL = rootURL.appendingPathComponent("record.pdf")
        let existingDestinationFolder = rootURL
            .appendingPathComponent("Organised Files", isDirectory: true)
            .appendingPathComponent("Other Documents", isDirectory: true)
        let existingDestinationURL = existingDestinationFolder.appendingPathComponent("record.pdf")
        let expectedDestinationURL = existingDestinationFolder.appendingPathComponent("record 2.pdf")
        try FileManager.default.createDirectory(at: existingDestinationFolder, withIntermediateDirectories: true)
        try write("original", to: sourceURL)
        try write("already there", to: existingDestinationURL)

        let journalDirectory = rootURL.appendingPathComponent("Journals", isDirectory: true)
        let executor = FileOperationExecutor(journalDirectory: journalDirectory)
        let sourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let sourceSnapshot = FileStateSnapshot(
            size: Int64(sourceValues.fileSize ?? 0),
            modificationDate: sourceValues.contentModificationDate
        )
        let plan = FileOperationPlan(
            id: "move-test",
            rootURL: rootURL,
            rootBookmarkData: nil,
            moveOperations: [
                .init(
                    id: "record",
                    sourceURL: sourceURL,
                    category: "Other Documents",
                    expectedSnapshot: sourceSnapshot
                )
            ],
            trashOperations: []
        )

        let journal = try await executor.apply(plan) { _ in }

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingDestinationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDestinationURL.path))
        XCTAssertEqual(journal.moveCount, 1)
        XCTAssertEqual(journal.trashCount, 0)

        let journalPath = try XCTUnwrap(journal.journalPath)
        _ = try await executor.undo(journalURL: URL(fileURLWithPath: journalPath)) { _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingDestinationURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedDestinationURL.path))
    }

    func testExecutorRefusesChangedDuplicateBeforeTrash() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sourceURL = rootURL.appendingPathComponent("duplicate.txt")
        try write("original duplicate", to: sourceURL)
        let expectedSnapshot = try snapshot(sourceURL)
        let expectedHash = sha256("original duplicate")
        try write("unique replacement", to: sourceURL)

        let executor = FileOperationExecutor(journalDirectory: rootURL.appendingPathComponent("Journals", isDirectory: true))
        let plan = FileOperationPlan(
            id: "stale-trash-test",
            rootURL: rootURL,
            rootBookmarkData: nil,
            moveOperations: [],
            trashOperations: [
                .init(
                    id: "duplicate",
                    sourceURL: sourceURL,
                    expectedSnapshot: expectedSnapshot,
                    expectedSHA256: expectedHash
                )
            ]
        )

        do {
            _ = try await executor.apply(plan) { _ in }
            XCTFail("Expected stale duplicate validation to stop Apply")
        } catch let error as FileOperationError {
            guard case .partialApply(let journal, _) = error else {
                return XCTFail("Unexpected operation error: \(error)")
            }
            XCTAssertEqual(journal.trashCount, 0)
        }
        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "unique replacement")
    }

    func testExecutorRefusesTopLevelSymbolicLink() async throws {
        let rootURL = try makeTemporaryDirectory()
        let outsideURL = try makeTemporaryDirectory().appendingPathComponent("outside.txt")
        let symbolicLinkURL = rootURL.appendingPathComponent("linked.txt")
        try write("outside", to: outsideURL)
        try FileManager.default.createSymbolicLink(at: symbolicLinkURL, withDestinationURL: outsideURL)
        let plan = FileOperationPlan(
            id: "symbolic-link-test",
            rootURL: rootURL,
            rootBookmarkData: nil,
            moveOperations: [
                .init(
                    id: "linked",
                    sourceURL: symbolicLinkURL,
                    category: "Other Documents",
                    expectedSnapshot: .init(size: 7, modificationDate: nil)
                )
            ],
            trashOperations: []
        )

        do {
            _ = try await FileOperationExecutor(journalDirectory: rootURL.appendingPathComponent("Journals"))
                .apply(plan) { _ in }
            XCTFail("Expected Apply to reject a symbolic link")
        } catch let error as FileOperationError {
            guard case .partialApply(let journal, _) = error else {
                return XCTFail("Unexpected operation error: \(error)")
            }
            XCTAssertTrue(journal.entries.isEmpty)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: symbolicLinkURL.path))
        XCTAssertEqual(try String(contentsOf: outsideURL, encoding: .utf8), "outside")
    }

    func testExecutorRefusesSymbolicOrganisedFilesDirectory() async throws {
        let rootURL = try makeTemporaryDirectory()
        let outsideURL = try makeTemporaryDirectory()
        let sourceURL = rootURL.appendingPathComponent("record.txt")
        try write("record", to: sourceURL)
        try FileManager.default.createSymbolicLink(
            at: rootURL.appendingPathComponent("Organised Files"),
            withDestinationURL: outsideURL
        )
        let executor = FileOperationExecutor(journalDirectory: rootURL.appendingPathComponent("Journals"))

        do {
            _ = try await executor.apply(movePlan(id: "symbolic-output-test", rootURL: rootURL, sources: [sourceURL])) { _ in }
            XCTFail("Expected Apply to reject a symbolic Organised Files directory")
        } catch let error as FileOperationError {
            guard case .partialApply(let journal, _) = error else {
                return XCTFail("Unexpected operation error: \(error)")
            }
            XCTAssertTrue(journal.entries.isEmpty)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outsideURL.path).isEmpty)
    }

    func testExecutorRefusesSymbolicCategoryDirectory() async throws {
        let rootURL = try makeTemporaryDirectory()
        let outsideURL = try makeTemporaryDirectory()
        let organisedURL = rootURL.appendingPathComponent("Organised Files", isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("record.txt")
        try FileManager.default.createDirectory(at: organisedURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: organisedURL.appendingPathComponent("Other Documents"),
            withDestinationURL: outsideURL
        )
        try write("record", to: sourceURL)
        let executor = FileOperationExecutor(journalDirectory: rootURL.appendingPathComponent("Journals"))

        do {
            _ = try await executor.apply(movePlan(id: "symbolic-category-test", rootURL: rootURL, sources: [sourceURL])) { _ in }
            XCTFail("Expected Apply to reject a symbolic category directory")
        } catch let error as FileOperationError {
            guard case .partialApply(let journal, _) = error else {
                return XCTFail("Unexpected operation error: \(error)")
            }
            XCTAssertTrue(journal.entries.isEmpty)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outsideURL.path).isEmpty)
    }

    func testApplyPreflightPreventsEarlierTrashWhenLaterCategoryIsInvalid() async throws {
        let rootURL = try makeTemporaryDirectory()
        let duplicateURL = rootURL.appendingPathComponent("duplicate.txt")
        let moveURL = rootURL.appendingPathComponent("move.txt")
        try write("duplicate", to: duplicateURL)
        try write("move", to: moveURL)
        let plan = FileOperationPlan(
            id: "preflight-test",
            rootURL: rootURL,
            rootBookmarkData: nil,
            moveOperations: [
                .init(id: "move", sourceURL: moveURL, category: "../Unsafe", expectedSnapshot: try snapshot(moveURL))
            ],
            trashOperations: [
                .init(
                    id: "duplicate",
                    sourceURL: duplicateURL,
                    expectedSnapshot: try snapshot(duplicateURL),
                    expectedSHA256: sha256("duplicate")
                )
            ]
        )

        do {
            _ = try await FileOperationExecutor(journalDirectory: rootURL.appendingPathComponent("Journals", isDirectory: true))
                .apply(plan) { _ in }
            XCTFail("Expected invalid category preflight to stop Apply")
        } catch let error as FileOperationError {
            guard case .partialApply(let journal, _) = error else {
                return XCTFail("Unexpected operation error: \(error)")
            }
            XCTAssertTrue(journal.entries.isEmpty)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moveURL.path))
    }

    func testScannerHandlesLargeEqualSizedCohort() async throws {
        let rootURL = try makeTemporaryDirectory()
        for index in 0..<300 {
            try write(String(format: "item-%04d", index), to: rootURL.appendingPathComponent("item-\(index).txt"))
        }

        let result = try await FolderScanner().scan(rootURL: rootURL) { _ in }

        XCTAssertEqual(result.scannedFileCount, 300)
        XCTAssertEqual(result.organisationItems.count, 300)
        XCTAssertTrue(result.duplicateGroups.isEmpty)
    }

    func testExecutorStopsBeforeStartingNextItem() async throws {
        let rootURL = try makeTemporaryDirectory()
        let firstURL = rootURL.appendingPathComponent("first.txt")
        let secondURL = rootURL.appendingPathComponent("second.txt")
        try write("first", to: firstURL)
        try write("second", to: secondURL)
        let state = ApplyStopTestState()
        let executor = FileOperationExecutor(journalDirectory: rootURL.appendingPathComponent("Journals", isDirectory: true))

        do {
            _ = try await executor.apply(
                movePlan(id: "stop-after-current-test", rootURL: rootURL, sources: [firstURL, secondURL]),
                shouldStop: { await state.shouldStop }
            ) { _ in
                await state.requestStop()
            }
            XCTFail("Expected Apply to stop before the second item")
        } catch let error as FileOperationError {
            guard case .partialApply(let journal, let reason) = error else {
                return XCTFail("Unexpected operation error: \(error)")
            }
            XCTAssertEqual(reason, FileOperationError.userStopped.localizedDescription)
            XCTAssertEqual(journal.moveCount, 1)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testUndoRefusesReplacementAtDestination() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sourceURL = rootURL.appendingPathComponent("record.txt")
        try write("approved content", to: sourceURL)
        let executor = FileOperationExecutor(journalDirectory: rootURL.appendingPathComponent("Journals", isDirectory: true))
        let journal = try await executor.apply(
            movePlan(id: "replacement-test", rootURL: rootURL, sources: [sourceURL])
        ) { _ in }
        let destinationPath = try XCTUnwrap(journal.entries.first?.destinationPath)
        let destinationURL = URL(fileURLWithPath: destinationPath)
        try FileManager.default.removeItem(at: destinationURL)
        try write("unrelated replacement", to: destinationURL)

        do {
            _ = try await executor.undo(journalURL: URL(fileURLWithPath: try XCTUnwrap(journal.journalPath))) { _ in }
            XCTFail("Expected Undo to reject the replacement")
        } catch let error as FileOperationError {
            guard case .destinationChanged = error else {
                return XCTFail("Unexpected undo error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(try String(contentsOf: destinationURL, encoding: .utf8), "unrelated replacement")
    }

    func testPartialUndoCanResumeAfterConflictIsRemoved() async throws {
        let rootURL = try makeTemporaryDirectory()
        let firstURL = rootURL.appendingPathComponent("first.txt")
        let secondURL = rootURL.appendingPathComponent("second.txt")
        try write("first", to: firstURL)
        try write("second", to: secondURL)
        let executor = FileOperationExecutor(journalDirectory: rootURL.appendingPathComponent("Journals", isDirectory: true))
        let journal = try await executor.apply(
            movePlan(id: "resume-undo-test", rootURL: rootURL, sources: [firstURL, secondURL])
        ) { _ in }
        let journalURL = URL(fileURLWithPath: try XCTUnwrap(journal.journalPath))
        try write("conflict", to: firstURL)

        do {
            _ = try await executor.undo(journalURL: journalURL) { _ in }
            XCTFail("Expected the first undo attempt to stop at the conflict")
        } catch let error as FileOperationError {
            guard case .restoreConflict = error else {
                return XCTFail("Unexpected undo error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        try FileManager.default.removeItem(at: firstURL)

        let completedJournal = try await executor.undo(journalURL: journalURL) { _ in }

        XCTAssertNotNil(completedJournal.undoneAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertTrue(completedJournal.entries.allSatisfy { $0.status == .undone })
    }

    func testUndoUsesRecoveryCopyWhenTrashDestinationWasNotRecorded() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sourceURL = rootURL.appendingPathComponent("duplicate.txt")
        let recoveryURL = rootURL.appendingPathComponent("recovery-copy.txt")
        try write("recoverable", to: recoveryURL)
        let journalURL = rootURL.appendingPathComponent("interrupted.json")
        let journal = OperationJournal(
            id: "interrupted-trash",
            rootPath: rootURL.path,
            rootBookmarkData: nil,
            createdAt: Date(),
            completedAt: nil,
            undoneAt: nil,
            journalPath: journalURL.path,
            failureDescription: "Interrupted after Trash",
            entries: [
                .init(
                    id: "duplicate",
                    action: .trash,
                    sourcePath: sourceURL.path,
                    destinationPath: nil,
                    destinationBookmarkData: nil,
                    recoveryPath: recoveryURL.path,
                    snapshot: try snapshot(recoveryURL),
                    contentSHA256: sha256("recoverable"),
                    modificationDateTolerance: 0.01,
                    status: .planned
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(journal).write(to: journalURL, options: .atomic)

        let restored = try await FileOperationExecutor().undo(journalURL: journalURL) { _ in }

        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "recoverable")
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL.path))
        XCTAssertEqual(restored.entries.first?.status, .undone)
    }

    func testUndoRecoversCheckpointAfterItemWasRestoredButJournalWriteWasInterrupted() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sourceURL = rootURL.appendingPathComponent("restored.txt")
        let missingDestinationURL = rootURL.appendingPathComponent("Organised Files/Other Documents/restored.txt")
        let recoveryURL = rootURL.appendingPathComponent("recovery-link.txt")
        try write("restored content", to: sourceURL)
        try FileManager.default.linkItem(at: sourceURL, to: recoveryURL)
        let journalURL = rootURL.appendingPathComponent("restore-interrupted.json")
        let journal = OperationJournal(
            id: "restore-interrupted",
            rootPath: rootURL.path,
            rootBookmarkData: nil,
            createdAt: Date(),
            completedAt: Date(),
            undoneAt: nil,
            journalPath: journalURL.path,
            failureDescription: nil,
            entries: [
                .init(
                    id: "restored",
                    action: .move,
                    sourcePath: sourceURL.path,
                    destinationPath: missingDestinationURL.path,
                    destinationBookmarkData: nil,
                    recoveryPath: recoveryURL.path,
                    snapshot: try snapshot(sourceURL),
                    contentSHA256: sha256("restored content"),
                    modificationDateTolerance: 0.01,
                    status: .completed
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(journal).write(to: journalURL, options: .atomic)

        let resumed = try await FileOperationExecutor().undo(journalURL: journalURL) { _ in }

        XCTAssertEqual(resumed.entries.first?.status, .undone)
        XCTAssertNotNil(resumed.undoneAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL.path))
    }

    func testUndoMigratesLegacyJournalSchema() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sourceURL = rootURL.appendingPathComponent("legacy.txt")
        let destinationURL = rootURL.appendingPathComponent("Organised Files/Other Documents/legacy.txt")
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("legacy", to: destinationURL)
        let journalURL = rootURL.appendingPathComponent("legacy.json")
        let journal = LegacyJournalFixture(
            id: "legacy-session",
            rootPath: rootURL.path,
            createdAt: Date(),
            completedAt: Date(),
            undoneAt: nil,
            journalPath: journalURL.path,
            entries: [
                .init(
                    id: "legacy",
                    action: .move,
                    sourcePath: sourceURL.path,
                    destinationPath: destinationURL.path,
                    snapshot: try snapshot(destinationURL)
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(journal).write(to: journalURL, options: .atomic)

        let restored = try await FileOperationExecutor().undo(journalURL: journalURL) { _ in }

        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "legacy")
        XCTAssertNotNil(restored.undoneAt)
    }

    func testUndoMigratesAccessibleLegacyTrashEntry() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sourceURL = rootURL.appendingPathComponent("legacy-trash.txt")
        let destinationURL = rootURL.appendingPathComponent("Legacy Trash/legacy-trash.txt")
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("legacy trash", to: destinationURL)
        let journalURL = rootURL.appendingPathComponent("legacy-trash.json")
        let journal = LegacyJournalFixture(
            id: "legacy-trash-session",
            rootPath: rootURL.path,
            createdAt: Date(),
            completedAt: Date(),
            undoneAt: nil,
            journalPath: journalURL.path,
            entries: [
                .init(
                    id: "legacy-trash",
                    action: .trash,
                    sourcePath: sourceURL.path,
                    destinationPath: destinationURL.path,
                    snapshot: try snapshot(destinationURL)
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(journal).write(to: journalURL, options: .atomic)

        _ = try await FileOperationExecutor().undo(journalURL: journalURL) { _ in }

        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "legacy trash")
    }

    func testRecoveryPruningRemovesOnlyExpiredCompletedSessions() async throws {
        let rootURL = try makeTemporaryDirectory()
        let journalDirectory = rootURL.appendingPathComponent("Journals", isDirectory: true)
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        let now = Date()
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -40, to: now))

        let expiredRecoveryURL = try makeRecoveryFile(sessionID: "expired", rootURL: rootURL)
        let recentRecoveryURL = try makeRecoveryFile(sessionID: "recent", rootURL: rootURL)
        let interruptedRecoveryURL = try makeRecoveryFile(sessionID: "interrupted", rootURL: rootURL)
        try writeJournal(
            recoveryJournal(id: "expired", rootURL: rootURL, recoveryURL: expiredRecoveryURL, createdAt: oldDate, completedAt: oldDate),
            to: journalDirectory.appendingPathComponent("expired.json")
        )
        try writeJournal(
            recoveryJournal(id: "recent", rootURL: rootURL, recoveryURL: recentRecoveryURL, createdAt: now, completedAt: now),
            to: journalDirectory.appendingPathComponent("recent.json")
        )
        try writeJournal(
            recoveryJournal(
                id: "interrupted",
                rootURL: rootURL,
                recoveryURL: interruptedRecoveryURL,
                createdAt: oldDate,
                completedAt: nil,
                failureDescription: "Interrupted"
            ),
            to: journalDirectory.appendingPathComponent("interrupted.json")
        )

        let removed = try await FileOperationExecutor(journalDirectory: journalDirectory)
            .pruneExpiredRecovery(retentionDays: 30, now: now)

        XCTAssertEqual(removed, ["expired"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredRecoveryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalDirectory.appendingPathComponent("expired.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentRecoveryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalDirectory.appendingPathComponent("recent.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: interruptedRecoveryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalDirectory.appendingPathComponent("interrupted.json").path))
    }

    func testRecoveryPruningDoesNotTrustRecordedJournalPath() async throws {
        let rootURL = try makeTemporaryDirectory()
        let journalDirectory = rootURL.appendingPathComponent("Journals", isDirectory: true)
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        let outsideURL = rootURL.appendingPathComponent("keep.txt")
        try write("keep", to: outsideURL)
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -40, to: Date()))
        let journal = OperationJournal(
            id: "safe-id",
            rootPath: rootURL.path,
            rootBookmarkData: nil,
            createdAt: oldDate,
            completedAt: oldDate,
            undoneAt: nil,
            journalPath: outsideURL.path,
            failureDescription: nil,
            entries: []
        )
        let storedJournalURL = journalDirectory.appendingPathComponent("safe-id.json")
        try writeJournal(journal, to: storedJournalURL)

        _ = try await FileOperationExecutor(journalDirectory: journalDirectory)
            .pruneExpiredRecovery(retentionDays: 30)

        XCTAssertEqual(try String(contentsOf: outsideURL, encoding: .utf8), "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedJournalURL.path))
    }

    func testJournalLoadReportCountsUnreadableFiles() throws {
        let rootURL = try makeTemporaryDirectory()
        let journalDirectory = rootURL.appendingPathComponent("Journals", isDirectory: true)
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        let validJournal = OperationJournal(
            id: "valid",
            rootPath: rootURL.path,
            rootBookmarkData: nil,
            createdAt: Date(),
            completedAt: Date(),
            undoneAt: nil,
            journalPath: journalDirectory.appendingPathComponent("valid.json").path,
            failureDescription: nil,
            entries: []
        )
        try writeJournal(validJournal, to: journalDirectory.appendingPathComponent("valid.json"))
        try write("not valid JSON", to: journalDirectory.appendingPathComponent("broken.json"))
        try write("ignored", to: journalDirectory.appendingPathComponent("notes.txt"))

        let report = FileOperationExecutor.loadJournalReport(from: journalDirectory)

        XCTAssertEqual(report.journals.map(\.id), ["valid"])
        XCTAssertEqual(report.unreadableCount, 1)
        XCTAssertFalse(report.directoryReadFailed)
    }

    func testJournalLoadReportIdentifiesInaccessibleDirectory() throws {
        let rootURL = try makeTemporaryDirectory()
        let fileURL = rootURL.appendingPathComponent("not-a-directory")
        try write("file", to: fileURL)

        let report = FileOperationExecutor.loadJournalReport(from: fileURL)

        XCTAssertTrue(report.journals.isEmpty)
        XCTAssertTrue(report.directoryReadFailed)
    }

    func testUndoReportsUnresolvableRootBookmarkAsUnavailable() async throws {
        let rootURL = try makeTemporaryDirectory()
        let journalURL = rootURL.appendingPathComponent("invalid-bookmark.json")
        try writeJournal(
            OperationJournal(
                id: "invalid-bookmark",
                rootPath: rootURL.path,
                rootBookmarkData: Data("not a bookmark".utf8),
                createdAt: Date(),
                completedAt: Date(),
                undoneAt: nil,
                journalPath: journalURL.path,
                failureDescription: nil,
                entries: []
            ),
            to: journalURL
        )

        do {
            _ = try await FileOperationExecutor().undo(journalURL: journalURL) { _ in }
            XCTFail("Expected an invalid root bookmark to require reauthorization")
        } catch let error as FileOperationError {
            guard case .bookmarkUnavailable(let path) = error else {
                return XCTFail("Unexpected bookmark error: \(error)")
            }
            XCTAssertEqual(path, rootURL.path)
        }
    }

    func testRootReauthorizationRejectsDifferentFolder() async throws {
        let rootURL = try makeTemporaryDirectory()
        let otherURL = try makeTemporaryDirectory()
        let journalURL = rootURL.appendingPathComponent("session.json")
        try writeJournal(
            OperationJournal(
                id: "session",
                rootPath: rootURL.path,
                rootBookmarkData: nil,
                createdAt: Date(),
                completedAt: Date(),
                undoneAt: nil,
                journalPath: journalURL.path,
                failureDescription: nil,
                entries: []
            ),
            to: journalURL
        )

        do {
            try await FileOperationExecutor().reauthorizeRoot(
                journalURL: journalURL,
                rootURL: otherURL,
                bookmarkData: Data()
            )
            XCTFail("Expected reauthorization to reject a different folder")
        } catch let error as FileOperationError {
            guard case .unsafeSource = error else {
                return XCTFail("Unexpected reauthorization error: \(error)")
            }
        }
    }

    @MainActor
    func testRealModeCannotJumpDirectlyToApply() throws {
        let store = PrototypeStore(loadPersistedActivity: false)
        store.scanMode = .real(try makeTemporaryDirectory())
        store.route = .review

        store.jump(to: .applying)

        XCTAssertEqual(store.route, .review)
        XCTAssertTrue(store.showNoticeAlert)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortwellTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func write(_ value: String, to url: URL) throws {
        try Data(value.utf8).write(to: url, options: [.atomic])
    }

    private func makeRecoveryFile(sessionID: String, rootURL: URL) throws -> URL {
        let url = rootURL
            .appendingPathComponent("Organised Files/.Sortwell Recovery", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("copy.txt")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(sessionID, to: url)
        return url
    }

    private func recoveryJournal(
        id: String,
        rootURL: URL,
        recoveryURL: URL,
        createdAt: Date,
        completedAt: Date?,
        failureDescription: String? = nil
    ) throws -> OperationJournal {
        OperationJournal(
            id: id,
            rootPath: rootURL.path,
            rootBookmarkData: nil,
            createdAt: createdAt,
            completedAt: completedAt,
            undoneAt: nil,
            journalPath: nil,
            failureDescription: failureDescription,
            entries: [
                .init(
                    id: "copy",
                    action: .trash,
                    sourcePath: rootURL.appendingPathComponent("copy.txt").path,
                    destinationPath: nil,
                    destinationBookmarkData: nil,
                    recoveryPath: recoveryURL.path,
                    snapshot: try snapshot(recoveryURL),
                    contentSHA256: nil,
                    modificationDateTolerance: 0.01,
                    status: .completed
                )
            ]
        )
    }

    private func writeJournal(_ journal: OperationJournal, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(journal).write(to: url, options: .atomic)
    }

    private func snapshot(_ url: URL) throws -> FileStateSnapshot {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return .init(size: Int64(values.fileSize ?? 0), modificationDate: values.contentModificationDate)
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func movePlan(id: String, rootURL: URL, sources: [URL]) throws -> FileOperationPlan {
        try .init(
            id: id,
            rootURL: rootURL,
            rootBookmarkData: nil,
            moveOperations: sources.map { source in
                .init(
                    id: source.lastPathComponent,
                    sourceURL: source,
                    category: "Other Documents",
                    expectedSnapshot: try snapshot(source)
                )
            },
            trashOperations: []
        )
    }
}

private actor ApplyStopTestState {
    private(set) var shouldStop = false

    func requestStop() {
        shouldStop = true
    }
}

private struct LegacyJournalFixture: Encodable {
    let id: String
    let rootPath: String
    let createdAt: Date
    let completedAt: Date?
    let undoneAt: Date?
    let journalPath: String?
    let entries: [LegacyJournalEntryFixture]
}

private struct LegacyJournalEntryFixture: Encodable {
    let id: String
    let action: JournalActionKind
    let sourcePath: String
    let destinationPath: String
    let snapshot: FileStateSnapshot
}
