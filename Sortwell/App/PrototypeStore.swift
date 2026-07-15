import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PrototypeStore {
    enum ScanMode: Hashable {
        case sample
        case real(URL)
    }

    var route: AppRoute = .welcome
    var reviewSection: ReviewSection = .organisation
    var categories = TelegramScenario.categories
    var planItems = TelegramScenario.planItems
    var duplicateGroups = TelegramScenario.duplicateGroups
    var needsReviewItems = TelegramScenario.needsReviewItems
    var protectedProjects = TelegramScenario.protectedProjects
    var activity = TelegramScenario.previousActivity

    var selectedPlanItemID: String? = TelegramScenario.planItems.first?.id
    var selectedDuplicateGroupID: String? = TelegramScenario.duplicateGroups.first?.id
    var selectedNeedsReviewID: String? = TelegramScenario.needsReviewItems.first?.id
    var selectedProjectID: String? = TelegramScenario.protectedProjects.first?.id

    var scanProgress = 0.0
    var applyProgress = 0.0
    var showConfirmation = false
    var showInspector = false
    var showNoticeAlert = false
    var noticeMessage = ""
    var showActivityDetail = false
    var activityDetailJournal: OperationJournal?
    var operationWasStopped = false
    var completedSessionID: String?
    var undoInProgressSessionID: String?
    var scanMode: ScanMode = .sample
    var scanStatus = FolderScanProgress.Phase.inventory.rawValue
    var scanCurrentPath = "Telegram/Hcl Documents/..."
    var scanFilesInspected = 0
    var scanProjectChecksCompleted = 0
    var scanDuplicateChecksCompleted = 0
    var latestScanResult: FolderScanResult?
    var applyStatus = "Preparing approved actions"
    var preferences: SortwellPreferences
    @ObservationIgnored private var activeScanID: UUID?
    @ObservationIgnored private var selectedRootBookmarkData: Data?
    @ObservationIgnored private var shouldLoadPersistedActivity = true
    @ObservationIgnored private var preferencesRepository: PreferencesRepository

    init(loadPersistedActivity: Bool = true, preferencesRepository: PreferencesRepository? = nil) {
        let repository = preferencesRepository ?? (try? .live()) ?? .temporary()
        self.preferencesRepository = repository
        preferences = (try? repository.load()) ?? .defaults
        shouldLoadPersistedActivity = loadPersistedActivity
        activity = Self.activitySessions(loadPersistedActivity: loadPersistedActivity)
        categories = Self.sampleCategories(preferences: preferences)
    }

    var scannedFileCount: Int { latestScanResult?.scannedFileCount ?? 8_203 }
    var scannedDirectoryCount: Int { latestScanResult?.scannedDirectoryCount ?? 2_223 }
    var scannedByteCount: Int64 { latestScanResult?.totalBytes ?? 259_000_000 }
    var protectedProjectCount: Int { latestScanResult?.protectedProjects.count ?? 30 }
    var protectedDuplicateGroupCount: Int { latestScanResult?.protectedDuplicateGroupCount ?? 1_227 }
    var totalTopLevelItems: Int {
        planItems.count + needsReviewItems.count + protectedProjectCount
    }

    var isSampleData: Bool {
        if case .sample = scanMode { return true }
        return false
    }

    var currentFolderName: String {
        switch scanMode {
        case .sample:
            "Telegram"
        case .real(let url):
            url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
    }

    var selectedFolderURL: URL? {
        if case .real(let url) = scanMode { return url }
        return nil
    }

    var destinationDisplayPath: String {
        "\(currentFolderName)/Organised Files/"
    }

    var applyIsSimulation: Bool { isSampleData }

    var scanSummarySubtitle: String {
        "\(formattedBytes(scannedByteCount)) · \(scannedFileCount.formatted()) files · \(scannedDirectoryCount.formatted()) folders. Nothing has changed yet."
    }

    var possibleTrashCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.potentiallyRemovableCopyCount }
    }

    var protectedDuplicateSummary: String {
        if protectedDuplicateGroupCount == 0 {
            return "Sortwell did not find repeated checksum groups that are locked inside protected locations."
        }
        return "Sortwell found \(protectedDuplicateGroupCount.formatted()) repeated checksum groups inside protected projects or nested folders. They are excluded because Sortwell does not change protected folder contents."
    }

    var currentScanPathDescription: String {
        if isSampleData { return sampleScanPath }
        if !scanCurrentPath.isEmpty { return scanCurrentPath }
        return currentFolderName
    }

    private var sampleScanPath: String {
        if scanProgress < 0.32 { return "Telegram/Hcl Documents/..." }
        if scanProgress < 0.68 { return "Telegram/ansible-itz-ing/roles/..." }
        return "Telegram/itz-bus-cardactivity1/tests/..."
    }

    var displayedScanFileCount: Int {
        if !isSampleData, latestScanResult == nil { return scanFilesInspected }
        return max(scanFilesInspected, Int(Double(scannedFileCount) * scanProgress))
    }

    var projectLedgerLabel: String {
        if !isSampleData, latestScanResult == nil { return "project boundaries checked" }
        return "software projects protected"
    }

    var duplicateLedgerLabel: String {
        if !isSampleData, latestScanResult == nil { return "duplicate candidates compared" }
        return "checksum groups compared"
    }

    var displayedProtectedProjectCount: Int {
        if latestScanResult != nil { return protectedProjectCount }
        if isSampleData { return min(30, Int(scanProgress * 37)) }
        return scanProjectChecksCompleted
    }

    var displayedDuplicateComparisonCount: Int {
        if latestScanResult != nil { return duplicateGroups.count + protectedDuplicateGroupCount }
        if isSampleData { return Int(scanProgress * 1_240) }
        return scanDuplicateChecksCompleted
    }

    var organisationMoveCount: Int {
        let removableCopyIDs = Set(duplicateGroups.flatMap(\.removableCopyIDs))
        return planItems.filter { $0.isSelected && !removableCopyIDs.contains($0.id) }.count
            + needsReviewItems.filter { $0.selectedCategory != nil && !removableCopyIDs.contains($0.id) }.count
    }

    var approvedTrashCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.removableCopyCount }
    }

    var reviewedDuplicateGroupCount: Int {
        duplicateGroups.filter { $0.decision != .pending }.count
    }

    var unresolvedItemCount: Int {
        needsReviewItems.filter { !$0.hasReviewedDecision }.count
    }

    var reviewedKeepInPlaceCount: Int {
        needsReviewItems.filter { $0.hasReviewedDecision && $0.selectedCategory == nil }.count
    }

    var needsReviewItemsKeptInPlaceCount: Int {
        needsReviewItems.filter { $0.selectedCategory == nil }.count
    }

    var totalActionCount: Int {
        organisationMoveCount + approvedTrashCount
    }

    var isOperationActive: Bool {
        route == .scan || route == .applying || undoInProgressSessionID != nil
    }

    func categoryMoveCount(_ category: String) -> Int {
        let removableCopyIDs = Set(duplicateGroups.flatMap(\.removableCopyIDs))
        return planItems.filter {
            $0.isSelected && $0.proposedCategory == category && !removableCopyIDs.contains($0.id)
        }.count + needsReviewItems.filter {
            $0.selectedCategory == category && !removableCopyIDs.contains($0.id)
        }.count
    }

    var selectedPlanItem: PlanItem? {
        planItems.first { $0.id == selectedPlanItemID }
    }

    var selectedDuplicateGroup: DuplicateGroup? {
        duplicateGroups.first { $0.id == selectedDuplicateGroupID }
    }

    var selectedNeedsReviewItem: NeedsReviewItem? {
        needsReviewItems.first { $0.id == selectedNeedsReviewID }
    }

    var selectedProject: ProtectedProject? {
        protectedProjects.first { $0.id == selectedProjectID }
    }

    var categoryDefinitions: [FileCategoryDefinition] {
        FileClassifier(preferences: preferences).categoryDefinitions
    }

    func addCustomCategory(title: String, icon: String) throws {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        let invalidCharacters = CharacterSet.controlCharacters.union(.newlines)
        guard !cleanedTitle.isEmpty,
              cleanedTitle != ".",
              cleanedTitle != "..",
              !cleanedTitle.hasPrefix("."),
              !cleanedTitle.contains("/"),
              !cleanedTitle.contains(":"),
              cleanedTitle.rangeOfCharacter(from: invalidCharacters) == nil,
              cleanedTitle.utf8.count <= 200 else { throw PreferencesError.invalidCategory }
        guard !categoryDefinitions.contains(where: { $0.title.caseInsensitiveCompare(cleanedTitle) == .orderedSame }) else {
            throw PreferencesError.duplicateCategory
        }
        let cleanedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedIcon.isEmpty || NSImage(systemSymbolName: cleanedIcon, accessibilityDescription: nil) != nil else {
            throw PreferencesError.invalidIcon
        }
        var updated = preferences
        updated.customCategories.append(
            .init(id: UUID().uuidString, title: cleanedTitle, icon: cleanedIcon.isEmpty ? "folder" : cleanedIcon)
        )
        try persistPreferences(updated)
    }

    func removeCustomCategory(_ id: String) throws {
        var updated = preferences
        updated.customCategories.removeAll { $0.id == id }
        updated.customRules.removeAll { $0.categoryID == id }
        try persistPreferences(updated)
    }

    func addCustomRule(
        categoryID: String,
        matchKind: ClassificationMatchKind,
        pattern: String,
        target: ClassificationTarget
    ) throws {
        let cleanedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPattern.isEmpty,
              categoryDefinitions.contains(where: { $0.id == categoryID }),
              matchKind != .contentContains || target == .files else {
            throw PreferencesError.invalidRule
        }
        var updated = preferences
        updated.customRules.append(
            .init(
                id: UUID().uuidString,
                categoryID: categoryID,
                matchKind: matchKind,
                pattern: cleanedPattern,
                target: target,
                isEnabled: true
            )
        )
        try persistPreferences(updated)
    }

    func removeCustomRule(_ id: String) throws {
        var updated = preferences
        updated.customRules.removeAll { $0.id == id }
        try persistPreferences(updated)
    }

    func setCustomRuleEnabled(_ id: String, isEnabled: Bool) throws {
        var updated = preferences
        guard let index = updated.customRules.firstIndex(where: { $0.id == id }) else { return }
        updated.customRules[index].isEnabled = isEnabled
        try persistPreferences(updated)
    }

    func updateAnalysisPreferences(contentAnalysisEnabled: Bool, ocrEnabled: Bool) throws {
        var updated = preferences
        updated.contentAnalysisEnabled = contentAnalysisEnabled
        updated.ocrEnabled = ocrEnabled
        try persistPreferences(updated)
    }

    func setRecoveryRetentionDays(_ days: Int) throws {
        var updated = preferences
        updated.recoveryRetentionDays = min(max(days, 1), 365)
        try persistPreferences(updated)
        Task { await performRecoveryMaintenance() }
    }

    func performRecoveryMaintenance() async {
        guard shouldLoadPersistedActivity, !isOperationActive else { return }
        do {
            let executor = FileOperationExecutor()
            _ = try await executor.pruneExpiredRecovery(retentionDays: preferences.recoveryRetentionDays)
            activity = Self.activitySessions(loadPersistedActivity: shouldLoadPersistedActivity)
        } catch {
            showNotice("Recovery cleanup could not finish: \(error.localizedDescription)")
        }
    }

    func startSampleScan() {
        loadSampleScenario()
        selectedRootBookmarkData = nil
        startScan(mode: .sample)
    }

    func chooseFolderForScan() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to organise"
        panel.prompt = "Scan Folder"
        panel.message = "Sortwell will scan this folder locally and show a review plan before any changes."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = startDroppedFolder(url)
    }

    @discardableResult
    func startDroppedFolder(_ url: URL) -> Bool {
        let standardURL = url.standardizedFileURL
        let accessed = standardURL.startAccessingSecurityScopedResource()
        defer { if accessed { standardURL.stopAccessingSecurityScopedResource() } }
        let values = try? standardURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true, values?.isPackage != true else {
            showNotice("Choose or drop a folder rather than an individual file.")
            return false
        }
        do {
            selectedRootBookmarkData = try standardURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            showNotice("Sortwell could not retain safe access to this folder: \(error.localizedDescription)")
            return false
        }
        startScan(mode: .real(standardURL))
        return true
    }

    func startScan(mode: ScanMode = .sample) {
        scanMode = mode
        activeScanID = UUID()
        latestScanResult = nil
        scanProgress = 0
        scanStatus = FolderScanProgress.Phase.inventory.rawValue
        scanCurrentPath = currentFolderName
        scanFilesInspected = 0
        scanProjectChecksCompleted = 0
        scanDuplicateChecksCompleted = 0
        route = .scan
    }

    func runScan(reduceMotion: Bool) async {
        guard let scanID = activeScanID else { return }
        if case .real(let folderURL) = scanMode {
            await runRealScan(folderURL: folderURL, scanID: scanID)
            return
        }

        let steps = reduceMotion ? 4 : 24
        for step in 1...steps {
            guard route == .scan, activeScanID == scanID, !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 90))
            guard activeScanID == scanID, !Task.isCancelled else { return }
            scanProgress = Double(step) / Double(steps)
            scanFilesInspected = Int(Double(scannedFileCount) * scanProgress)
            scanCurrentPath = currentScanPathDescription
        }
        guard route == .scan, activeScanID == scanID else { return }
        activeScanID = nil
        route = .summary
    }

    func cancelScan() {
        activeScanID = nil
        route = .welcome
    }

    func prepareForTermination() {
        switch route {
        case .scan:
            cancelScan()
        case .applying:
            stopApplying()
        default:
            break
        }
    }

    func beginReview(_ section: ReviewSection = .organisation) {
        reviewSection = section
        route = .review
    }

    func togglePlanItem(_ id: String) {
        guard let index = planItems.firstIndex(where: { $0.id == id }) else { return }
        planItems[index].isSelected.toggle()
    }

    func updatePlanCategory(_ category: String, for id: String) {
        guard let index = planItems.firstIndex(where: { $0.id == id }) else { return }
        planItems[index].proposedCategory = category
    }

    func selectCanonicalCopy(_ copyID: String, in groupID: String) {
        guard let index = duplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let group = duplicateGroups[index]
        guard group.copies.contains(where: { $0.id == copyID }) else { return }
        if group.copies.contains(where: \.isProtected),
           group.copies.first(where: { $0.id == copyID })?.isProtected != true {
            return
        }
        duplicateGroups[index].canonicalCopyID = copyID
        duplicateGroups[index].decision = .pending
    }

    func decideDuplicateGroup(_ decision: DuplicateDecision, groupID: String) {
        guard let index = duplicateGroups.firstIndex(where: { $0.id == groupID }) else { return }
        if decision == .moveOthersToTrash, !duplicateGroups[index].canApproveCleanup { return }
        duplicateGroups[index].decision = decision
    }

    func classifyNeedsReviewItem(_ id: String, as category: String?) {
        guard let index = needsReviewItems.firstIndex(where: { $0.id == id }) else { return }
        needsReviewItems[index].selectedCategory = category
        needsReviewItems[index].hasReviewedDecision = true
    }

    func beginApplying() {
        showConfirmation = false
        applyProgress = 0
        applyStatus = "Preparing approved actions"
        operationWasStopped = false
        route = .applying
    }

    func runApply(reduceMotion: Bool) async {
        if !isSampleData {
            await runRealApply()
            return
        }

        let steps = reduceMotion ? 5 : 28
        for step in 1...steps {
            guard route == .applying, !operationWasStopped else { return }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 90 : 85))
            applyProgress = Double(step) / Double(steps)
        }
        guard route == .applying, !operationWasStopped else { return }
        completeSession(didFinish: true)
    }

    func stopApplying() {
        guard route == .applying, !operationWasStopped else { return }
        operationWasStopped = true
        if applyIsSimulation {
            completeSession(didFinish: false)
        } else {
            applyStatus = "Finishing the current item before stopping"
        }
    }

    func completeSession(didFinish: Bool = true) {
        let completedMoves = didFinish
            ? organisationMoveCount
            : min(organisationMoveCount, Int(Double(organisationMoveCount) * applyProgress))
        let completedTrashActions = didFinish || applyProgress >= 0.9 ? approvedTrashCount : 0
        let sessionID = isSampleData ? "telegram-session" : "scan-\(stableID(currentFolderName + String(Date().timeIntervalSince1970)))"
        let session = ActivitySession(
            id: sessionID,
            folderName: currentFolderName,
            dateDescription: "Just now",
            moveCount: completedMoves,
            trashCount: completedTrashActions,
            isUndone: false
        )
        activity.removeAll { $0.id == session.id }
        activity.insert(session, at: 0)
        completedSessionID = session.id
        route = .results
    }

    func undoSession(_ id: String) {
        guard let index = activity.firstIndex(where: { $0.id == id }) else { return }
        if let journalPath = activity[index].journalPath {
            guard undoInProgressSessionID == nil, !activity[index].isUndone else { return }
            undoInProgressSessionID = id
            Task { await undoRealSession(id: id, journalPath: journalPath) }
            return
        }
        activity[index].isUndone = true
    }

    func openActivityDetail(_ session: ActivitySession) {
        guard let journalPath = session.journalPath else {
            showNotice("Per-file details are available for real organisation sessions.")
            return
        }
        do {
            activityDetailJournal = try FileOperationExecutor.loadJournal(at: URL(fileURLWithPath: journalPath))
            showActivityDetail = true
        } catch {
            showNotice("Sortwell could not open this activity journal: \(error.localizedDescription)")
        }
    }

    func revealOrganisedFiles() {
        guard !isSampleData, let rootURL = scanRootURL else {
            showNotice("Sample runs do not create an Organised Files folder.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([
            rootURL.appendingPathComponent("Organised Files", isDirectory: true)
        ])
    }

    func showNotice(_ message: String) {
        noticeMessage = message
        showNoticeAlert = true
    }

    func jump(to route: AppRoute) {
        guard !isOperationActive else {
            showNotice("Wait for the current operation to finish before changing screens.")
            return
        }
        if !isSampleData, route == .applying || route == .results {
            showNotice("Real file changes can only start from the final confirmation screen.")
            return
        }
        showConfirmation = false
        if route == .results, completedSessionID == nil {
            applyProgress = 1
            completeSession()
            return
        }
        self.route = route
    }

    func reset() {
        loadSampleScenario()
        route = .welcome
        activeScanID = nil
        scanMode = .sample
        selectedRootBookmarkData = nil
        reviewSection = .organisation
        latestScanResult = nil
        scanStatus = FolderScanProgress.Phase.inventory.rawValue
        scanCurrentPath = "Telegram/Hcl Documents/..."
        scanFilesInspected = 0
        scanProjectChecksCompleted = 0
        scanDuplicateChecksCompleted = 0
        scanProgress = 0
        applyProgress = 0
        showConfirmation = false
        showInspector = false
        showNoticeAlert = false
        operationWasStopped = false
        completedSessionID = nil
        undoInProgressSessionID = nil
        applyStatus = "Preparing approved actions"
        activity = Self.activitySessions(loadPersistedActivity: shouldLoadPersistedActivity)
    }

    private func runRealScan(folderURL: URL, scanID: UUID) async {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let classifier = FileClassifier(preferences: preferences)
            let scanner = FolderScanner(
                classifier: classifier,
                contentAnalyzer: LocalContentAnalyzer(preferences: preferences)
            )
            let result = try await scanner.scan(rootURL: folderURL) { [weak self] progress in
                await self?.updateScanProgress(progress, scanID: scanID)
            }
            guard route == .scan, activeScanID == scanID, !Task.isCancelled else { return }
            apply(result)
            scanProgress = 1
            activeScanID = nil
            route = .summary
        } catch is CancellationError {
            return
        } catch {
            guard route == .scan, activeScanID == scanID else { return }
            activeScanID = nil
            route = .welcome
            showNotice("Sortwell could not scan \(folderURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func runRealApply() async {
        guard let rootURL = scanRootURL else {
            route = .review
            showNotice("Sortwell needs a completed real scan before it can apply changes.")
            return
        }

        let accessed = rootURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let plan = try makeOperationPlan(sessionID: UUID().uuidString)
            let executor = FileOperationExecutor()
            let journal = try await executor.apply(
                plan,
                shouldStop: { [weak self] in
                    await self?.operationWasStopped ?? true
                }
            ) { [weak self] progress in
                await self?.updateApplyProgress(progress)
            }
            recordCompletedSession(from: journal)
            guard route == .applying else { return }
            operationWasStopped = false
            applyProgress = 1
            route = .results
            await performRecoveryMaintenance()
        } catch let FileOperationError.partialApply(journal, reason) {
            recordCompletedSession(from: journal)
            let stoppedByUser = operationWasStopped && reason == FileOperationError.userStopped.localizedDescription
            operationWasStopped = stoppedByUser
            guard route == .applying else { return }
            if stoppedByUser {
                applyStatus = reason
                route = .results
            } else {
                route = .activity
                showNotice("Apply stopped safely. Completed actions were recorded for Undo. \(reason)")
            }
        } catch {
            guard route == .applying else { return }
            route = .review
            showNotice("Sortwell could not apply the approved plan: \(error.localizedDescription)")
        }
    }

    private func updateScanProgress(_ progress: FolderScanProgress, scanID: UUID) {
        guard activeScanID == scanID, route == .scan else { return }
        scanStatus = progress.phase.rawValue
        scanCurrentPath = displayPath(for: URL(fileURLWithPath: progress.currentPath), root: scanRootURL)
        switch progress.phase {
        case .inventory:
            scanFilesInspected = progress.completed
            scanProgress = min(max(0.18 + progress.fraction * 0.34, scanProgress), 0.58)
        case .projects:
            scanProjectChecksCompleted = progress.completed
            scanProgress = min(max(0.04 + progress.fraction * 0.14, scanProgress), 0.22)
        case .hashing:
            scanDuplicateChecksCompleted = progress.completed
            scanProgress = min(max(0.58 + progress.fraction * 0.32, scanProgress), 0.92)
        case .planning:
            scanProgress = 0.96
        }
    }

    private func updateApplyProgress(_ progress: FileOperationProgress) {
        applyProgress = progress.fraction
        applyStatus = progress.currentAction
    }

    private var scanRootURL: URL? {
        if case .real(let url) = scanMode { return url }
        return nil
    }

    private func apply(_ result: FolderScanResult) {
        latestScanResult = result
        categories = result.categoryDefinitions.map { definition in
            SortwellCategory(
                id: definition.id,
                title: definition.title,
                icon: definition.icon,
                totalCount: result.organisationItems.filter { $0.category == definition.title }.count
            )
        }
        planItems = result.organisationItems.map { item in
            PlanItem(
                id: item.id,
                name: item.name,
                kind: item.isDirectory ? .folder : .file,
                currentPath: displayPath(for: item.url, root: result.rootURL),
                proposedCategory: item.category,
                explanation: item.explanation,
                size: formattedBytes(item.size),
                isSelected: true,
                fileURL: item.url
            )
        }
        needsReviewItems = result.needsReviewItems.map { item in
            NeedsReviewItem(
                id: item.id,
                name: item.name,
                kindDescription: item.kindDescription,
                currentPath: displayPath(for: item.url, root: result.rootURL),
                reason: item.reason,
                selectedCategory: nil,
                hasReviewedDecision: false,
                fileURL: item.url
            )
        }
        protectedProjects = result.protectedProjects.map { project in
            ProtectedProject(
                id: project.id,
                name: project.name,
                path: displayPath(for: project.url, root: result.rootURL),
                containedFiles: project.containedFiles,
                reason: project.reason
            )
        }
        duplicateGroups = result.duplicateGroups.map { group in
            let copies = group.copies.map { copy in
                DuplicateCopy(
                    id: copy.id,
                    name: copy.name,
                    path: displayPath(for: copy.url, root: result.rootURL),
                    size: formattedBytes(copy.size),
                    isInsideProject: copy.isInsideProject,
                    protectionReason: copy.protectionReason,
                    fileURL: copy.url
                )
            }
            return DuplicateGroup(
                id: group.id,
                title: group.title,
                hashPrefix: String(group.sha256.prefix(11)),
                copies: copies,
                canonicalCopyID: copies.first(where: \.isProtected)?.id ?? copies.first?.id,
                decision: .pending
            )
        }

        selectedPlanItemID = planItems.first?.id
        selectedDuplicateGroupID = duplicateGroups.first?.id
        selectedNeedsReviewID = needsReviewItems.first?.id
        selectedProjectID = protectedProjects.first?.id
    }

    private func makeOperationPlan(sessionID: String) throws -> FileOperationPlan {
        guard let result = latestScanResult else { throw StoreOperationError.missingScanResult }

        let removableCopyIDs = Set(duplicateGroups.flatMap(\.removableCopyIDs))
        let planByID = Dictionary(uniqueKeysWithValues: planItems.map { ($0.id, $0) })
        let needsReviewByID = Dictionary(uniqueKeysWithValues: needsReviewItems.map { ($0.id, $0) })

        var moves: [FileMoveOperation] = result.organisationItems.compactMap { item in
            guard let planItem = planByID[item.id], planItem.isSelected, !removableCopyIDs.contains(item.id) else { return nil }
            return .init(
                id: item.id,
                sourceURL: item.url,
                category: planItem.proposedCategory,
                expectedSnapshot: .init(size: item.size, modificationDate: item.modificationDate)
            )
        }

        moves += result.needsReviewItems.compactMap { item in
            guard let reviewItem = needsReviewByID[item.id], let category = reviewItem.selectedCategory, !removableCopyIDs.contains(item.id) else { return nil }
            return .init(
                id: item.id,
                sourceURL: item.url,
                category: category,
                expectedSnapshot: .init(size: item.size, modificationDate: item.modificationDate)
            )
        }

        let trashOperations = result.duplicateGroups
            .flatMap { group in
                group.copies.compactMap { copy -> FileTrashOperation? in
                    guard removableCopyIDs.contains(copy.id), !copy.isProtected else { return nil }
                    return .init(
                        id: copy.id,
                        sourceURL: copy.url,
                        expectedSnapshot: .init(size: copy.size, modificationDate: copy.modificationDate),
                        expectedSHA256: group.sha256
                    )
                }
            }
            .sorted { $0.sourceURL.path < $1.sourceURL.path }

        return .init(
            id: sessionID,
            rootURL: result.rootURL,
            rootBookmarkData: selectedRootBookmarkData,
            moveOperations: moves,
            trashOperations: trashOperations
        )
    }

    private func recordCompletedSession(from journal: OperationJournal) {
        let session = ActivitySession(
            id: journal.id,
            folderName: currentFolderName,
            dateDescription: "Just now",
            moveCount: journal.moveCount,
            trashCount: journal.trashCount,
            isUndone: false,
            journalPath: journal.journalPath,
            isPartial: journal.completedAt == nil || journal.failureDescription != nil
        )
        activity.removeAll { $0.id == session.id }
        activity.insert(session, at: 0)
        completedSessionID = session.id
    }

    private func undoRealSession(id: String, journalPath: String) async {
        do {
            let executor = FileOperationExecutor()
            _ = try await executor.undo(journalURL: URL(fileURLWithPath: journalPath)) { _ in }
            if let index = activity.firstIndex(where: { $0.id == id }) {
                activity[index].isUndone = true
            }
        } catch {
            showNotice("Sortwell could not undo this session: \(error.localizedDescription)")
        }
        undoInProgressSessionID = nil
        await performRecoveryMaintenance()
    }

    private func loadSampleScenario() {
        planItems = TelegramScenario.planItems
        duplicateGroups = TelegramScenario.duplicateGroups
        needsReviewItems = TelegramScenario.needsReviewItems
        categories = Self.sampleCategories(preferences: preferences)
        protectedProjects = TelegramScenario.protectedProjects
        selectedPlanItemID = TelegramScenario.planItems.first?.id
        selectedDuplicateGroupID = TelegramScenario.duplicateGroups.first?.id
        selectedNeedsReviewID = TelegramScenario.needsReviewItems.first?.id
        selectedProjectID = TelegramScenario.protectedProjects.first?.id
    }

    private func displayPath(for url: URL, root: URL?) -> String {
        guard let root else { return url.path }
        let standardRoot = root.standardizedFileURL
        let standardURL = url.standardizedFileURL
        let rootPath = standardRoot.path
        let path = standardURL.path
        guard path.hasPrefix(rootPath) else { return path }
        let suffix = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? standardRoot.lastPathComponent : "\(standardRoot.lastPathComponent)/\(suffix)"
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func stableID(_ value: String) -> String {
        String(value.hashValue.magnitude, radix: 16)
    }

    private func persistPreferences(_ updated: SortwellPreferences) throws {
        try preferencesRepository.save(updated)
        preferences = updated
        if isSampleData, route == .welcome {
            categories = Self.sampleCategories(preferences: updated)
        }
    }

    private static func sampleCategories(preferences: SortwellPreferences) -> [SortwellCategory] {
        TelegramScenario.categories + preferences.customCategories.map {
            SortwellCategory(id: $0.id, title: $0.title, icon: $0.icon, totalCount: 0)
        }
    }

    private static func activitySessions(loadPersistedActivity: Bool) -> [ActivitySession] {
        let realSessions: [ActivitySession]
        if loadPersistedActivity {
            realSessions = FileOperationExecutor.loadPersistedJournals().map { journal in
                ActivitySession(
                    id: journal.id,
                    folderName: URL(fileURLWithPath: journal.rootPath).lastPathComponent,
                    dateDescription: journal.createdAt.formatted(date: .abbreviated, time: .shortened),
                    moveCount: journal.moveCount,
                    trashCount: journal.trashCount,
                    isUndone: journal.undoneAt != nil,
                    journalPath: journal.journalPath,
                    isPartial: journal.completedAt == nil || journal.failureDescription != nil
                )
            }
        } else {
            realSessions = []
        }
        return loadPersistedActivity ? realSessions : TelegramScenario.previousActivity
    }
}

private enum StoreOperationError: LocalizedError {
    case missingScanResult

    var errorDescription: String? {
        switch self {
        case .missingScanResult:
            "No completed real scan is available."
        }
    }
}
