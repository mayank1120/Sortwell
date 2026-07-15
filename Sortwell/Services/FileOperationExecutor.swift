import CryptoKit
import Foundation

enum FileOperationError: LocalizedError, Sendable {
    case sourceMissing(String)
    case unsafeSource(String)
    case sourceChanged(String)
    case destinationChanged(String)
    case missingTrashResult(String)
    case restoreConflict(String)
    case unresolvedOperation(String)
    case bookmarkUnavailable(String)
    case invalidCategory(String)
    case userStopped
    case partialApply(OperationJournal, String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            "The source item is no longer available: \(path)"
        case .unsafeSource(let path):
            "Sortwell refused to change an item outside the approved scan boundary: \(path)"
        case .sourceChanged(let path):
            "The item changed after review and was left untouched: \(path)"
        case .destinationChanged(let path):
            "Undo stopped because the organised or trashed item no longer matches the recorded item: \(path)"
        case .missingTrashResult(let path):
            "macOS moved an item to Trash but did not return a restorable location: \(path)"
        case .restoreConflict(let path):
            "Undo cannot restore an item because another item already exists at: \(path)"
        case .unresolvedOperation(let path):
            "Sortwell recorded an interrupted operation that requires manual review: \(path)"
        case .bookmarkUnavailable(let path):
            "Sortwell could not regain secure access required for Undo: \(path)"
        case .invalidCategory(let category):
            "Sortwell refused an invalid destination category: \(category)"
        case .userStopped:
            "Stopped after the current item."
        case .partialApply(_, let reason):
            "Apply stopped after some work may have completed: \(reason)"
        }
    }
}

actor FileOperationExecutor {
    typealias ProgressHandler = @Sendable (FileOperationProgress) async -> Void
    typealias StopHandler = @Sendable () async -> Bool

    private let fileManager: FileManager
    private let journalDirectory: URL?

    init(fileManager: FileManager = .default, journalDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.journalDirectory = journalDirectory
    }

    nonisolated static func loadPersistedJournals(fileManager: FileManager = .default) -> [OperationJournal] {
        OperationJournalStore.loadAll(fileManager: fileManager)
    }

    nonisolated static func loadJournal(at url: URL) throws -> OperationJournal {
        try OperationJournalStore.read(from: url)
    }

    func pruneExpiredRecovery(retentionDays: Int, now: Date = .now) throws -> Set<String> {
        let directory = try journalDirectory ?? OperationJournalStore.defaultDirectory(fileManager: fileManager)
        let journals = OperationJournalStore.loadAll(from: directory, fileManager: fileManager)
        let cutoff = Calendar.current.date(byAdding: .day, value: -min(max(retentionDays, 1), 365), to: now) ?? now
        let standardDirectory = directory.standardizedFileURL
        var removed: Set<String> = []

        for journal in journals {
            guard journal.completedAt != nil,
                  journal.failureDescription == nil,
                  (journal.undoneAt ?? journal.completedAt ?? journal.createdAt) < cutoff else { continue }
            let rootURL = try resolveURL(path: journal.rootPath, bookmarkData: journal.rootBookmarkData)
            let accessed = rootURL.startAccessingSecurityScopedResource()
            if journal.rootBookmarkData != nil, !accessed { continue }
            defer { if accessed { rootURL.stopAccessingSecurityScopedResource() } }

            let recoveryRootURL = rootURL
                .appendingPathComponent("Organised Files", isDirectory: true)
                .appendingPathComponent(".Sortwell Recovery", isDirectory: true)
                .standardizedFileURL
            let expectedRecoveryURL = recoveryRootURL
                .appendingPathComponent(journal.id, isDirectory: true)
                .standardizedFileURL
            guard expectedRecoveryURL.deletingLastPathComponent() == recoveryRootURL else { continue }
            let recoveryPathsAreSafe = journal.entries.compactMap(\.recoveryPath).allSatisfy {
                URL(fileURLWithPath: $0).standardizedFileURL.path.hasPrefix(expectedRecoveryURL.path + "/")
            }
            guard recoveryPathsAreSafe else { continue }
            if fileManager.fileExists(atPath: expectedRecoveryURL.path) {
                try fileManager.removeItem(at: expectedRecoveryURL)
            }
            let journalURL = standardDirectory
                .appendingPathComponent("\(journal.id).json")
                .standardizedFileURL
            guard journalURL.deletingLastPathComponent() == standardDirectory else { continue }
            try fileManager.removeItem(at: journalURL)
            removed.insert(journal.id)
        }
        return removed
    }

    func apply(
        _ plan: FileOperationPlan,
        shouldStop: @escaping StopHandler = { false },
        progress: @escaping ProgressHandler
    ) async throws -> OperationJournal {
        let journalURL = try makeJournalURL(for: plan.id)
        var journal = OperationJournal(
            id: plan.id,
            rootPath: plan.rootURL.path,
            rootBookmarkData: plan.rootBookmarkData,
            createdAt: Date(),
            completedAt: nil,
            undoneAt: nil,
            journalPath: journalURL.path,
            failureDescription: nil,
            entries: []
        )
        try write(journal, to: journalURL)

        do {
            try preflight(plan)
            let total = plan.totalOperationCount
            var completed = 0

            for operation in plan.trashOperations {
                if await shouldStop() { throw FileOperationError.userStopped }
                try Task.checkCancellation()
                try validateSource(operation.sourceURL, isInside: plan.rootURL)
                try validateExpectedState(
                    operation.sourceURL,
                    snapshot: operation.expectedSnapshot,
                    sha256: operation.expectedSHA256
                )

                let currentSnapshot = try snapshot(for: operation.sourceURL)
                let currentHash = try sha256IfRegularFile(operation.sourceURL)
                let recoveryURL = try createRecoveryCopy(
                    for: operation.sourceURL,
                    rootURL: plan.rootURL,
                    sessionID: plan.id,
                    operationID: operation.id
                )
                journal.entries.append(
                    .init(
                        id: operation.id,
                        action: .trash,
                        sourcePath: operation.sourceURL.path,
                        destinationPath: nil,
                        destinationBookmarkData: nil,
                        recoveryPath: recoveryURL.path,
                        snapshot: currentSnapshot,
                        contentSHA256: currentHash,
                        modificationDateTolerance: 0.01,
                        status: .planned
                    )
                )
                let entryIndex = journal.entries.count - 1
                try write(journal, to: journalURL)

                var trashedURL: NSURL?
                try fileManager.trashItem(at: operation.sourceURL, resultingItemURL: &trashedURL)
                guard let destinationURL = trashedURL as URL? else {
                    throw FileOperationError.missingTrashResult(operation.sourceURL.path)
                }
                journal.entries[entryIndex].destinationPath = destinationURL.path
                journal.entries[entryIndex].destinationBookmarkData = try makeSecurityBookmark(for: destinationURL)
                journal.entries[entryIndex].status = .completed
                completed += 1
                try write(journal, to: journalURL)
                await progress(.init(completed: completed, total: total, currentAction: "Moved \(operation.sourceURL.lastPathComponent) to Trash"))
            }

            let organisedRoot = plan.rootURL.appendingPathComponent("Organised Files", isDirectory: true)
            for operation in plan.moveOperations {
                if await shouldStop() { throw FileOperationError.userStopped }
                try Task.checkCancellation()
                try validateTopLevelSource(operation.sourceURL, root: plan.rootURL)
                try validateExpectedState(operation.sourceURL, snapshot: operation.expectedSnapshot, sha256: nil)

                let currentSnapshot = try snapshot(for: operation.sourceURL)
                let currentHash = try sha256IfRegularFile(operation.sourceURL)
                let categoryURL = organisedRoot.appendingPathComponent(try categoryFolderName(operation.category), isDirectory: true)
                try fileManager.createDirectory(at: categoryURL, withIntermediateDirectories: true)
                let destinationURL = availableDestinationURL(for: operation.sourceURL, in: categoryURL)
                journal.entries.append(
                    .init(
                        id: operation.id,
                        action: .move,
                        sourcePath: operation.sourceURL.path,
                        destinationPath: destinationURL.path,
                        destinationBookmarkData: nil,
                        recoveryPath: nil,
                        snapshot: currentSnapshot,
                        contentSHA256: currentHash,
                        modificationDateTolerance: 0.01,
                        status: .planned
                    )
                )
                let entryIndex = journal.entries.count - 1
                try write(journal, to: journalURL)

                try fileManager.moveItem(at: operation.sourceURL, to: destinationURL)
                journal.entries[entryIndex].status = .completed
                completed += 1
                try write(journal, to: journalURL)
                await progress(.init(completed: completed, total: total, currentAction: "Moved \(operation.sourceURL.lastPathComponent)"))
            }

            journal.completedAt = Date()
            try write(journal, to: journalURL)
            await progress(.init(completed: plan.totalOperationCount, total: plan.totalOperationCount, currentAction: "Recorded undo journal"))
            return journal
        } catch {
            journal.failureDescription = error.localizedDescription
            try? write(journal, to: journalURL)
            throw FileOperationError.partialApply(journal, error.localizedDescription)
        }
    }

    func undo(journalURL: URL, progress: @escaping ProgressHandler) async throws -> OperationJournal {
        var journal = try readJournal(from: journalURL)
        let rootURL = try resolveURL(path: journal.rootPath, bookmarkData: journal.rootBookmarkData)
        let rootAccessed = rootURL.startAccessingSecurityScopedResource()
        if journal.rootBookmarkData != nil, !rootAccessed {
            throw FileOperationError.bookmarkUnavailable(journal.rootPath)
        }
        defer {
            if rootAccessed { rootURL.stopAccessingSecurityScopedResource() }
        }

        let total = journal.entries.filter { $0.status != .notApplied }.count
        var completed = journal.entries.filter { $0.status == .undone }.count

        for index in journal.entries.indices.reversed() {
            try Task.checkCancellation()
            if journal.entries[index].status == .undone {
                if let recoveryPath = journal.entries[index].recoveryPath {
                    try? fileManager.removeItem(at: URL(fileURLWithPath: recoveryPath))
                }
                continue
            }
            if journal.entries[index].status == .notApplied { continue }

            let entry = journal.entries[index]
            let sourceURL = URL(fileURLWithPath: entry.sourcePath)
            let sourceExists = fileManager.fileExists(atPath: sourceURL.path)
            let recoveryURL = entry.recoveryPath.map(URL.init(fileURLWithPath:))

            if sourceExists {
                let recordedDestinationExists = entry.destinationPath.map { fileManager.fileExists(atPath: $0) } ?? false
                if !recordedDestinationExists {
                    try validateRecordedItem(sourceURL, entry: entry)
                    journal.entries[index].status = entry.status == .planned ? .notApplied : .undone
                    if journal.entries[index].status == .undone { completed += 1 }
                    try write(journal, to: journalURL)
                    if let recoveryURL { try? fileManager.removeItem(at: recoveryURL) }
                    continue
                }
            }

            if entry.status == .planned, sourceExists {
                let recordedDestinationExists = entry.destinationPath.map { fileManager.fileExists(atPath: $0) } ?? false
                if !recordedDestinationExists {
                    if let recoveryURL { try? fileManager.removeItem(at: recoveryURL) }
                    journal.entries[index].status = .notApplied
                    try write(journal, to: journalURL)
                    continue
                }
            }

            guard let destinationPath = entry.destinationPath else {
                if let recoveryURL, fileManager.fileExists(atPath: recoveryURL.path) {
                    try validateRecordedItem(recoveryURL, entry: entry)
                    try fileManager.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.moveItem(at: recoveryURL, to: sourceURL)
                    journal.entries[index].status = .undone
                    completed += 1
                    try write(journal, to: journalURL)
                    await progress(.init(completed: completed, total: total, currentAction: "Recovered \(sourceURL.lastPathComponent)"))
                    continue
                }
                throw FileOperationError.unresolvedOperation(entry.sourcePath)
            }

            let resolvedDestinationURL: URL?
            var scopedTrashURL: URL?
            if entry.action == .trash {
                if let bookmarkData = entry.destinationBookmarkData {
                    if let url = try? resolveURL(path: destinationPath, bookmarkData: bookmarkData),
                       url.startAccessingSecurityScopedResource() {
                        resolvedDestinationURL = url
                        scopedTrashURL = url
                    } else {
                        resolvedDestinationURL = nil
                    }
                } else {
                    let legacyURL = URL(fileURLWithPath: destinationPath)
                    resolvedDestinationURL = fileManager.fileExists(atPath: legacyURL.path) ? legacyURL : nil
                }
            } else {
                resolvedDestinationURL = URL(fileURLWithPath: destinationPath)
            }
            let destinationURL: URL
            if let resolvedDestinationURL, fileManager.fileExists(atPath: resolvedDestinationURL.path) {
                destinationURL = resolvedDestinationURL
            } else if let recoveryURL, fileManager.fileExists(atPath: recoveryURL.path) {
                destinationURL = recoveryURL
            } else if entry.action == .trash {
                throw FileOperationError.bookmarkUnavailable(destinationPath)
            } else {
                destinationURL = URL(fileURLWithPath: destinationPath)
            }
            defer {
                if let scopedTrashURL {
                    scopedTrashURL.stopAccessingSecurityScopedResource()
                }
            }
            let destinationExists = fileManager.fileExists(atPath: destinationURL.path)

            if sourceExists, !destinationExists {
                try validateRecordedItem(sourceURL, entry: entry)
                journal.entries[index].status = .undone
                completed += 1
                try write(journal, to: journalURL)
                if let recoveryURL { try? fileManager.removeItem(at: recoveryURL) }
                continue
            }
            if sourceExists, destinationExists {
                throw FileOperationError.restoreConflict(sourceURL.path)
            }
            guard destinationExists else {
                throw FileOperationError.sourceMissing(destinationURL.path)
            }

            try validateRecordedItem(destinationURL, entry: entry)
            try fileManager.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: destinationURL, to: sourceURL)
            journal.entries[index].status = .undone
            completed += 1
            try write(journal, to: journalURL)
            if let recoveryURL, recoveryURL != destinationURL { try? fileManager.removeItem(at: recoveryURL) }
            await progress(.init(completed: completed, total: total, currentAction: "Restored \(sourceURL.lastPathComponent)"))
        }

        journal.undoneAt = Date()
        journal.failureDescription = nil
        removeEmptyRecoveryDirectory(for: journal, rootURL: rootURL)
        try write(journal, to: journalURL)
        return journal
    }

    private func validateSource(_ sourceURL: URL, isInside rootURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw FileOperationError.sourceMissing(sourceURL.path)
        }
        guard sourceURL.isDescendantOrEqual(of: rootURL) else {
            throw FileOperationError.unsafeSource(sourceURL.path)
        }
    }

    private func preflight(_ plan: FileOperationPlan) throws {
        for operation in plan.trashOperations {
            try Task.checkCancellation()
            try validateSource(operation.sourceURL, isInside: plan.rootURL)
            try validateExpectedState(
                operation.sourceURL,
                snapshot: operation.expectedSnapshot,
                sha256: operation.expectedSHA256
            )
        }
        for operation in plan.moveOperations {
            try Task.checkCancellation()
            _ = try categoryFolderName(operation.category)
            try validateTopLevelSource(operation.sourceURL, root: plan.rootURL)
            try validateExpectedState(operation.sourceURL, snapshot: operation.expectedSnapshot, sha256: nil)
        }

        let organisedRoot = plan.rootURL.appendingPathComponent("Organised Files", isDirectory: true)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: organisedRoot.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw FileOperationError.destinationChanged(organisedRoot.path)
        }
    }

    private func validateTopLevelSource(_ sourceURL: URL, root rootURL: URL) throws {
        try validateSource(sourceURL, isInside: rootURL)
        guard sourceURL.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL else {
            throw FileOperationError.unsafeSource(sourceURL.path)
        }
    }

    private func validateExpectedState(_ url: URL, snapshot expected: FileStateSnapshot, sha256 expectedHash: String?) throws {
        let current = try snapshot(for: url)
        guard current.matches(expected) else { throw FileOperationError.sourceChanged(url.path) }
        if let expectedHash {
            guard try sha256IfRegularFile(url) == expectedHash else {
                throw FileOperationError.sourceChanged(url.path)
            }
        }
    }

    private func validateRecordedItem(_ url: URL, entry: OperationJournalEntry) throws {
        let current = try snapshot(for: url)
        guard current.matches(
            entry.snapshot,
            modificationDateTolerance: entry.modificationDateTolerance ?? 0.01
        ) else { throw FileOperationError.destinationChanged(url.path) }
        if let expectedHash = entry.contentSHA256 {
            guard try sha256IfRegularFile(url) == expectedHash else {
                throw FileOperationError.destinationChanged(url.path)
            }
        }
    }

    private func snapshot(for url: URL) throws -> FileStateSnapshot {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let size = values.isDirectory == true ? try folderSize(url) : Int64(values.fileSize ?? 0)
        return .init(size: size, modificationDate: values.contentModificationDate)
    }

    private func folderSize(_ folderURL: URL) throws -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw FileOperationError.sourceMissing(folderURL.path) }

        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isHiddenKey])
            if values.isRegularFile == true, values.isHidden != true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private func sha256IfRegularFile(_ url: URL) throws -> String? {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func availableDestinationURL(for sourceURL: URL, in folderURL: URL) -> URL {
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var candidate = folderURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let candidateName = pathExtension.isEmpty ? "\(name) \(index)" : "\(name) \(index).\(pathExtension)"
            candidate = folderURL.appendingPathComponent(candidateName, isDirectory: false)
            index += 1
        }
        return candidate
    }

    private func categoryFolderName(_ value: String) throws -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        let invalidCharacters = CharacterSet.controlCharacters.union(.newlines)
        guard !cleaned.isEmpty,
              cleaned != ".",
              cleaned != "..",
              !cleaned.hasPrefix("."),
              !cleaned.contains("/"),
              !cleaned.contains(":"),
              cleaned.rangeOfCharacter(from: invalidCharacters) == nil,
              cleaned.utf8.count <= 200 else {
            throw FileOperationError.invalidCategory(value)
        }
        return cleaned
    }

    private func createRecoveryCopy(
        for sourceURL: URL,
        rootURL: URL,
        sessionID: String,
        operationID: String
    ) throws -> URL {
        let directory = rootURL
            .appendingPathComponent("Organised Files", isDirectory: true)
            .appendingPathComponent(".Sortwell Recovery", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeID = operationID.replacingOccurrences(of: "/", with: "-")
        let recoveryURL = directory.appendingPathComponent("\(safeID)-\(sourceURL.lastPathComponent)")
        do {
            try fileManager.linkItem(at: sourceURL, to: recoveryURL)
        } catch {
            try fileManager.copyItem(at: sourceURL, to: recoveryURL)
        }
        return recoveryURL
    }

    private func removeEmptyRecoveryDirectory(for journal: OperationJournal, rootURL: URL) {
        let recoveryRootURL = rootURL
            .appendingPathComponent("Organised Files", isDirectory: true)
            .appendingPathComponent(".Sortwell Recovery", isDirectory: true)
            .standardizedFileURL
        let sessionURL = recoveryRootURL
            .appendingPathComponent(journal.id, isDirectory: true)
            .standardizedFileURL
        guard sessionURL.deletingLastPathComponent() == recoveryRootURL,
              (try? fileManager.contentsOfDirectory(atPath: sessionURL.path).isEmpty) == true else { return }
        try? fileManager.removeItem(at: sessionURL)
        if (try? fileManager.contentsOfDirectory(atPath: recoveryRootURL.path).isEmpty) == true {
            try? fileManager.removeItem(at: recoveryRootURL)
        }
    }

    private func makeSecurityBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func resolveURL(path: String, bookmarkData: Data?) throws -> URL {
        guard let bookmarkData else { return URL(fileURLWithPath: path) }
        var isStale = false
        return try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func makeJournalURL(for id: String) throws -> URL {
        let directory = try journalDirectory ?? OperationJournalStore.defaultDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(id).json")
    }

    private func write(_ journal: OperationJournal, to url: URL) throws {
        try OperationJournalStore.write(journal, to: url)
    }

    private func readJournal(from url: URL) throws -> OperationJournal {
        try OperationJournalStore.read(from: url)
    }
}

private enum OperationJournalStore {
    static func defaultDirectory(fileManager: FileManager) throws -> URL {
        try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Sortwell", isDirectory: true)
            .appendingPathComponent("Journals", isDirectory: true)
    }

    static func loadAll(fileManager: FileManager) -> [OperationJournal] {
        guard let directory = try? defaultDirectory(fileManager: fileManager) else { return [] }
        return loadAll(from: directory, fileManager: fileManager)
    }

    static func loadAll(from directory: URL, fileManager: FileManager) -> [OperationJournal] {
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? read(from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func write(_ journal: OperationJournal, to url: URL) throws {
        let data = try JSONEncoder.sortwell.encode(journal)
        try data.write(to: url, options: [.atomic])
    }

    static func read(from url: URL) throws -> OperationJournal {
        let data = try Data(contentsOf: url)
        if let journal = try? JSONDecoder.sortwell.decode(OperationJournal.self, from: data) {
            return journal
        }
        let legacy = try JSONDecoder.legacySortwell.decode(LegacyOperationJournal.self, from: data)
        return OperationJournal(
            id: legacy.id,
            rootPath: legacy.rootPath,
            rootBookmarkData: nil,
            createdAt: legacy.createdAt,
            completedAt: legacy.completedAt,
            undoneAt: legacy.undoneAt,
            journalPath: legacy.journalPath ?? url.path,
            failureDescription: nil,
            entries: legacy.entries.map { entry in
                OperationJournalEntry(
                    id: entry.id,
                    action: entry.action,
                    sourcePath: entry.sourcePath,
                    destinationPath: entry.destinationPath,
                    destinationBookmarkData: nil,
                    recoveryPath: nil,
                    snapshot: entry.snapshot,
                    contentSHA256: nil,
                    modificationDateTolerance: 1.0,
                    status: legacy.undoneAt == nil ? .completed : .undone
                )
            }
        )
    }
}

private struct LegacyOperationJournal: Decodable {
    let id: String
    let rootPath: String
    let createdAt: Date
    let completedAt: Date?
    let undoneAt: Date?
    let journalPath: String?
    let entries: [LegacyOperationJournalEntry]
}

private struct LegacyOperationJournalEntry: Decodable {
    let id: String
    let action: JournalActionKind
    let sourcePath: String
    let destinationPath: String
    let snapshot: FileStateSnapshot
}

private extension FileStateSnapshot {
    func matches(_ other: FileStateSnapshot, modificationDateTolerance: TimeInterval = 0.01) -> Bool {
        guard size == other.size else { return false }
        switch (modificationDate, other.modificationDate) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs.timeIntervalSince(rhs)) <= modificationDateTolerance
        default:
            return false
        }
    }
}

private extension JSONEncoder {
    static var sortwell: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

private extension JSONDecoder {
    static var sortwell: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    static var legacySortwell: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension URL {
    func isDescendantOrEqual(of parent: URL) -> Bool {
        let parentComponents = parent.standardizedFileURL.pathComponents
        let childComponents = standardizedFileURL.pathComponents
        guard childComponents.count >= parentComponents.count else { return false }
        return Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }
}
