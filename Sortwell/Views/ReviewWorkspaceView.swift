import SwiftUI

struct ReviewWorkspaceView: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        GeometryReader { geometry in
            let showsInspector = geometry.size.width >= 1_080

            HStack(spacing: 0) {
                ReviewSidebar()
                    .frame(width: showsInspector ? 216 : 200)

                Rectangle()
                    .fill(SortwellPalette.border)
                    .frame(width: 1)

                VStack(spacing: 0) {
                    ReviewHeader(showsInspector: showsInspector)
                    DividerLine()

                    HStack(spacing: 0) {
                        ReviewSectionContent()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if showsInspector {
                            Rectangle()
                                .fill(SortwellPalette.border)
                                .frame(width: 1)
                            ReviewInspector()
                                .frame(width: 292)
                        }
                    }

                    DividerLine()
                    ReviewFooter()
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.showInspector },
                set: { store.showInspector = $0 }
            )
        ) {
            ReviewInspector()
                .environment(store)
                .frame(minWidth: 390, minHeight: 520)
        }
    }
}

private struct ReviewSidebar: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("REVIEW")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(SortwellPalette.secondaryText)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 9)

            ForEach(ReviewSection.allCases) { section in
                SidebarRow(
                    title: section.title,
                    icon: section.icon,
                    count: count(for: section),
                    isSelected: store.reviewSection == section
                ) {
                    store.reviewSection = section
                }
            }

            if store.reviewSection == .organisation {
                Text("CATEGORIES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(SortwellPalette.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.categories) { category in
                            HStack(spacing: 9) {
                                Image(systemName: category.icon)
                                    .frame(width: 17)
                                Text(category.title)
                                    .lineLimit(1)
                                Spacer()
                                Text(store.categoryMoveCount(category.title).formatted())
                                    .monospacedDigit()
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(SortwellPalette.secondaryText)
                            .padding(.horizontal, 16)
                            .frame(height: 29)
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 7) {
                Label("Nothing has changed yet", systemImage: "checkmark.shield")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SortwellPalette.sage)
                Text("Unapproved and uncertain items remain exactly where they are.")
                    .font(.system(size: 10))
                    .foregroundStyle(SortwellPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(SortwellPalette.sidebar)
    }

    private func count(for section: ReviewSection) -> Int {
        switch section {
        case .organisation: store.totalTopLevelItems
        case .duplicates: store.duplicateGroups.count
        case .needsReview: store.unresolvedItemCount
        case .protectedProjects: store.protectedProjectCount
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .frame(width: 17)
                Text(title)
                    .lineLimit(1)
                Spacer()
                Text(count.formatted())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? SortwellPalette.sage : SortwellPalette.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? SortwellPalette.sageSoft : .clear)
            )
            .padding(.horizontal, 7)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct ReviewHeader: View {
    @Environment(PrototypeStore.self) private var store
    let showsInspector: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.reviewSection.title)
                    .font(.system(size: 17, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SortwellPalette.secondaryText)
            }
            Spacer()
            if !showsInspector {
                Button {
                    store.showInspector = true
                } label: {
                    Label("Details", systemImage: "sidebar.trailing")
                }
                .buttonStyle(SortwellSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
        .background(SortwellPalette.surface)
    }

    private var subtitle: String {
        switch store.reviewSection {
        case .organisation: "Review proposed moves into Organised Files"
        case .duplicates: "Approve each exact duplicate group individually"
        case .needsReview: "Unclassified items remain in place by default"
        case .protectedProjects: "Project contents and locations remain unchanged"
        }
    }
}

private struct ReviewSectionContent: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        Group {
            switch store.reviewSection {
            case .organisation:
                OrganisationPlanContent()
            case .duplicates:
                DuplicateReviewContent()
            case .needsReview:
                NeedsReviewContent()
            case .protectedProjects:
                ProtectedProjectsContent()
            }
        }
        .background(SortwellPalette.canvas)
    }
}

private struct OrganisationPlanContent: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.planItems) { item in
                    HStack(spacing: 13) {
                        Button {
                            store.togglePlanItem(item.id)
                        } label: {
                            Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundStyle(item.isSelected ? SortwellPalette.sage : SortwellPalette.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Include \(item.name) in organisation plan")
                        .accessibilityValue(item.isSelected ? "Included" : "Excluded")

                        Button {
                            store.selectedPlanItemID = item.id
                        } label: {
                            HStack(spacing: 13) {
                            Image(systemName: item.kind.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(SortwellPalette.secondaryText)
                                .frame(width: 23)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9))
                                    Text(item.proposedCategory)
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(SortwellPalette.secondaryText)
                            }
                            Spacer()
                            Text(item.size)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(SortwellPalette.secondaryText)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(SortwellPalette.secondaryText.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.name), \(item.proposedCategory), \(item.size)")
                        .accessibilityValue(item.isSelected ? "Included in organisation plan" : "Excluded from organisation plan")
                        .accessibilityAddTraits(item.id == store.selectedPlanItemID ? .isSelected : [])
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 58)
                    .background(item.id == store.selectedPlanItemID ? SortwellPalette.sageSoft : SortwellPalette.surface)
                    DividerLine()
                }
            }
            .padding(18)
        }
    }
}

private struct DuplicateReviewContent: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.duplicateGroups) { group in
                        Button {
                            store.selectedDuplicateGroupID = group.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: decisionIcon(group.decision))
                                    .foregroundStyle(decisionTint(group.decision))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text("\(group.copies.count) matching files")
                                        .font(.system(size: 10))
                                        .foregroundStyle(SortwellPalette.secondaryText)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(group.id == store.selectedDuplicateGroupID ? SortwellPalette.sageSoft : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(group.title)
                        .accessibilityValue("\(group.copies.count) matching files, \(decisionDescription(group.decision))")
                        .accessibilityAddTraits(group.id == store.selectedDuplicateGroupID ? .isSelected : [])
                    }
                }
                .padding(12)
            }
            .frame(width: 210)
            .background(SortwellPalette.raisedSurface)

            Rectangle()
                .fill(SortwellPalette.border)
                .frame(width: 1)

            if let group = store.selectedDuplicateGroup {
                DuplicateGroupDetail(group: group)
            } else {
                ContentUnavailableView("Select a group", systemImage: "doc.on.doc")
            }
        }
    }

    private func decisionIcon(_ decision: DuplicateDecision) -> String {
        switch decision {
        case .pending: "circle"
        case .keepAll: "checkmark.circle"
        case .moveOthersToTrash: "trash.circle.fill"
        }
    }

    private func decisionTint(_ decision: DuplicateDecision) -> Color {
        decision == .pending ? SortwellPalette.secondaryText : SortwellPalette.sage
    }

    private func decisionDescription(_ decision: DuplicateDecision) -> String {
        switch decision {
        case .pending: "Decision pending"
        case .keepAll: "Keep all copies"
        case .moveOthersToTrash: "Move approved copies to Trash"
        }
    }
}

private struct DuplicateGroupDetail: View {
    @Environment(PrototypeStore.self) private var store
    let group: DuplicateGroup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.title)
                            .font(.system(size: 18, weight: .semibold))
                        Text("\(group.copies.count) byte-for-byte identical files")
                            .font(.system(size: 12))
                            .foregroundStyle(SortwellPalette.secondaryText)
                    }
                    Spacer()
                    StatusPill(title: "Exact match", icon: "checkmark.shield")
                }

                VStack(spacing: 9) {
                    ForEach(group.copies) { copy in
                        DuplicateCopyRow(
                            copy: copy,
                            isCanonical: group.canonicalCopyID == copy.id,
                            selectionDisabled: group.copies.contains(where: \.isProtected) && !copy.isProtected
                        ) {
                            store.selectCanonicalCopy(copy.id, in: group.id)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Keep All Copies") {
                        store.decideDuplicateGroup(.keepAll, groupID: group.id)
                    }
                    .buttonStyle(SortwellSecondaryButtonStyle())

                    Button(cleanupButtonTitle) {
                        store.decideDuplicateGroup(.moveOthersToTrash, groupID: group.id)
                    }
                    .buttonStyle(SortwellPrimaryButtonStyle())
                    .disabled(!group.canApproveCleanup)
                }

                if group.decision != .pending {
                    Label(decisionMessage, systemImage: group.decision == .keepAll ? "checkmark.circle" : "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SortwellPalette.sage)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(SortwellPalette.sageSoft))
                }
            }
            .padding(24)
        }
    }

    private var decisionMessage: String {
        switch group.decision {
        case .pending: ""
        case .keepAll: "All copies will remain untouched."
        case .moveOthersToTrash: "Required copies will be retained and \(group.potentiallyRemovableCopyCount) will move to Trash after final confirmation."
        }
    }

    private var cleanupButtonTitle: String {
        if group.copies.contains(where: \.isProtected) {
            return "Keep Protected Copy and Move Loose Copies to Trash"
        }
        return "Keep Selected Copy and Move Others to Trash"
    }
}

private struct DuplicateCopyRow: View {
    let copy: DuplicateCopy
    let isCanonical: Bool
    let selectionDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: isCanonical ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isCanonical ? SortwellPalette.sage : SortwellPalette.secondaryText)
                Image(systemName: "doc")
                    .foregroundStyle(SortwellPalette.secondaryText)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(copy.name)
                            .font(.system(size: 12, weight: .medium))
                        if copy.isProtected {
                            StatusPill(title: copy.protectionReason ?? "Required in project", icon: "lock.shield")
                        }
                    }
                    Text(copy.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SortwellPalette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(copy.size)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SortwellPalette.secondaryText)
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isCanonical ? SortwellPalette.sageSoft : SortwellPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isCanonical ? SortwellPalette.sage.opacity(0.45) : SortwellPalette.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(selectionDisabled)
        .help(selectionDisabled ? "A protected project copy must remain the retained copy" : copy.path)
        .accessibilityLabel("\(copy.name), \(isCanonical ? "selected to keep" : "not selected")")
        .accessibilityValue(copy.path)
        .accessibilityAddTraits(isCanonical ? .isSelected : [])
    }
}

private struct NeedsReviewContent: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.needsReviewItems) { item in
                        Button {
                            store.selectedNeedsReviewID = item.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.hasReviewedDecision ? "checkmark.circle.fill" : "questionmark.circle")
                                    .foregroundStyle(item.hasReviewedDecision ? SortwellPalette.sage : SortwellPalette.amber)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text(reviewStatus(for: item))
                                        .font(.system(size: 10))
                                        .foregroundStyle(SortwellPalette.secondaryText)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(item.id == store.selectedNeedsReviewID ? (item.hasReviewedDecision ? SortwellPalette.sageSoft : SortwellPalette.amberSoft) : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.name)
                        .accessibilityValue(reviewStatus(for: item))
                        .accessibilityAddTraits(item.id == store.selectedNeedsReviewID ? .isSelected : [])
                    }
                }
                .padding(12)
            }
            .frame(width: 235)
            .background(SortwellPalette.raisedSurface)

            Rectangle().fill(SortwellPalette.border).frame(width: 1)

            if let item = store.selectedNeedsReviewItem {
                NeedsReviewDetail(item: item)
            } else {
                ContentUnavailableView("Select an item", systemImage: "questionmark.folder")
            }
        }
    }

    private func reviewStatus(for item: NeedsReviewItem) -> String {
        if let category = item.selectedCategory { return category }
        return item.hasReviewedDecision ? "Confirmed: keep in place" : "Needs a decision"
    }
}

private struct NeedsReviewDetail: View {
    @Environment(PrototypeStore.self) private var store
    let item: NeedsReviewItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let fileURL = item.fileURL {
                    SecurityScopedQuickLookPreview(fileURL: fileURL, accessRootURL: store.selectedFolderURL)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SortwellPalette.border, lineWidth: 1))
                        .frame(height: 230)
                } else {
                    ContentUnavailableView("Preview unavailable", systemImage: "doc.richtext")
                        .frame(height: 190)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 18, weight: .semibold))
                    Text(item.reason)
                        .font(.system(size: 12))
                        .foregroundStyle(SortwellPalette.secondaryText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose a category")
                        .font(.system(size: 12, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                        ForEach(store.categories) { category in
                            let isSelected = item.selectedCategory == category.title
                            Button {
                                store.classifyNeedsReviewItem(item.id, as: category.title)
                            } label: {
                                Label(category.title, systemImage: isSelected ? "checkmark.circle.fill" : category.icon)
                            }
                            .buttonStyle(SortwellChoiceButtonStyle(isSelected: isSelected))
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }

                    Button {
                        store.classifyNeedsReviewItem(item.id, as: nil)
                    } label: {
                        Label(
                            item.hasReviewedDecision && item.selectedCategory == nil ? "Confirmed: Keep in Place" : "Confirm Keep in Place",
                            systemImage: item.hasReviewedDecision && item.selectedCategory == nil ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item.hasReviewedDecision && item.selectedCategory == nil ? .isSelected : [])
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SortwellPalette.sage)
                    .padding(.top, 5)
                }
            }
            .padding(24)
        }
    }
}

private struct ProtectedProjectsContent: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.protectedProjects) { project in
                    Button {
                        store.selectedProjectID = project.id
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(SortwellPalette.sageSoft)
                                    .frame(width: 40, height: 40)
                                Image(systemName: "folder.badge.gearshape")
                                    .foregroundStyle(SortwellPalette.sage)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(project.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    StatusPill(title: "Keep in place", icon: "lock.shield")
                                }
                                Text("\(project.containedFiles.formatted()) contained files · contents will not be reorganised")
                                    .font(.system(size: 11))
                                    .foregroundStyle(SortwellPalette.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(SortwellPalette.secondaryText)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(project.id == store.selectedProjectID ? SortwellPalette.sageSoft : SortwellPalette.surface)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(SortwellPalette.border, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(project.name)
                    .accessibilityValue("Keep in place, \(project.containedFiles.formatted()) contained files")
                    .accessibilityAddTraits(project.id == store.selectedProjectID ? .isSelected : [])
                }

                if store.protectedProjectCount > store.protectedProjects.count {
                    HStack(spacing: 10) {
                        Image(systemName: "ellipsis")
                        Text("\((store.protectedProjectCount - store.protectedProjects.count).formatted()) more protected projects are represented in this sample")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(SortwellPalette.secondaryText)
                    .padding(.top, 5)
                }
            }
            .padding(20)
        }
    }
}

private struct ReviewInspector: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch store.reviewSection {
                case .organisation:
                    PlanInspectorContent(item: store.selectedPlanItem)
                case .duplicates:
                    DuplicateInspectorContent(group: store.selectedDuplicateGroup)
                case .needsReview:
                    NeedsInspectorContent(item: store.selectedNeedsReviewItem)
                case .protectedProjects:
                    ProjectInspectorContent(project: store.selectedProject)
                }
            }
            .padding(20)
        }
        .background(SortwellPalette.surface)
    }
}

private struct PlanInspectorContent: View {
    @Environment(PrototypeStore.self) private var store
    let item: PlanItem?

    var body: some View {
        if let item {
            InspectorTitle(icon: item.kind.icon, title: item.name, status: "Strong suggestion")
            InspectorField(title: "Current location", value: item.currentPath, monospaced: true)
            InspectorField(title: "Proposed location", value: "Organised Files/\(item.proposedCategory)/", monospaced: true)
            InspectorField(title: "Why Sortwell suggested this", value: item.explanation)

            Menu {
                ForEach(store.categories) { category in
                    Button(category.title) {
                        store.updatePlanCategory(category.title, for: item.id)
                    }
                }
            } label: {
                Label("Change Category", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(SortwellSecondaryButtonStyle())
        }
    }
}

private struct DuplicateInspectorContent: View {
    let group: DuplicateGroup?

    var body: some View {
        if let group {
            InspectorTitle(icon: "doc.on.doc", title: group.title, status: "Exact duplicate")
            InspectorField(title: "Verification", value: "Same SHA-256 checksum and byte-for-byte comparison")
            InspectorField(title: "Checksum", value: "\(group.hashPrefix)…", monospaced: true)
            InspectorField(title: "Copies", value: "\(group.copies.count) files · \(group.potentiallyRemovableCopyCount) potentially removable")
            InspectorField(title: "Safety", value: "No copy moves to Trash until you approve this group and confirm the complete plan.")
        }
    }
}

private struct NeedsInspectorContent: View {
    let item: NeedsReviewItem?

    var body: some View {
        if let item {
            InspectorTitle(icon: "questionmark.folder", title: item.name, status: needsStatus)
            InspectorField(title: "Current location", value: item.currentPath, monospaced: true)
            InspectorField(title: "Why this needs review", value: item.reason)
            InspectorField(title: "Default action", value: "The item remains in its original location unless you choose a category.")
        }
    }

    private var needsStatus: String {
        guard let item else { return "Needs decision" }
        if let category = item.selectedCategory { return category }
        return item.hasReviewedDecision ? "Confirmed: keep in place" : "Needs decision"
    }
}

private struct ProjectInspectorContent: View {
    let project: ProtectedProject?

    var body: some View {
        if let project {
            InspectorTitle(icon: "lock.shield", title: project.name, status: "Keep in place")
            InspectorField(title: "Current location", value: project.path, monospaced: true)
            InspectorField(title: "Detected contents", value: "\(project.containedFiles.formatted()) files")
            InspectorField(title: "Why it is protected", value: project.reason)
            InspectorField(title: "Sortwell action", value: "The folder and everything inside it will remain unchanged.")
        }
    }
}

private struct InspectorTitle: View {
    let icon: String
    let title: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(SortwellPalette.sage)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)
            StatusPill(title: status, icon: "checkmark.circle")
        }
    }
}

private struct InspectorField: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SortwellPalette.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 12))
                .foregroundStyle(SortwellPalette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ReviewFooter: View {
    @Environment(PrototypeStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(store.organisationMoveCount) moves selected · \(store.approvedTrashCount) Trash actions approved")
                    .font(.system(size: 12, weight: .medium))
                Text("\(store.needsReviewItemsKeptInPlaceCount) review items remain in place · \(store.unresolvedItemCount) still need a decision")
                    .font(.system(size: 10))
                    .foregroundStyle(SortwellPalette.secondaryText)
            }
            Spacer()
            Button("Back to Summary") {
                store.route = .summary
            }
            .buttonStyle(SortwellSecondaryButtonStyle())

            Button("Continue to Confirmation") {
                store.showConfirmation = true
            }
            .buttonStyle(SortwellPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(SortwellPalette.surface)
    }
}
