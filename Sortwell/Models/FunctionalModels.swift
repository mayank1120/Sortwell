import Foundation

struct FolderScanProgress: Sendable {
    enum Phase: String, Sendable {
        case inventory = "Inspecting folder contents"
        case projects = "Protecting software projects"
        case hashing = "Comparing possible duplicates"
        case planning = "Preparing the organisation plan"
    }

    let phase: Phase
    let completed: Int
    let total: Int
    let currentPath: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

struct ScannedOrganisationItem: Sendable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date?
    let category: String
    let explanation: String
}

struct ScannedNeedsReviewItem: Sendable {
    let id: String
    let url: URL
    let name: String
    let kindDescription: String
    let reason: String
    let size: Int64
    let modificationDate: Date?
}

struct ScannedProtectedProject: Sendable {
    let id: String
    let url: URL
    let name: String
    let containedFiles: Int
    let reason: String
}

struct ScannedDuplicateCopy: Sendable {
    let id: String
    let url: URL
    let name: String
    let size: Int64
    let modificationDate: Date?
    let isProtected: Bool
    let isInsideProject: Bool
    let protectionReason: String?
}

struct ScannedDuplicateGroup: Sendable {
    let id: String
    let title: String
    let sha256: String
    let copies: [ScannedDuplicateCopy]
}

struct FolderScanResult: Sendable {
    let rootURL: URL
    let categoryDefinitions: [FileCategoryDefinition]
    let scannedFileCount: Int
    let scannedDirectoryCount: Int
    let totalBytes: Int64
    let organisationItems: [ScannedOrganisationItem]
    let needsReviewItems: [ScannedNeedsReviewItem]
    let protectedProjects: [ScannedProtectedProject]
    let duplicateGroups: [ScannedDuplicateGroup]
    let protectedDuplicateGroupCount: Int
}

struct FileStateSnapshot: Sendable, Codable, Hashable {
    let size: Int64
    let modificationDate: Date?
}

struct FileOperationProgress: Sendable {
    let completed: Int
    let total: Int
    let currentAction: String

    var fraction: Double {
        guard total > 0 else { return 1 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

struct FileOperationPlan: Sendable {
    let id: String
    let rootURL: URL
    let rootBookmarkData: Data?
    let moveOperations: [FileMoveOperation]
    let trashOperations: [FileTrashOperation]

    var totalOperationCount: Int {
        moveOperations.count + trashOperations.count
    }
}

struct FileMoveOperation: Sendable {
    let id: String
    let sourceURL: URL
    let category: String
    let expectedSnapshot: FileStateSnapshot
}

struct FileTrashOperation: Sendable {
    let id: String
    let sourceURL: URL
    let expectedSnapshot: FileStateSnapshot
    let expectedSHA256: String
}

enum JournalActionKind: String, Sendable, Codable {
    case move
    case trash
}

enum JournalActionStatus: String, Sendable, Codable {
    case planned
    case completed
    case undone
    case notApplied
}

struct OperationJournalEntry: Identifiable, Sendable, Codable, Hashable {
    let id: String
    let action: JournalActionKind
    let sourcePath: String
    var destinationPath: String?
    var destinationBookmarkData: Data?
    var recoveryPath: String?
    let snapshot: FileStateSnapshot
    let contentSHA256: String?
    let modificationDateTolerance: TimeInterval?
    var status: JournalActionStatus
}

struct OperationJournal: Identifiable, Sendable, Codable, Hashable {
    let id: String
    let rootPath: String
    let rootBookmarkData: Data?
    let createdAt: Date
    var completedAt: Date?
    var undoneAt: Date?
    var journalPath: String?
    var failureDescription: String?
    var entries: [OperationJournalEntry]

    var moveCount: Int {
        entries.filter { $0.action == .move && $0.status != .planned && $0.status != .notApplied }.count
    }

    var trashCount: Int {
        entries.filter { $0.action == .trash && $0.status != .planned && $0.status != .notApplied }.count
    }
}
