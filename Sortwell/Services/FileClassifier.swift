import Foundation

struct FileClassification: Sendable {
    let categoryID: String
    let category: String
    let explanation: String
}

struct FileClassifier: Sendable {
    static let builtInCategoryDefinitions: [FileCategoryDefinition] = [
        .init(id: "identity", title: "Identity & Personal", icon: "person.text.rectangle"),
        .init(id: "education", title: "Education & Employment", icon: "graduationcap"),
        .init(id: "finance", title: "Finance & Bills", icon: "sterlingsign.circle"),
        .init(id: "housing", title: "Housing & Property", icon: "house"),
        .init(id: "health", title: "Health & Medical", icon: "cross.case"),
        .init(id: "media", title: "Images & Media", icon: "photo.on.rectangle"),
        .init(id: "technical", title: "Technical Files & Data", icon: "terminal"),
        .init(id: "archives", title: "Archives", icon: "archivebox"),
        .init(id: "other", title: "Other Documents", icon: "doc.text")
    ]

    let categoryDefinitions: [FileCategoryDefinition]
    private let customRules: [CustomClassificationRule]

    init(preferences: SortwellPreferences = .defaults) {
        categoryDefinitions = Self.builtInCategoryDefinitions + preferences.customCategories
        customRules = preferences.customRules
    }

    func classify(name: String, isDirectory: Bool, analysis: LocalContentAnalysis = .empty) -> FileClassification? {
        let lower = name.lowercased()
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()

        if let custom = customClassification(name: lower, extension: ext, isDirectory: isDirectory, content: analysis.searchableText) {
            return custom
        }

        let semanticText = "\(lower) \(analysis.searchableText)"
        let evidence = analysis.evidenceDescription.map { " The suggestion also uses \($0)." } ?? ""
        if matches(semanticText, ["aadhar", "aadhaar", "passport", "pan card", "pancard", "driving licence", "driving license", "voter id", "birth certificate", "affidavit", "immigration", "right to work"]) {
            return match("identity", "Identity & Personal", "Local text indicates an identity or immigration record.\(evidence)")
        }
        if matches(semanticText, ["resume", "curriculum vitae", "degree", "marksheet", "employment", "experience letter", "relieving", "payslip", "salary", "sponsorship", "certificate of employment"]) {
            return match("education", "Education & Employment", "Local text indicates an education or employment record.\(evidence)")
        }
        if matches(semanticText, ["bank statement", "challan", "receipt", "invoice", "cancelled cheque", "payment receipt", "payment received", "income tax", "utility bill", "account statement"]) {
            return match("finance", "Finance & Bills", "Local text indicates a financial statement, bill, or receipt.\(evidence)")
        }
        if matches(semanticText, ["tenancy", "council tax", "property", "housing", "rent", "landlord", "lease agreement"]) {
            return match("housing", "Housing & Property", "Local text indicates a housing or property record.\(evidence)")
        }
        if matches(semanticText, ["medical", "dental", "diagnosis", "prescription", "fit note", "appointment", "patient", "health service"]) {
            return match("health", "Health & Medical", "Local text indicates a health or medical record.\(evidence)")
        }
        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "tiff", "bmp", "mov", "mp4", "m4v", "wav", "mp3", "m4a"].contains(ext) {
            return match("media", "Images & Media", "The file type is commonly used for images, audio, or video.\(evidence)")
        }
        if ["zip", "tar", "tgz", "gz", "bz2", "xz", "7z", "rar"].contains(ext) {
            return match("archives", "Archives", "The file is a compressed archive.")
        }
        if ["swift", "py", "js", "ts", "tsx", "jsx", "java", "kt", "go", "rs", "rb", "php", "sh", "yml", "yaml", "json", "xml", "toml", "md", "sql", "jar", "pem", "key", "out", "log"].contains(ext) {
            return match("technical", "Technical Files & Data", "The file type is commonly used for source code, configuration, or technical data.")
        }
        if isDirectory {
            if matches(lower, ["photo", "image", "media"]) {
                return match("media", "Images & Media", "The folder name indicates image or media content and it will move intact.")
            }
            if matches(lower, ["document", "record", "personal"]) {
                return match("other", "Other Documents", "The folder name indicates document content and it will move intact.")
            }
            return nil
        }
        if ["pdf", "doc", "docx", "pages", "xls", "xlsx", "csv", "txt", "rtf", "epub", "eml"].contains(ext), !looksGenerated(lower) {
            return match("other", "Other Documents", "The document type and local metadata do not support a more specific category.\(evidence)")
        }
        return nil
    }

    func icon(for category: String) -> String {
        categoryDefinitions.first { $0.title == category }?.icon ?? "doc"
    }

    private func customClassification(name: String, extension ext: String, isDirectory: Bool, content: String) -> FileClassification? {
        for rule in customRules where rule.isEnabled && applies(rule.target, toDirectory: isDirectory) {
            guard let category = categoryDefinitions.first(where: { $0.id == rule.categoryID }) else { continue }
            let pattern = normalisedPattern(rule.pattern, kind: rule.matchKind)
            guard !pattern.isEmpty else { continue }
            let matched: Bool
            switch rule.matchKind {
            case .filenameContains: matched = name.contains(pattern)
            case .fileExtension: matched = ext == pattern
            case .contentContains: matched = content.contains(pattern)
            }
            if matched {
                return .init(
                    categoryID: category.id,
                    category: category.title,
                    explanation: "Matched your local \(rule.matchKind.title.lowercased()) rule ‘\(rule.pattern)’."
                )
            }
        }
        return nil
    }

    private func applies(_ target: ClassificationTarget, toDirectory: Bool) -> Bool {
        switch target {
        case .files: !toDirectory
        case .folders: toDirectory
        case .filesAndFolders: true
        }
    }

    private func normalisedPattern(_ value: String, kind: ClassificationMatchKind) -> String {
        var pattern = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if kind == .fileExtension, pattern.hasPrefix(".") { pattern.removeFirst() }
        return pattern
    }

    private func matches(_ value: String, _ terms: [String]) -> Bool {
        let searchable = " " + value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ") + " "
        return terms.contains { term in
            let normalisedTerm = term
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .joined(separator: " ")
            return searchable.contains(" \(normalisedTerm) ")
        }
    }

    private func looksGenerated(_ value: String) -> Bool {
        let stem = URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
        let alphanumeric = stem.filter(\.isLetter)
        let digits = stem.filter(\.isNumber)
        return alphanumeric.count < 3 || digits.count > max(8, alphanumeric.count * 2)
    }

    private func match(_ id: String, _ category: String, _ explanation: String) -> FileClassification {
        .init(categoryID: id, category: category, explanation: explanation)
    }
}
