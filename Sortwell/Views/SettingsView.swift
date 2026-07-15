import SwiftUI

struct SortwellSettingsView: View {
    @Environment(PrototypeStore.self) private var store
    @State private var newCategoryTitle = ""
    @State private var newCategoryIcon = "folder"
    @State private var newRuleCategoryID = "other"
    @State private var newRuleMatchKind = ClassificationMatchKind.filenameContains
    @State private var newRulePattern = ""
    @State private var newRuleTarget = ClassificationTarget.filesAndFolders
    @State private var errorMessage: String?

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }
            classificationSettings
                .tabItem { Label("Classification", systemImage: "folder.badge.gearshape") }
        }
        .frame(width: 680, height: 560)
        .alert("Settings Could Not Be Saved", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear {
            ensureSelectedRuleCategoryExists()
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Local analysis") {
                Toggle("Analyse supported document contents", isOn: contentAnalysisBinding)
                Text("Sortwell reads supported text, PDF, and image content only on this Mac to improve suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Use OCR for scanned PDFs and images", isOn: ocrBinding)
                    .disabled(!store.preferences.contentAnalysisEnabled)
            }

            Section("Recovery and Undo") {
                Picker("Keep completed recovery data for", selection: recoveryRetentionBinding) {
                    ForEach(retentionOptions, id: \.self) { days in
                        Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                    }
                }
                Text("Expired recovery copies and their completed journals are removed automatically. Interrupted sessions are retained for review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private var classificationSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsSection(title: "Categories", subtitle: "Built-in categories stay available. Add local categories for your own filing system.") {
                    VStack(spacing: 8) {
                        ForEach(store.categoryDefinitions) { category in
                            HStack(spacing: 10) {
                                Image(systemName: category.icon)
                                    .foregroundStyle(SortwellPalette.sage)
                                    .frame(width: 22)
                                Text(category.title)
                                Spacer()
                                if store.preferences.customCategories.contains(where: { $0.id == category.id }) {
                                    Button(role: .destructive) {
                                        perform { try store.removeCustomCategory(category.id) }
                                        ensureSelectedRuleCategoryExists()
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove \(category.title)")
                                    .accessibilityLabel("Remove category \(category.title)")
                                } else {
                                    Text("Built in")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(SortwellPalette.raisedSurface))
                        }

                        HStack(spacing: 8) {
                            TextField("Category name", text: $newCategoryTitle)
                            TextField("SF Symbol", text: $newCategoryIcon)
                                .frame(width: 130)
                            Button("Add") {
                                perform { try store.addCustomCategory(title: newCategoryTitle, icon: newCategoryIcon) }
                                if errorMessage == nil {
                                    newCategoryTitle = ""
                                    newCategoryIcon = "folder"
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SortwellPalette.sage)
                            .disabled(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                settingsSection(title: "Rules", subtitle: "Rules are checked in this order before Sortwell's built-in suggestions.") {
                    VStack(spacing: 10) {
                        ForEach(store.preferences.customRules) { rule in
                            HStack(spacing: 10) {
                                Toggle("Enable rule: \(rule.matchKind.title) \(rule.pattern)", isOn: ruleEnabledBinding(rule.id))
                                    .labelsHidden()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(rule.matchKind.title) ‘\(rule.pattern)’")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("\(categoryTitle(rule.categoryID)) · \(rule.target.title)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    perform { try store.removeCustomRule(rule.id) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove rule")
                                .accessibilityLabel("Remove rule: \(rule.matchKind.title) \(rule.pattern)")
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(SortwellPalette.raisedSurface))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Picker("Category", selection: $newRuleCategoryID) {
                                    ForEach(store.categoryDefinitions) { category in
                                        Text(category.title).tag(category.id)
                                    }
                                }
                                Picker("Match", selection: $newRuleMatchKind) {
                                    ForEach(ClassificationMatchKind.allCases) { kind in
                                        Text(kind.title).tag(kind)
                                    }
                                }
                                .onChange(of: newRuleMatchKind) { _, kind in
                                    if kind == .contentContains { newRuleTarget = .files }
                                }
                            }
                            HStack {
                                TextField(rulePatternPrompt, text: $newRulePattern)
                                Picker("Applies to", selection: $newRuleTarget) {
                                    ForEach(availableRuleTargets) { target in
                                        Text(target.title).tag(target)
                                    }
                                }
                                .frame(width: 210)
                                Button("Add Rule") {
                                    perform {
                                        try store.addCustomRule(
                                            categoryID: newRuleCategoryID,
                                            matchKind: newRuleMatchKind,
                                            pattern: newRulePattern,
                                            target: newRuleTarget
                                        )
                                    }
                                    if errorMessage == nil { newRulePattern = "" }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(SortwellPalette.sage)
                                .disabled(newRulePattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(SortwellPalette.border, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(24)
        }
        .background(SortwellPalette.canvas)
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var contentAnalysisBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.contentAnalysisEnabled },
            set: { enabled in
                perform {
                    try store.updateAnalysisPreferences(
                        contentAnalysisEnabled: enabled,
                        ocrEnabled: store.preferences.ocrEnabled
                    )
                }
            }
        )
    }

    private var ocrBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.ocrEnabled },
            set: { enabled in
                perform {
                    try store.updateAnalysisPreferences(
                        contentAnalysisEnabled: store.preferences.contentAnalysisEnabled,
                        ocrEnabled: enabled
                    )
                }
            }
        )
    }

    private var recoveryRetentionBinding: Binding<Int> {
        Binding(
            get: { store.preferences.recoveryRetentionDays },
            set: { days in perform { try store.setRecoveryRetentionDays(days) } }
        )
    }

    private var retentionOptions: [Int] {
        Array(Set([7, 14, 30, 60, 90, 180, 365, store.preferences.recoveryRetentionDays])).sorted()
    }

    private var rulePatternPrompt: String {
        switch newRuleMatchKind {
        case .filenameContains: "Text in filename"
        case .fileExtension: "Extension, such as pdf"
        case .contentContains: "Text in extracted content"
        }
    }

    private var availableRuleTargets: [ClassificationTarget] {
        newRuleMatchKind == .contentContains ? [.files] : ClassificationTarget.allCases
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func ruleEnabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { store.preferences.customRules.first(where: { $0.id == id })?.isEnabled ?? false },
            set: { enabled in perform { try store.setCustomRuleEnabled(id, isEnabled: enabled) } }
        )
    }

    private func categoryTitle(_ id: String) -> String {
        store.categoryDefinitions.first(where: { $0.id == id })?.title ?? "Unavailable category"
    }

    private func ensureSelectedRuleCategoryExists() {
        guard !store.categoryDefinitions.contains(where: { $0.id == newRuleCategoryID }) else { return }
        newRuleCategoryID = store.categoryDefinitions.first?.id ?? "other"
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
