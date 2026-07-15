import Foundation

struct FileCategoryDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var icon: String
}

enum ClassificationMatchKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case filenameContains
    case fileExtension
    case contentContains

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filenameContains: "Filename contains"
        case .fileExtension: "File extension"
        case .contentContains: "Extracted content contains"
        }
    }
}

enum ClassificationTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case files
    case folders
    case filesAndFolders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "Files"
        case .folders: "Folders"
        case .filesAndFolders: "Files and folders"
        }
    }
}

struct CustomClassificationRule: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var categoryID: String
    var matchKind: ClassificationMatchKind
    var pattern: String
    var target: ClassificationTarget
    var isEnabled: Bool
}

struct SortwellPreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var customCategories: [FileCategoryDefinition]
    var customRules: [CustomClassificationRule]
    var recoveryRetentionDays: Int
    var contentAnalysisEnabled: Bool
    var ocrEnabled: Bool

    static let defaults = SortwellPreferences(
        schemaVersion: currentSchemaVersion,
        customCategories: [],
        customRules: [],
        recoveryRetentionDays: 30,
        contentAnalysisEnabled: true,
        ocrEnabled: true
    )
}

struct PreferencesRepository: Sendable {
    let fileURL: URL

    static func live(fileManager: FileManager = .default) throws -> PreferencesRepository {
        let directory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Sortwell", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return .init(fileURL: directory.appendingPathComponent("Preferences.json"))
    }

    static func temporary() -> PreferencesRepository {
        .init(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("Sortwell-Preferences-\(UUID().uuidString).json"))
    }

    func load() throws -> SortwellPreferences {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .defaults }
        let preferences = try JSONDecoder().decode(SortwellPreferences.self, from: Data(contentsOf: fileURL))
        guard preferences.schemaVersion == SortwellPreferences.currentSchemaVersion else {
            throw PreferencesError.unsupportedSchema
        }
        return preferences
    }

    func save(_ preferences: SortwellPreferences) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(preferences).write(to: fileURL, options: .atomic)
    }
}

enum PreferencesError: LocalizedError {
    case invalidCategory
    case invalidIcon
    case duplicateCategory
    case invalidRule
    case unsupportedSchema

    var errorDescription: String? {
        switch self {
        case .invalidCategory: "Category names must be valid folder names of 200 UTF-8 bytes or fewer."
        case .invalidIcon: "Enter the name of a valid SF Symbol."
        case .duplicateCategory: "A category with this name already exists."
        case .invalidRule: "Classification rules need a pattern and a valid category."
        case .unsupportedSchema: "These preferences were created by an unsupported Sortwell version."
        }
    }
}
