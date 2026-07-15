import Foundation

enum TelegramScenario {
    static let categories: [SortwellCategory] = [
        .init(id: "identity", title: "Identity & Personal", icon: "person.text.rectangle", totalCount: 27),
        .init(id: "education", title: "Education & Employment", icon: "graduationcap", totalCount: 6),
        .init(id: "finance", title: "Finance & Bills", icon: "sterlingsign.circle", totalCount: 6),
        .init(id: "housing", title: "Housing & Property", icon: "house", totalCount: 13),
        .init(id: "health", title: "Health & Medical", icon: "cross.case", totalCount: 3),
        .init(id: "technical", title: "Technical Files & Data", icon: "terminal", totalCount: 27),
        .init(id: "archives", title: "Archives", icon: "archivebox", totalCount: 41),
        .init(id: "other", title: "Other Documents", icon: "doc.text", totalCount: 1)
    ]

    static let planItems: [PlanItem] = {
        var items: [PlanItem] = [
            .init(id: "aadhar", name: "Aadhar.pdf", kind: .file, currentPath: "Telegram/Aadhar.pdf", proposedCategory: "Identity & Personal", explanation: "The filename indicates an identity document, and the PDF metadata is consistent with a scanned personal record.", size: "356 KB", isSelected: true),
            .init(id: "degree", name: "Degree.pdf", kind: .file, currentPath: "Telegram/Degree.pdf", proposedCategory: "Education & Employment", explanation: "The filename clearly identifies an education certificate.", size: "376 KB", isSelected: true),
            .init(id: "bank", name: "bankstatement.pdf", kind: .file, currentPath: "Telegram/bankstatement.pdf", proposedCategory: "Finance & Bills", explanation: "The filename and extracted document title identify a bank statement.", size: "134 KB", isSelected: true),
            .init(id: "council", name: "council_tax.jpg", kind: .file, currentPath: "Telegram/council_tax.jpg", proposedCategory: "Housing & Property", explanation: "Council tax is associated with housing and household records.", size: "148 KB", isSelected: true),
            .init(id: "dental", name: "Dental_bill.pdf", kind: .file, currentPath: "Telegram/Dental_bill.pdf", proposedCategory: "Health & Medical", explanation: "The filename identifies a medical expense document.", size: "480 KB", isSelected: true),
            .init(id: "design", name: "DESIGN_REVIEW.md", kind: .file, currentPath: "Telegram/DESIGN_REVIEW.md", proposedCategory: "Technical Files & Data", explanation: "This Markdown document contains technical design notes.", size: "16 KB", isSelected: true),
            .init(id: "archive", name: "archive.zip", kind: .file, currentPath: "Telegram/archive.zip", proposedCategory: "Archives", explanation: "ZIP files are grouped with other compressed archives.", size: "3.9 MB", isSelected: true),
            .init(id: "hcl", name: "Hcl Documents", kind: .folder, currentPath: "Telegram/Hcl Documents", proposedCategory: "Education & Employment", explanation: "The folder contains employment, education, and related personal records. It will move intact.", size: "28 MB", isSelected: true)
        ]

        for category in categories {
            let existingCount = items.filter { $0.proposedCategory == category.title }.count
            guard existingCount < category.totalCount else { continue }
            for index in (existingCount + 1)...category.totalCount {
                let name = generatedName(for: category.id, index: index)
                items.append(
                    .init(
                        id: "generated-\(category.id)-\(index)",
                        name: name,
                        kind: .file,
                        currentPath: "Telegram/\(name)",
                        proposedCategory: category.title,
                        explanation: "The filename, file type, and local metadata consistently match the \(category.title.lowercased()) category.",
                        size: "\(24 + index * 7) KB",
                        isSelected: true
                    )
                )
            }
        }
        return items
    }()

    static let duplicateGroups: [DuplicateGroup] = [
        group("passport", "Passport document", "86b565d04a7", [
            copy("passport-main", "passport Juhi.pdf", "Telegram/passport Juhi.pdf", "5.54 MB"),
            copy("passport-hcl", "passport Juhi.pdf", "Telegram/Hcl Documents/passport Juhi.pdf", "5.54 MB"),
            copy("passport-nested", "passport Juhi.pdf", "Telegram/Hcl Documents/Juhi Docs/passport Juhi.pdf", "5.54 MB")
        ]),
        group("do-tar", "Project archive", "be021add515", [
            copy("do-loose", "do.tar", "Telegram/do.tar", "4.37 MB"),
            copy("do-project", "do.tar", "Telegram/itz_code/do.tar", "4.37 MB", project: true)
        ]),
        group("aadhar", "Identity scan", "3f201700846", [
            copy("aadhar-main", "Aadhar.pdf", "Telegram/Aadhar.pdf", "356 KB"),
            copy("aadhar-merged", "merged.pdf", "Telegram/merged.pdf", "356 KB")
        ]),
        group("statement", "Bank statement", "5cf4ded91c9", [
            copy("statement-named", "bankstatement.pdf", "Telegram/bankstatement.pdf", "134 KB"),
            copy("statement-generic", "_pdf", "Telegram/_pdf", "134 KB"),
            copy("statement-dot", "_pdf.", "Telegram/_pdf.", "134 KB")
        ]),
        group("logs", "Error log", "07221f2991d", [
            copy("logs-named", "error_logs", "Telegram/error_logs", "26 KB"),
            copy("logs-dot", "error_logs.", "Telegram/error_logs.", "26 KB")
        ]),
        group("streams", "Card activity source", "de9c64fb1b1", [
            copy("streams-loose", "cardactivity_streams-1.py", "Telegram/cardactivity_streams-1.py", "10 KB"),
            copy("streams-project", "cardactivity_streams.py", "Telegram/itz-bus-cardactivity1/buscardactivity/cardactivity_streams.py", "10 KB", project: true)
        ]),
        group("test", "Integration test", "cebd883d66e", [
            copy("test-loose", "test_hotd_integration.py", "Telegram/test_hotd_integration.py", "8 KB"),
            copy("test-project", "test_hotd_integration.py", "Telegram/itz-bus-cardactivity1/tests/functionaltests/test_hotd_integration.py", "8 KB", project: true)
        ])
    ]

    static let needsReviewItems: [NeedsReviewItem] = [
        .init(id: "ho", name: "ho.pdf", kindDescription: "PDF document", currentPath: "Telegram/ho.pdf", reason: "The filename and document metadata do not provide enough information.", selectedCategory: nil, hasReviewedDecision: false),
        .init(id: "oa", name: "oa.pdf", kindDescription: "PDF document", currentPath: "Telegram/oa.pdf", reason: "The short filename has no reliable category indicators.", selectedCategory: nil, hasReviewedDecision: false),
        .init(id: "oat", name: "oat.pdf", kindDescription: "PDF document", currentPath: "Telegram/oat.pdf", reason: "The document title is unavailable and the filename is ambiguous.", selectedCategory: nil, hasReviewedDecision: false),
        .init(id: "p", name: "p.pdf", kindDescription: "PDF document", currentPath: "Telegram/p.pdf", reason: "There is not enough context to make a safe suggestion.", selectedCategory: nil, hasReviewedDecision: false),
        .init(id: "numeric1", name: "1765123568029 (1).pdf", kindDescription: "PDF document", currentPath: "Telegram/1765123568029 (1).pdf", reason: "The numeric filename does not describe the document.", selectedCategory: nil, hasReviewedDecision: false),
        .init(id: "numeric2", name: "784829610_3e65258c72ab4cb09cfba56cd0124c73-280725-1336-180.pdf", kindDescription: "PDF document", currentPath: "Telegram/784829610_3e65258c72ab4cb09cfba56cd0124c73-280725-1336-180.pdf", reason: "The generated filename cannot be classified reliably.", selectedCategory: nil, hasReviewedDecision: false)
    ]

    static let protectedProjects: [ProtectedProject] = [
        .init(id: "ansible", name: "ansible-itz-ing", path: "Telegram/ansible-itz-ing", containedFiles: 786, reason: "Contains Ansible roles, inventories, templates, and project configuration."),
        .init(id: "review", name: "adept-review-reactor", path: "Telegram/adept-review-reactor", containedFiles: 94, reason: "Contains a complete application project and test suite."),
        .init(id: "shared", name: "csdp-shared-resources", path: "Telegram/csdp-shared-resources", containedFiles: 512, reason: "Contains shared source packages, charts, and build files."),
        .init(id: "testwr", name: "testwr", path: "Telegram/testwr", containedFiles: 688, reason: "Contains two related reader and writer software projects."),
        .init(id: "itz", name: "itz_code", path: "Telegram/itz_code", containedFiles: 421, reason: "Contains nested Git repositories and packaged project archives."),
        .init(id: "bus", name: "itz-bus-cardactivity1", path: "Telegram/itz-bus-cardactivity1", containedFiles: 286, reason: "Contains application source, tests, and project configuration."),
        .init(id: "snake", name: "snakebyte", path: "Telegram/snakebyte", containedFiles: 162, reason: "Contains a Python package, tests, and generated build outputs.")
    ]

    static let previousActivity: [ActivitySession] = [
        .init(id: "downloads", folderName: "Downloads", dateDescription: "Today at 2:18 PM", moveCount: 164, trashCount: 0, isUndone: false)
    ]

    private static func copy(_ id: String, _ name: String, _ path: String, _ size: String, project: Bool = false) -> DuplicateCopy {
        .init(id: id, name: name, path: path, size: size, isInsideProject: project)
    }

    private static func group(_ id: String, _ title: String, _ hash: String, _ copies: [DuplicateCopy]) -> DuplicateGroup {
        .init(
            id: id,
            title: title,
            hashPrefix: hash,
            copies: copies,
            canonicalCopyID: copies.first(where: \.isInsideProject)?.id ?? copies.first?.id,
            decision: .pending
        )
    }

    private static func generatedName(for categoryID: String, index: Int) -> String {
        switch categoryID {
        case "identity": "Personal document \(index).pdf"
        case "education": "Employment record \(index).pdf"
        case "finance": "Financial statement \(index).pdf"
        case "housing": "Property document \(index).pdf"
        case "health": "Medical record \(index).pdf"
        case "technical": "technical-note-\(index).txt"
        case "archives": "archive-\(index).tar"
        default: "Uncategorised document \(index).pdf"
        }
    }
}
