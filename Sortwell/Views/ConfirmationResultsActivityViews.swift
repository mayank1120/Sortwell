import SwiftUI

struct ConfirmationView: View {
    @Environment(PrototypeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to organise \(store.currentFolderName)")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text(store.applyIsSimulation ? "Review the complete action summary before applying it. The sample run is simulated." : "Review the complete action summary before applying it. Approved changes will be performed locally and recorded for undo.")
                        .font(.system(size: 12))
                        .foregroundStyle(SortwellPalette.secondaryText)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(SortwellPalette.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close confirmation")
                .keyboardShortcut(.cancelAction)
            }
            .padding(24)

            DividerLine()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ConfirmationDestination()

                    ConfirmationSection(title: "Organisation", icon: "folder.badge.plus") {
                        ConfirmationRow(value: store.organisationMoveCount.formatted(), label: "top-level items will move into Organised Files")
                        ConfirmationRow(value: store.protectedProjectCount.formatted(), label: "software projects will remain in place")
                        ConfirmationRow(value: store.reviewedKeepInPlaceCount.formatted(), label: "reviewed items are confirmed to remain in place")
                        ConfirmationRow(value: store.unresolvedItemCount.formatted(), label: "unresolved items will remain untouched")
                    }

                    ConfirmationSection(title: "Duplicate cleanup", icon: "doc.on.doc") {
                        ConfirmationRow(value: store.reviewedDuplicateGroupCount.formatted(), label: "of \(store.duplicateGroups.count.formatted()) exact duplicate groups reviewed")
                        ConfirmationRow(value: store.approvedTrashCount.formatted(), label: "verified copies will move to Trash")
                        ConfirmationRow(value: (store.duplicateGroups.count - store.reviewedDuplicateGroupCount).formatted(), label: "unreviewed groups will remain untouched")
                    }

                    ConfirmationSection(title: "Safety checks", icon: "checkmark.shield") {
                        SafetyCheckRow(text: store.applyIsSimulation ? "This sample run previews the workflow without filesystem changes" : "A local undo journal will be written as actions complete")
                        SafetyCheckRow(text: "Existing destination names are never overwritten")
                        SafetyCheckRow(text: "Project contents and locations remain untouched")
                        SafetyCheckRow(text: "An activity record will be created")
                    }

                    Text("Undo is available while affected files remain accessible and items moved to Trash have not been removed.")
                        .font(.system(size: 10))
                        .foregroundStyle(SortwellPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }

            DividerLine()

            HStack {
                Button("Back to Review") {
                    dismiss()
                }
                .buttonStyle(SortwellSecondaryButtonStyle())
                Spacer()
                StatusPill(title: "4 safety checks passed", icon: "checkmark.shield")
                Button("Apply \(store.totalActionCount) Actions") {
                    store.beginApplying()
                }
                .buttonStyle(SortwellPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(store.totalActionCount == 0)
            }
            .padding(.horizontal, 24)
            .frame(height: 68)
            .background(SortwellPalette.surface)
        }
        .frame(width: 650, height: 680)
        .background(SortwellPalette.canvas)
    }
}

private struct ConfirmationDestination: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("DESTINATION")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(SortwellPalette.secondaryText)
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(SortwellPalette.sage)
                Text(store.destinationDisplayPath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Spacer()
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 9).fill(SortwellPalette.sageSoft))
        }
    }
}

private struct ConfirmationSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(SortwellPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(SortwellPalette.border, lineWidth: 1))
            )
        }
    }
}

private struct ConfirmationRow: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 13) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(SortwellPalette.secondaryText)
            Spacer()
        }
        .padding(.vertical, 9)
    }
}

private struct SafetyCheckRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SortwellPalette.sage)
            Text(text)
                .font(.system(size: 12))
            Spacer()
        }
        .padding(.vertical, 9)
    }
}

struct ApplyingView: View {
    @Environment(PrototypeStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ScreenHeading(
                eyebrow: store.applyIsSimulation ? "Simulation" : "Applying locally",
                title: "Organising \(store.currentFolderName)",
                subtitle: store.applyIsSimulation ? "This sample run demonstrates the approved workflow. No files are being moved or sent to Trash." : "Sortwell is performing only the approved actions and recording each completed step for undo."
            )

            VStack(alignment: .leading, spacing: 13) {
                ProgressView(value: store.applyProgress)
                    .tint(SortwellPalette.sage)
                    .controlSize(.large)
                    .accessibilityLabel("Apply progress")
                    .accessibilityValue("\(Int(store.applyProgress * 100)) per cent")

                HStack {
                    Text("\(Int(store.applyProgress * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text("\(completedActionCount) of \(store.totalActionCount) \(store.applyIsSimulation ? "simulated actions" : "approved actions")")
                        .font(.system(size: 12))
                        .foregroundStyle(SortwellPalette.secondaryText)
                }
            }

            Panel {
                VStack(alignment: .leading, spacing: 16) {
                    Label(currentOperation, systemImage: "arrow.right.circle")
                        .font(.system(size: 14, weight: .semibold))
                    DividerLine()
                    Label("Activity record active", systemImage: "list.bullet.clipboard")
                        .font(.system(size: 12))
                        .foregroundStyle(SortwellPalette.sage)
                    Label("Existing destination files are never overwritten", systemImage: "character.cursor.ibeam")
                        .font(.system(size: 12))
                        .foregroundStyle(SortwellPalette.sage)
                    Label("Protected projects remain in place", systemImage: "lock.shield")
                        .font(.system(size: 12))
                        .foregroundStyle(SortwellPalette.sage)
                }
            }

            HStack {
                Text(store.applyIsSimulation ? "Keep this window open until the simulation is complete." : "Keep this window open until the operation is complete.")
                    .font(.system(size: 11))
                    .foregroundStyle(SortwellPalette.secondaryText)
                Spacer()
                Button(store.operationWasStopped ? "Stop Requested" : "Stop After Current Item") {
                    store.stopApplying()
                }
                .buttonStyle(SortwellSecondaryButtonStyle())
                .disabled(store.operationWasStopped)
            }
        }
        .frame(maxWidth: 760)
        .padding(54)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await store.runApply(reduceMotion: reduceMotion)
        }
    }

    private var completedActionCount: Int {
        min(store.totalActionCount, Int(Double(store.totalActionCount) * store.applyProgress))
    }

    private var currentOperation: String {
        if !store.applyIsSimulation { return store.applyStatus }
        if store.applyProgress < 0.35 { return "Creating the Organised Files category structure" }
        if store.applyProgress < 0.78 { return "Simulating approved organisation moves" }
        return "Recording approved Trash actions and undo details"
    }
}

struct ResultsView: View {
    @Environment(PrototypeStore.self) private var store

    private var currentSession: ActivitySession? {
        guard let id = store.completedSessionID else { return nil }
        return store.activity.first { $0.id == id }
    }

    private var wasUndone: Bool {
        currentSession?.isUndone == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(SortwellPalette.sageSoft)
                            .frame(width: 58, height: 58)
                        Image(systemName: wasUndone ? "arrow.uturn.backward" : (store.operationWasStopped ? "pause.fill" : "checkmark"))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(SortwellPalette.sage)
                    }
                    ScreenHeading(
                        eyebrow: resultEyebrow(wasUndone: wasUndone),
                        title: wasUndone ? "\(store.currentFolderName) was restored" : (store.operationWasStopped ? "Completed actions were recorded" : "\(store.currentFolderName) is organised"),
                        subtitle: resultSubtitle(wasUndone: wasUndone)
                    )
                }

                HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 0) {
                        LedgerMetric(value: (currentSession?.moveCount ?? store.organisationMoveCount).formatted(), label: moveResultLabel, tint: SortwellPalette.sage)
                        DividerLine()
                        LedgerMetric(value: (currentSession?.trashCount ?? store.approvedTrashCount).formatted(), label: trashResultLabel)
                        DividerLine()
                        LedgerMetric(value: store.protectedProjectCount.formatted(), label: "software projects preserved in place")
                        DividerLine()
                        LedgerMetric(value: store.needsReviewItemsKeptInPlaceCount.formatted(), label: "review items left untouched", tint: SortwellPalette.amber)
                    }
                    .frame(maxWidth: .infinity)

                    Panel {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Organised Files", systemImage: "folder.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SortwellPalette.sage)
                            ForEach(store.categories) { category in
                                HStack {
                                    Image(systemName: category.icon)
                                        .frame(width: 18)
                                    Text(category.title)
                                    Spacer()
                                    Text(store.completedCategoryMoveCount(category.title).formatted())
                                        .monospacedDigit()
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(SortwellPalette.secondaryText)
                            }
                        }
                    }
                    .frame(width: 350)
                }

                HStack(spacing: 10) {
                    Button(wasUndone ? "View Undo Activity" : "Reveal Organised Files") {
                        if wasUndone {
                            store.route = .activity
                        } else {
                            store.revealOrganisedFiles()
                        }
                    }
                        .buttonStyle(SortwellPrimaryButtonStyle())
                        .help(store.applyIsSimulation ? "Sample runs do not create an Organised Files folder" : "Reveal the Organised Files folder in Finder")
                    Button("View Activity") {
                        store.route = .activity
                    }
                    .buttonStyle(SortwellSecondaryButtonStyle())
                    if let id = currentSession?.id, currentSession?.isUndone == false {
                        Button("Undo This Organisation") {
                            store.undoSession(id)
                            store.route = .activity
                        }
                        .buttonStyle(SortwellSecondaryButtonStyle())
                    }
                    Spacer()
                    Button("Organise More") {
                        store.reset()
                    }
                    .buttonStyle(SortwellSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: 960)
            .padding(46)
            .frame(maxWidth: .infinity)
        }
    }

    private func resultSubtitle(wasUndone: Bool) -> String {
        if wasUndone { return "The activity record now shows this organisation as undone." }
        if store.applyIsSimulation { return "This sample run changed no files. The results below demonstrate the final experience." }
        if store.operationWasStopped { return "Sortwell stopped safely after the current item. Completed actions were recorded for Undo, and all remaining items were left untouched." }
        return "Approved moves and Trash actions were completed on this Mac and recorded in a local undo journal."
    }

    private func resultEyebrow(wasUndone: Bool) -> String {
        if store.applyIsSimulation {
            return wasUndone ? "Simulation undone" : (store.operationWasStopped ? "Simulation stopped safely" : "Simulation complete")
        }
        return wasUndone ? "Undo complete" : (store.operationWasStopped ? "Stopped safely" : "Operation complete")
    }

    private var moveResultLabel: String {
        if wasUndone { return store.applyIsSimulation ? "moves restored in the undo simulation" : "moves restored" }
        return store.applyIsSimulation ? "organisation moves simulated" : "organisation moves completed"
    }

    private var trashResultLabel: String {
        if wasUndone { return "Trash actions restored" }
        return store.applyIsSimulation ? "verified copies marked for Trash" : "verified copies moved to Trash"
    }
}

struct ActivityView: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top) {
                ScreenHeading(
                    eyebrow: "Recorded locally",
                    title: "Activity and Undo",
                    subtitle: "Review organisation sessions and their recovery status."
                )
                Spacer()
                Button("Back") {
                    store.route = store.completedSessionID == nil ? .welcome : .results
                }
                .buttonStyle(SortwellSecondaryButtonStyle())
            }

            if store.unreadableJournalCount > 0 {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SortwellPalette.amber)
                    Text("Sortwell could not read \(store.unreadableJournalCount) saved activity \(store.unreadableJournalCount == 1 ? "journal" : "journals"). Existing files were left unchanged.")
                        .font(.system(size: 11))
                        .foregroundStyle(SortwellPalette.secondaryText)
                    Spacer()
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 10).fill(SortwellPalette.amberSoft))
            }

            if store.journalDirectoryReadFailed {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SortwellPalette.amber)
                    Text("Sortwell could not access the saved Activity folder. Existing files were left unchanged; restore folder access and relaunch Sortwell to try again.")
                        .font(.system(size: 11))
                        .foregroundStyle(SortwellPalette.secondaryText)
                    Spacer()
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 10).fill(SortwellPalette.amberSoft))
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.activity) { session in
                        ActivityRow(session: session)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(SortwellPalette.blue)
                Text("Undo is available while affected files and destinations remain accessible. Items moved to Trash cannot be restored after Trash is emptied.")
                    .font(.system(size: 11))
                    .foregroundStyle(SortwellPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(15)
            .background(RoundedRectangle(cornerRadius: 10).fill(SortwellPalette.surface))
        }
        .frame(maxWidth: 880)
        .padding(46)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ActivityRow: View {
    @Environment(PrototypeStore.self) private var store
    let session: ActivitySession

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(session.isUndone ? SortwellPalette.raisedSurface : SortwellPalette.sageSoft)
                    .frame(width: 42, height: 42)
                Image(systemName: session.isUndone ? "arrow.uturn.backward" : "folder")
                    .foregroundStyle(session.isUndone ? SortwellPalette.secondaryText : SortwellPalette.sage)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.folderName)
                        .font(.system(size: 13, weight: .semibold))
                    if session.isUndone {
                        StatusPill(title: "Undone", icon: "arrow.uturn.backward", tint: SortwellPalette.secondaryText, background: SortwellPalette.raisedSurface)
                    } else if session.isPartial {
                        StatusPill(title: "Interrupted", icon: "exclamationmark.triangle", tint: SortwellPalette.amber, background: SortwellPalette.amberSoft)
                    }
                }
                Text("\(session.moveCount) moves · \(session.trashCount) Trash actions · \(session.dateDescription)")
                    .font(.system(size: 11))
                    .foregroundStyle(SortwellPalette.secondaryText)
            }
            Spacer()
            Button("View") {
                store.openActivityDetail(session)
            }
            .buttonStyle(SortwellSecondaryButtonStyle())
            .disabled(session.journalPath == nil)
            .accessibilityLabel("View \(session.folderName) activity details")
            if !session.isUndone {
                Button(store.undoInProgressSessionID == session.id ? "Undoing…" : "Undo") {
                    store.undoSession(session.id)
                }
                .buttonStyle(SortwellSecondaryButtonStyle())
                .disabled(store.undoInProgressSessionID != nil)
                .accessibilityLabel("Undo \(session.folderName) organisation")
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(SortwellPalette.surface)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(SortwellPalette.border, lineWidth: 1))
        )
    }
}

struct ActivityDetailView: View {
    @Environment(PrototypeStore.self) private var store
    let journal: OperationJournal?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity Details")
                        .font(.system(size: 20, weight: .semibold))
                    Text(journal.map { URL(fileURLWithPath: $0.rootPath).lastPathComponent } ?? "Unavailable")
                        .font(.system(size: 12))
                        .foregroundStyle(SortwellPalette.secondaryText)
                }
                Spacer()
                Button("Close") { store.showActivityDetail = false }
                    .buttonStyle(SortwellSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(22)
            DividerLine()

            if let journal {
                VStack(spacing: 0) {
                    if let failureDescription = journal.failureDescription {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(SortwellPalette.amber)
                            Text("Operation stopped: \(failureDescription)")
                                .font(.system(size: 11))
                                .foregroundStyle(SortwellPalette.secondaryText)
                            Spacer()
                        }
                        .padding(14)
                        .background(SortwellPalette.amberSoft)
                    }

                    Table(journal.entries) {
                        TableColumn("Action") { entry in
                            Label(entry.action == .move ? "Move" : "Trash", systemImage: entry.action == .move ? "folder" : "trash")
                        }
                        .width(80)
                        TableColumn("Original location") { entry in
                            Text(entry.sourcePath).font(.system(size: 10, design: .monospaced)).lineLimit(2)
                        }
                        TableColumn("Destination") { entry in
                            Text(entry.destinationPath ?? entry.recoveryPath ?? "Not applied")
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(2)
                        }
                        TableColumn("Status") { entry in
                            Text(entry.status.title)
                        }
                        .width(85)
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("Journal unavailable", systemImage: "list.bullet.clipboard")
            }
        }
        .frame(width: 900, height: 560)
        .background(SortwellPalette.canvas)
    }
}

private extension JournalActionStatus {
    var title: String {
        switch self {
        case .planned: "Interrupted"
        case .completed: "Completed"
        case .undone: "Undone"
        case .notApplied: "Not applied"
        }
    }
}
