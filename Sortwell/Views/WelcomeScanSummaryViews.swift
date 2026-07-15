import SwiftUI

struct WelcomeView: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: max(48, geometry.size.width * 0.07)) {
                    VStack(alignment: .leading, spacing: 26) {
                        ScreenHeading(
                            eyebrow: "Private by design",
                            title: "Bring order to your files, safely.",
                            subtitle: "Sortwell reviews everything locally and shows you a clear plan before making any changes."
                        )

                        VStack(alignment: .leading, spacing: 13) {
                            AssuranceRow(icon: "laptopcomputer", text: "Your files stay on this Mac")
                            AssuranceRow(icon: "eye", text: "Nothing changes until you approve")
                            AssuranceRow(icon: "list.bullet.clipboard", text: "Every action is recorded for review")
                        }

                        Button {
                            store.chooseFolderForScan()
                        } label: {
                            Label("Choose Folder…", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(SortwellPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("Opens a folder picker and starts a local read-only scan")
                    }
                    .frame(maxWidth: 450, alignment: .leading)

                    FolderDropZone(
                        action: { store.chooseFolderForScan() },
                        dropAction: { store.startDroppedFolder($0) }
                    )
                    .frame(maxWidth: 440)
                }
                .frame(maxWidth: 1080)
                .padding(.horizontal, 54)
                .padding(.top, 70)
                .frame(maxHeight: .infinity)

                RecentActivityStrip()
            }
        }
    }
}

private struct AssuranceRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SortwellPalette.sage)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(SortwellPalette.secondaryText)
        }
    }
}

private struct FolderDropZone: View {
    let action: () -> Void
    let dropAction: (URL) -> Bool
    @State private var isDropTargeted = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(SortwellPalette.sageSoft)
                        .frame(width: 84, height: 84)
                    Image(systemName: "folder")
                        .font(.system(size: 37, weight: .light))
                        .foregroundStyle(SortwellPalette.sage)
                }

                VStack(spacing: 7) {
                    Text(isDropTargeted ? "Drop to scan this folder" : "Choose or drop a folder to organise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SortwellPalette.primaryText)
                    Text("Sortwell scans locally, then shows a plan for review before anything can change.")
                        .font(.system(size: 12))
                        .foregroundStyle(SortwellPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }

                Text("Choose Folder")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SortwellPalette.sage)
            }
            .padding(34)
            .frame(maxWidth: .infinity, minHeight: 330)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isDropTargeted ? SortwellPalette.sageSoft : SortwellPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(SortwellPalette.border, style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
                    )
            )
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, let url = urls.first else { return false }
            return dropAction(url)
        } isTargeted: { isDropTargeted = $0 }
        .accessibilityLabel("Choose a folder to organise")
    }
}

private struct RecentActivityStrip: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            DividerLine()
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(SortwellPalette.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent activity")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SortwellPalette.secondaryText)
                    Text(activityDescription)
                        .font(.system(size: 12, weight: .medium))
                }
                Spacer()
                if !store.activity.isEmpty {
                    Button("View") {
                        store.route = .activity
                    }
                    .buttonStyle(SortwellSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 32)
            .frame(height: 76)
            .background(SortwellPalette.surface)
        }
    }

    private var activityDescription: String {
        guard let session = store.activity.first else {
            return "No organisation sessions recorded yet"
        }
        let actionCount = session.moveCount + session.trashCount
        return "\(session.folderName) · \(actionCount.formatted()) actions · \(session.dateDescription)"
    }
}

struct ScanView: View {
    @Environment(PrototypeStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ScreenHeading(
                eyebrow: "Read-only scan",
                title: "Understanding \(store.currentFolderName)",
                subtitle: "Sortwell is identifying documents, archives, uncertain items, and software project boundaries."
            )

            VStack(alignment: .leading, spacing: 14) {
                ProgressView(value: store.scanProgress)
                    .tint(SortwellPalette.sage)
                    .controlSize(.large)
                    .accessibilityLabel("Scan progress")
                    .accessibilityValue("\(Int(store.scanProgress * 100)) per cent")

                HStack {
                    Text("\(Int(store.scanProgress * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text("No files are being changed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SortwellPalette.sage)
                }
            }

            Panel {
                VStack(spacing: 0) {
                    ScanLedgerRow(value: store.displayedScanFileCount.formatted(), label: "files inspected", icon: "doc.text.magnifyingglass")
                    DividerLine()
                    ScanLedgerRow(value: store.displayedProtectedProjectCount.formatted(), label: store.projectLedgerLabel, icon: "lock.shield")
                    DividerLine()
                    ScanLedgerRow(value: store.displayedDuplicateComparisonCount.formatted(), label: store.duplicateLedgerLabel, icon: "number")
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.scanStatus)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SortwellPalette.secondaryText)
                    Text(store.currentScanPathDescription)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Cancel Scan") {
                    store.cancelScan()
                }
                .buttonStyle(SortwellSecondaryButtonStyle())
            }
        }
        .frame(maxWidth: 760)
        .padding(54)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await store.runScan(reduceMotion: reduceMotion)
        }
    }

}

private struct ScanLedgerRow: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SortwellPalette.sage)
                .frame(width: 24)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 74, alignment: .trailing)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(SortwellPalette.secondaryText)
            Spacer()
        }
        .padding(.vertical, 13)
    }
}

struct ScanSummaryView: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                ScreenHeading(
                    eyebrow: "Scan complete",
                    title: "\(store.currentFolderName) is ready to review",
                    subtitle: store.scanSummarySubtitle
                )

                HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 0) {
                        LedgerMetric(value: store.totalTopLevelItems.formatted(), label: "top-level items reviewed")
                        DividerLine()
                        LedgerMetric(value: store.organisationMoveCount.formatted(), label: "organisation moves suggested", tint: SortwellPalette.sage)
                        DividerLine()
                        LedgerMetric(value: store.duplicateGroups.count.formatted(), label: "exact duplicate groups · \(store.possibleTrashCount.formatted()) removable copies")
                        DividerLine()
                        LedgerMetric(value: store.unresolvedItemCount.formatted(), label: "uncertain items will remain untouched", tint: SortwellPalette.amber)
                        DividerLine()
                        LedgerMetric(value: store.protectedProjectCount.formatted(), label: "software projects kept in place")
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        Panel {
                            VStack(alignment: .leading, spacing: 15) {
                                StatusPill(title: "Project contents protected", icon: "lock.shield")
                                Text("Repeated project files are not cleanup candidates")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(store.protectedDuplicateSummary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(SortwellPalette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Review protected projects") {
                                    store.beginReview(.protectedProjects)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SortwellPalette.sage)
                            }
                        }

                        Panel {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Proposed categories")
                                    .font(.system(size: 13, weight: .semibold))
                                ForEach(store.categories.prefix(5)) { category in
                                    HStack {
                                        Label(category.title, systemImage: category.icon)
                                            .font(.system(size: 12))
                                            .foregroundStyle(SortwellPalette.secondaryText)
                                        Spacer()
                                        Text(category.totalCount.formatted())
                                            .font(.system(size: 12, design: .monospaced))
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: 360)
                }

                HStack {
                    Button("Choose Another Folder") {
                        store.reset()
                    }
                    .buttonStyle(SortwellSecondaryButtonStyle())
                    Spacer()
                    Button("Review Plan") {
                        store.beginReview()
                    }
                    .buttonStyle(SortwellPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: 980)
            .padding(46)
            .frame(maxWidth: .infinity)
        }
    }
}
