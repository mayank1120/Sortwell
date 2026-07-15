import XCTest
@testable import Sortwell

@MainActor
final class PrototypeStoreTests: XCTestCase {
    func testTelegramScenarioCounts() {
        let store = PrototypeStore()

        XCTAssertEqual(store.duplicateGroups.count, 7)
        XCTAssertEqual(store.needsReviewItems.count, 6)
        XCTAssertEqual(store.protectedProjectCount, 30)
        XCTAssertEqual(store.planItems.count, 124)
        XCTAssertEqual(store.organisationMoveCount, 124)
        XCTAssertEqual(store.organisationMoveCount + store.needsReviewItems.count + store.protectedProjectCount, store.totalTopLevelItems)
        XCTAssertEqual(store.approvedTrashCount, 0)
    }

    func testDuplicateCleanupRequiresExplicitDecision() {
        let store = PrototypeStore()
        let group = try! XCTUnwrap(store.duplicateGroups.first)

        XCTAssertEqual(group.decision, .pending)
        XCTAssertEqual(store.approvedTrashCount, 0)

        store.decideDuplicateGroup(.moveOthersToTrash, groupID: group.id)

        XCTAssertEqual(store.approvedTrashCount, 2)
    }

    func testNeedsReviewDefaultsToKeepInPlace() {
        let store = PrototypeStore()

        XCTAssertEqual(store.unresolvedItemCount, 6)
        XCTAssertTrue(store.needsReviewItems.allSatisfy { $0.selectedCategory == nil })
    }

    func testProtectedProjectRecommendationIsKeepInPlace() {
        let store = PrototypeStore()

        XCTAssertEqual(store.protectedProjects.count, 7)
        XCTAssertTrue(store.protectedProjects.allSatisfy { !$0.path.isEmpty })
        XCTAssertEqual(store.protectedProjectCount, 30)
    }

    func testProjectCopyCannotBeReplacedAsCanonical() {
        let store = PrototypeStore()
        let group = try! XCTUnwrap(store.duplicateGroups.first { $0.id == "do-tar" })
        let projectCopy = try! XCTUnwrap(group.copies.first { $0.isInsideProject })
        let looseCopy = try! XCTUnwrap(group.copies.first { !$0.isInsideProject })

        XCTAssertEqual(group.canonicalCopyID, projectCopy.id)
        store.selectCanonicalCopy(looseCopy.id, in: group.id)

        XCTAssertEqual(store.duplicateGroups.first { $0.id == group.id }?.canonicalCopyID, projectCopy.id)
    }

    func testInvalidCanonicalAndCleanupAreRejected() {
        let store = PrototypeStore()
        let groupID = try! XCTUnwrap(store.duplicateGroups.first?.id)

        store.selectCanonicalCopy("missing-copy", in: groupID)
        XCTAssertNotEqual(store.duplicateGroups.first?.canonicalCopyID, "missing-copy")

        store.duplicateGroups[0].canonicalCopyID = nil
        store.decideDuplicateGroup(.moveOthersToTrash, groupID: groupID)
        XCTAssertEqual(store.duplicateGroups[0].decision, .pending)
    }

    func testProjectCopiesAreNeverRemovable() {
        let group = DuplicateGroup(
            id: "multi-project",
            title: "Shared project file",
            hashPrefix: "abc",
            copies: [
                .init(id: "project-a", name: "config.yml", path: "Project A/config.yml", size: "1 KB", isInsideProject: true),
                .init(id: "project-b", name: "config.yml", path: "Project B/config.yml", size: "1 KB", isInsideProject: true),
                .init(id: "loose", name: "config copy.yml", path: "config copy.yml", size: "1 KB", isInsideProject: false)
            ],
            canonicalCopyID: "project-a",
            decision: .moveOthersToTrash
        )

        XCTAssertEqual(group.removableCopyIDs, ["loose"])
    }

    func testNeedsReviewDecisionsUpdateActionCounts() {
        let store = PrototypeStore()
        let item = try! XCTUnwrap(store.needsReviewItems.first)
        let initialFinanceCount = store.categoryMoveCount("Finance & Bills")

        store.classifyNeedsReviewItem(item.id, as: "Finance & Bills")

        XCTAssertEqual(store.unresolvedItemCount, 5)
        XCTAssertEqual(store.organisationMoveCount, 125)
        XCTAssertEqual(store.categoryMoveCount("Finance & Bills"), initialFinanceCount + 1)

        let second = try! XCTUnwrap(store.needsReviewItems.dropFirst().first)
        store.classifyNeedsReviewItem(second.id, as: nil)
        XCTAssertEqual(store.unresolvedItemCount, 4)
        XCTAssertEqual(store.reviewedKeepInPlaceCount, 1)
        XCTAssertEqual(store.organisationMoveCount, 125)
    }

    func testChangingCategoryUpdatesAggregateCounts() {
        let store = PrototypeStore()
        let item = try! XCTUnwrap(store.planItems.first)
        let oldCount = store.categoryMoveCount(item.proposedCategory)
        let newCount = store.categoryMoveCount("Other Documents")

        store.updatePlanCategory("Other Documents", for: item.id)

        XCTAssertEqual(store.categoryMoveCount(item.proposedCategory), oldCount - 1)
        XCTAssertEqual(store.categoryMoveCount("Other Documents"), newCount + 1)
    }

    func testStoppingImmediatelyRecordsNoActions() {
        let store = PrototypeStore()
        let group = try! XCTUnwrap(store.duplicateGroups.first)
        store.decideDuplicateGroup(.moveOthersToTrash, groupID: group.id)
        store.beginApplying()

        store.stopApplying()

        XCTAssertEqual(store.activity.first?.moveCount, 0)
        XCTAssertEqual(store.activity.first?.trashCount, 0)
        XCTAssertTrue(store.operationWasStopped)
    }

    func testRealStopWaitsForExecutor() {
        let store = PrototypeStore(loadPersistedActivity: false)
        store.scanMode = .real(FileManager.default.temporaryDirectory)
        store.route = .applying

        store.stopApplying()

        XCTAssertEqual(store.route, .applying)
        XCTAssertTrue(store.operationWasStopped)
        XCTAssertEqual(store.applyStatus, "Finishing the current item before stopping")
    }

    func testAllSafeDuplicateGroupsProduceNineExplicitRemovableIDs() {
        let store = PrototypeStore()
        for group in store.duplicateGroups {
            store.decideDuplicateGroup(.moveOthersToTrash, groupID: group.id)
        }

        XCTAssertEqual(store.approvedTrashCount, 9)
        XCTAssertEqual(store.duplicateGroups.flatMap(\.removableCopyIDs).count, 9)
        XCTAssertTrue(store.duplicateGroups.flatMap(\.removableCopyIDs).allSatisfy { id in
            store.duplicateGroups.flatMap(\.copies).first { $0.id == id }?.isInsideProject == false
        })
    }

    func testApprovedDuplicateTrashIsNotAlsoCountedAsMove() throws {
        let store = PrototypeStore(loadPersistedActivity: false)
        let group = try XCTUnwrap(store.duplicateGroups.first)
        let removableID = try XCTUnwrap(group.candidateRemovableCopyIDs.first)
        store.planItems.append(
            .init(
                id: removableID,
                name: "duplicate.txt",
                kind: .file,
                currentPath: "Telegram/duplicate.txt",
                proposedCategory: "Other Documents",
                explanation: "Test fixture",
                size: "1 KB",
                isSelected: true
            )
        )
        let moveCountBeforeApproval = store.organisationMoveCount

        store.decideDuplicateGroup(.moveOthersToTrash, groupID: group.id)

        XCTAssertEqual(store.organisationMoveCount, moveCountBeforeApproval - 1)
        XCTAssertEqual(store.totalActionCount, store.organisationMoveCount + store.approvedTrashCount)
    }

    func testProjectDuplicatePathsMatchProtectedProjects() {
        let store = PrototypeStore()
        let projectCopies = store.duplicateGroups.flatMap(\.copies).filter(\.isInsideProject)

        XCTAssertTrue(projectCopies.allSatisfy { copy in
            store.protectedProjects.contains { copy.path.hasPrefix($0.path + "/") }
        })
    }

    func testResetClearsMutablePrototypeState() {
        let store = PrototypeStore(loadPersistedActivity: false)
        store.togglePlanItem(store.planItems[0].id)
        store.classifyNeedsReviewItem(store.needsReviewItems[0].id, as: "Finance & Bills")
        store.undoSession(store.activity[0].id)
        store.showInspector = true

        store.reset()

        XCTAssertEqual(store.organisationMoveCount, 124)
        XCTAssertEqual(store.unresolvedItemCount, 6)
        XCTAssertFalse(store.activity[0].isUndone)
        XCTAssertFalse(store.showInspector)
    }
}
