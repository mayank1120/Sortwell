import CryptoKit
import Foundation

enum FolderScanError: LocalizedError, Sendable {
    case selectedRootIsProject(String)
    case incompleteScan(String)

    var errorDescription: String? {
        switch self {
        case .selectedRootIsProject(let path):
            "The selected folder appears to be a software project. Choose its parent folder so Sortwell can keep the project intact: \(path)"
        case .incompleteScan(let path):
            "Sortwell could not safely inspect every item under: \(path)"
        }
    }
}

actor FolderScanner {
    typealias ProgressHandler = @Sendable (FolderScanProgress) async -> Void

    private let fileManager = FileManager.default
    private let classifier: FileClassifier
    private let contentAnalyzer: LocalContentAnalyzer
    private let collectionRoots: Set<URL>
    private let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .fileSizeKey, .contentModificationDateKey, .isHiddenKey
    ]
    private let projectMarkers: Set<String> = [
        ".git", "package.json", "Package.swift", "pyproject.toml", "pom.xml",
        "build.gradle", "Cargo.toml", "go.mod", "Gemfile", "composer.json",
        "CMakeLists.txt", "Makefile", "Jenkinsfile", "docker-compose.yml",
        "requirements.txt", "setup.py", "setup.cfg", "Pipfile", "poetry.lock",
        "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "tsconfig.json",
        "Podfile", "Cartfile", "gradlew", ".swiftpm", ".idea", ".vscode"
    ]
    private let projectBundleExtensions: Set<String> = [
        "xcodeproj", "xcworkspace", "playground", "sln", "csproj", "fsproj", "vbproj"
    ]
    private let sourceExtensions: Set<String> = [
        "c", "cc", "cpp", "cxx", "h", "hpp", "m", "mm", "swift", "py", "rb",
        "js", "jsx", "ts", "tsx", "java", "kt", "kts", "go", "rs", "php", "scala"
    ]
    private let sourceDirectoryNames: Set<String> = [
        "app", "lib", "src", "source", "sources", "test", "tests"
    ]

    init(
        classifier: FileClassifier = FileClassifier(),
        contentAnalyzer: LocalContentAnalyzer? = nil,
        collectionRoots: Set<URL>? = nil
    ) {
        self.classifier = classifier
        self.contentAnalyzer = contentAnalyzer ?? LocalContentAnalyzer(preferences: .defaults)
        self.collectionRoots = collectionRoots ?? Set(
            [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory, .documentDirectory]
                .compactMap { FileManager.default.urls(for: $0, in: .userDomainMask).first?.standardizedFileURL }
        )
    }

    func scan(rootURL: URL, progress: @escaping ProgressHandler) async throws -> FolderScanResult {
        try Task.checkCancellation()
        let root = rootURL.standardizedFileURL
        if isProjectMarker(root) {
            throw FolderScanError.selectedRootIsProject(root.path)
        }
        if try selectedRootLooksLikeProject(root) {
            throw FolderScanError.selectedRootIsProject(root.path)
        }
        let topLevelURLs = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ).map(\.standardizedFileURL)

        var protectedRoots: [URL: ProtectedRoot] = [:]
        var protectedProjects: [ScannedProtectedProject] = []
        for (index, url) in topLevelURLs.enumerated() {
            try Task.checkCancellation()
            await progress(.init(phase: .projects, completed: index + 1, total: topLevelURLs.count, currentPath: url.path))
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            if url.lastPathComponent == "Organised Files" {
                protectedRoots[url] = .init(reason: "Existing Sortwell output is left unchanged.", isProject: false)
            } else if let reason = projectReason(for: url) {
                protectedRoots[url] = .init(reason: reason, isProject: true)
            }
        }

        var allFiles: [FileRecord] = []
        var directoryCount = 0
        var totalBytes: Int64 = 0
        var containedCounts: [URL: Int] = [:]

        let errorRecorder = ScanErrorRecorder()
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, _ in
                errorRecorder.record(url.path)
                return false
            }
        )

        var inspected = 0
        while let enumeratedURL = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()
            let url = enumeratedURL.standardizedFileURL
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: resourceKeys)
            } catch {
                throw FolderScanError.incompleteScan(url.path)
            }
            if values.isSymbolicLink == true || values.isHidden == true { continue }
            if values.isDirectory == true {
                directoryCount += 1
                continue
            }
            guard values.isRegularFile == true else { continue }

            let size = Int64(values.fileSize ?? 0)
            totalBytes += size
            let topLevel = url.deletingLastPathComponent() == root
            let protectedRoot = protectedRoots.keys.first { url.isDescendant(of: $0) }
            if let protectedRoot {
                containedCounts[protectedRoot, default: 0] += 1
            }
            let protectedInfo = protectedRoot.flatMap { protectedRoots[$0] }
            let protectionReason: String?
            if protectedInfo?.isProject == true {
                protectionReason = "Required inside a protected software project."
            } else if !topLevel {
                protectionReason = "Nested inside a folder that Sortwell keeps intact."
            } else {
                protectionReason = nil
            }
            allFiles.append(
                .init(
                    url: url,
                    size: size,
                    modificationDate: values.contentModificationDate,
                    isTopLevel: topLevel,
                    isProtected: protectionReason != nil,
                    isInsideProject: protectedInfo?.isProject == true,
                    protectionReason: protectionReason
                )
            )
            inspected += 1
            if inspected.isMultiple(of: 100) {
                await progress(.init(phase: .inventory, completed: inspected, total: max(inspected + 1, topLevelURLs.count), currentPath: url.path))
            }
        }
        if let failedPath = errorRecorder.failedPath {
            throw FolderScanError.incompleteScan(failedPath)
        }
        await progress(.init(phase: .inventory, completed: inspected, total: max(inspected, 1), currentPath: root.path))

        for (url, info) in protectedRoots.sorted(by: { $0.key.path < $1.key.path }) where info.isProject {
            protectedProjects.append(
                .init(
                    id: stableID(url.path),
                    url: url,
                    name: url.lastPathComponent,
                    containedFiles: containedCounts[url, default: 0],
                    reason: info.reason
                )
            )
        }

        var organisationItems: [ScannedOrganisationItem] = []
        var needsReviewItems: [ScannedNeedsReviewItem] = []
        for url in topLevelURLs.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: resourceKeys)
            if values.isHidden == true || protectedRoots[url] != nil { continue }
            guard values.isSymbolicLink != true else { continue }
            let isDirectory = values.isDirectory == true
            guard isDirectory || values.isRegularFile == true else { continue }
            let size = isDirectory ? folderSize(url, from: allFiles) : Int64(values.fileSize ?? 0)
            let analysis: LocalContentAnalysis
            if isDirectory {
                analysis = .empty
            } else {
                analysis = (try? await contentAnalyzer.analyse(url)) ?? .empty
            }
            if let classification = classifier.classify(name: url.lastPathComponent, isDirectory: isDirectory, analysis: analysis) {
                organisationItems.append(
                    .init(
                        id: stableID(url.path), url: url, name: url.lastPathComponent,
                        isDirectory: isDirectory, size: size,
                        modificationDate: values.contentModificationDate,
                        category: classification.category, explanation: classification.explanation
                    )
                )
            } else {
                needsReviewItems.append(
                    .init(
                        id: stableID(url.path), url: url, name: url.lastPathComponent,
                        kindDescription: isDirectory ? "Folder" : (url.pathExtension.isEmpty ? "File" : "\(url.pathExtension.uppercased()) file"),
                        reason: "The filename and file type do not provide enough context for a safe category suggestion.",
                        size: size, modificationDate: values.contentModificationDate
                    )
                )
            }
        }

        await progress(.init(phase: .hashing, completed: 0, total: allFiles.count, currentPath: root.path))
        let duplicateResult = try await findDuplicates(in: allFiles, progress: progress)
        await progress(.init(phase: .planning, completed: 1, total: 1, currentPath: root.path))

        return .init(
            rootURL: root,
            categoryDefinitions: classifier.categoryDefinitions,
            scannedFileCount: allFiles.count,
            scannedDirectoryCount: directoryCount,
            totalBytes: totalBytes,
            organisationItems: organisationItems,
            needsReviewItems: needsReviewItems,
            protectedProjects: protectedProjects,
            duplicateGroups: duplicateResult.actionable,
            protectedDuplicateGroupCount: duplicateResult.protectedCount
        )
    }

    private func findDuplicates(
        in files: [FileRecord],
        progress: @escaping ProgressHandler
    ) async throws -> (actionable: [ScannedDuplicateGroup], protectedCount: Int) {
        let sizeGroups = Dictionary(grouping: files, by: \.size)
            .filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
        let candidates = sizeGroups.flatMap { group in
            group.value.sorted { $0.url.path < $1.url.path }
        }
        var hashGroups: [String: [FileRecord]] = [:]

        for (index, file) in candidates.enumerated() {
            try Task.checkCancellation()
            let hash = try sha256(file.url)
            hashGroups[hash, default: []].append(file)
            if index.isMultiple(of: 20) || index == candidates.count - 1 {
                await progress(.init(phase: .hashing, completed: index + 1, total: max(candidates.count, 1), currentPath: file.url.path))
            }
        }

        var actionable: [ScannedDuplicateGroup] = []
        var protectedCount = 0
        for hash in hashGroups.keys.sorted() {
            guard let records = hashGroups[hash], records.count > 1 else { continue }
            let sortedRecords = records.sorted { $0.url.path < $1.url.path }
            let canonical = sortedRecords[0]
            let exactRecords = try sortedRecords.filter { try filesAreEqual(canonical.url, $0.url) }
            guard exactRecords.count > 1 else { continue }
            if exactRecords.allSatisfy(\.isProtected) {
                protectedCount += 1
                continue
            }
            let copies = exactRecords.map { record in
                ScannedDuplicateCopy(
                    id: stableID(record.url.path), url: record.url,
                    name: record.url.lastPathComponent, size: record.size,
                    modificationDate: record.modificationDate,
                    isProtected: record.isProtected,
                    isInsideProject: record.isInsideProject,
                    protectionReason: record.protectionReason
                )
            }
            let sortedCopies = copies.sorted { $0.url.path < $1.url.path }
            actionable.append(
                .init(
                    id: hash, title: duplicateTitle(for: sortedCopies), sha256: hash,
                    copies: sortedCopies
                )
            )
        }
        actionable.sort {
            let titleOrder = $0.title.localizedStandardCompare($1.title)
            return titleOrder == .orderedSame ? $0.sha256 < $1.sha256 : titleOrder == .orderedAscending
        }
        return (actionable, protectedCount)
    }

    private func projectReason(for directory: URL) -> String? {
        do {
            if try containsProjectMarker(directory, depth: 0, inspected: 0) {
                return "Contains software-project markers, source code, or build configuration. Its contents and location are protected."
            }
            return nil
        } catch {
            return "Could not be fully inspected for project markers, so its contents and location are protected."
        }
    }

    private func selectedRootLooksLikeProject(_ directory: URL) throws -> Bool {
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        if children.contains(where: { $0.lastPathComponent == ".git" }) { return true }
        if collectionRoots.contains(directory.standardizedFileURL) { return false }

        let markerCount = children.filter(isProjectMarker).count
        let hasProjectBundle = children.contains { projectBundleExtensions.contains($0.pathExtension.lowercased()) }
        var hasSourceFile = false
        var hasSourceDirectory = false
        for child in children where !child.lastPathComponent.hasPrefix(".") {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                hasSourceDirectory = hasSourceDirectory || sourceDirectoryNames.contains(child.lastPathComponent.lowercased())
            } else {
                hasSourceFile = hasSourceFile || sourceExtensions.contains(child.pathExtension.lowercased())
            }
        }
        return hasProjectBundle
            || looksLikeSourceTree(children)
            || markerCount >= 2
            || (markerCount == 1 && (hasSourceFile || hasSourceDirectory))
    }

    private func containsProjectMarker(_ directory: URL, depth: Int, inspected: Int) throws -> Bool {
        guard depth <= 3, inspected < 300 else { throw ProjectInspectionError.safetyLimitReached }
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: []
        )

        if children.contains(where: isProjectMarker) || looksLikeSourceTree(children) { return true }
        if depth == 3, children.contains(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) {
            throw ProjectInspectionError.safetyLimitReached
        }
        if children.count > 100 { throw ProjectInspectionError.safetyLimitReached }
        for child in children.prefix(100) {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            guard values.isDirectory == true, values.isHidden != true else { continue }
            if try containsProjectMarker(child, depth: depth + 1, inspected: inspected + children.count) { return true }
        }
        return false
    }

    private func isProjectMarker(_ url: URL) -> Bool {
        projectMarkers.contains(url.lastPathComponent)
            || projectBundleExtensions.contains(url.pathExtension.lowercased())
    }

    private func looksLikeSourceTree(_ children: [URL]) -> Bool {
        var sourceFileCount = 0
        var hasSourceDirectory = false
        for child in children where !child.lastPathComponent.hasPrefix(".") {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                hasSourceDirectory = hasSourceDirectory || sourceDirectoryNames.contains(child.lastPathComponent.lowercased())
            } else if sourceExtensions.contains(child.pathExtension.lowercased()) {
                sourceFileCount += 1
            }
        }
        return sourceFileCount >= 4 || (sourceFileCount >= 2 && hasSourceDirectory)
    }

    private func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func filesAreEqual(_ first: URL, _ second: URL) throws -> Bool {
        if first == second { return true }
        let firstHandle = try FileHandle(forReadingFrom: first)
        let secondHandle = try FileHandle(forReadingFrom: second)
        defer {
            try? firstHandle.close()
            try? secondHandle.close()
        }
        while true {
            let firstData = try firstHandle.read(upToCount: 1_048_576) ?? Data()
            let secondData = try secondHandle.read(upToCount: 1_048_576) ?? Data()
            if firstData != secondData { return false }
            if firstData.isEmpty { return true }
        }
    }

    private func folderSize(_ folder: URL, from files: [FileRecord]) -> Int64 {
        files.filter { $0.url.isDescendant(of: folder) }.reduce(0) { $0 + $1.size }
    }

    private func duplicateTitle(for copies: [ScannedDuplicateCopy]) -> String {
        let preferred = copies.first(where: { !$0.name.hasPrefix("_") })?.name ?? copies[0].name
        return preferred.isEmpty ? "Matching files" : preferred
    }

    private func stableID(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

private struct FileRecord: Sendable {
    let url: URL
    let size: Int64
    let modificationDate: Date?
    let isTopLevel: Bool
    let isProtected: Bool
    let isInsideProject: Bool
    let protectionReason: String?
}

private struct ProtectedRoot: Sendable {
    let reason: String
    let isProject: Bool
}

private enum ProjectInspectionError: Error {
    case safetyLimitReached
}

private final class ScanErrorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?

    var failedPath: String? {
        lock.withLock { path }
    }

    func record(_ path: String) {
        lock.withLock {
            if self.path == nil { self.path = path }
        }
    }
}

private extension URL {
    func isDescendant(of parent: URL) -> Bool {
        let parentComponents = parent.standardizedFileURL.pathComponents
        let childComponents = standardizedFileURL.pathComponents
        guard childComponents.count > parentComponents.count else { return false }
        return Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }
}
