import Foundation

enum AppRoute: String, CaseIterable, Identifiable {
    case welcome
    case scan
    case summary
    case review
    case applying
    case results
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .scan: "Scan"
        case .summary: "Scan Summary"
        case .review: "Review Workspace"
        case .applying: "Apply"
        case .results: "Results"
        case .activity: "Activity and Undo"
        }
    }

}

enum ReviewSection: String, CaseIterable, Identifiable {
    case organisation
    case duplicates
    case needsReview
    case protectedProjects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .organisation: "Organisation Plan"
        case .duplicates: "Exact Duplicates"
        case .needsReview: "Needs Review"
        case .protectedProjects: "Protected Projects"
        }
    }

    var icon: String {
        switch self {
        case .organisation: "list.bullet.rectangle"
        case .duplicates: "doc.on.doc"
        case .needsReview: "questionmark.folder"
        case .protectedProjects: "lock.shield"
        }
    }
}

struct SortwellCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let totalCount: Int
}

enum PlanItemKind: Hashable {
    case file
    case folder

    var icon: String {
        switch self {
        case .file: "doc"
        case .folder: "folder"
        }
    }
}

struct PlanItem: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: PlanItemKind
    let currentPath: String
    var proposedCategory: String
    let explanation: String
    let size: String
    var isSelected: Bool
    let fileURL: URL?

    init(
        id: String,
        name: String,
        kind: PlanItemKind,
        currentPath: String,
        proposedCategory: String,
        explanation: String,
        size: String,
        isSelected: Bool,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.currentPath = currentPath
        self.proposedCategory = proposedCategory
        self.explanation = explanation
        self.size = size
        self.isSelected = isSelected
        self.fileURL = fileURL
    }
}

struct DuplicateCopy: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let size: String
    let isInsideProject: Bool
    let protectionReason: String?
    let fileURL: URL?

    init(
        id: String,
        name: String,
        path: String,
        size: String,
        isInsideProject: Bool,
        protectionReason: String? = nil,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.isInsideProject = isInsideProject
        self.protectionReason = protectionReason
        self.fileURL = fileURL
    }

    var isProtected: Bool {
        isInsideProject || protectionReason != nil
    }
}

enum DuplicateDecision: String, Hashable {
    case pending
    case keepAll
    case moveOthersToTrash
}

struct DuplicateGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let hashPrefix: String
    var copies: [DuplicateCopy]
    var canonicalCopyID: String?
    var decision: DuplicateDecision

    var removableCopyCount: Int {
        guard decision == .moveOthersToTrash else { return 0 }
        return removableCopyIDs.count
    }

    var potentiallyRemovableCopyCount: Int {
        candidateRemovableCopyIDs.count
    }

    var candidateRemovableCopyIDs: [String] {
        guard let canonicalCopyID,
              copies.contains(where: { $0.id == canonicalCopyID }) else { return [] }
        return copies
            .filter { !$0.isProtected && $0.id != canonicalCopyID }
            .map(\.id)
    }

    var removableCopyIDs: [String] {
        decision == .moveOthersToTrash ? candidateRemovableCopyIDs : []
    }

    var canApproveCleanup: Bool {
        !candidateRemovableCopyIDs.isEmpty
    }
}

struct NeedsReviewItem: Identifiable, Hashable {
    let id: String
    let name: String
    let kindDescription: String
    let currentPath: String
    let reason: String
    var selectedCategory: String?
    var hasReviewedDecision: Bool
    let fileURL: URL?

    init(
        id: String,
        name: String,
        kindDescription: String,
        currentPath: String,
        reason: String,
        selectedCategory: String?,
        hasReviewedDecision: Bool,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.kindDescription = kindDescription
        self.currentPath = currentPath
        self.reason = reason
        self.selectedCategory = selectedCategory
        self.hasReviewedDecision = hasReviewedDecision
        self.fileURL = fileURL
    }
}

struct ProtectedProject: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let containedFiles: Int
    let reason: String
}

struct ActivitySession: Identifiable, Hashable {
    let id: String
    let folderName: String
    let dateDescription: String
    let moveCount: Int
    let trashCount: Int
    var isUndone: Bool
    var journalPath: String? = nil
    var isPartial: Bool = false
}
