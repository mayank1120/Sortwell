import AppKit
import SwiftUI
import XCTest
@testable import Sortwell

@MainActor
final class VisualSnapshotTests: XCTestCase {
    func testRenderScreens() throws {
        let outputURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VisualSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let store = PrototypeStore(loadPersistedActivity: false)
        try render(RootView().environment(store), named: "01-welcome-light", size: .init(width: 1180, height: 760), scheme: .light, to: outputURL)

        store.route = .scan
        store.scanProgress = 0.64
        try render(RootView().environment(store), named: "02a-scan-light", size: .init(width: 1180, height: 760), scheme: .light, to: outputURL)

        store.route = .summary
        try render(RootView().environment(store), named: "02-summary-light", size: .init(width: 1180, height: 760), scheme: .light, to: outputURL)
        try render(RootView().environment(store), named: "02b-summary-compact", size: .init(width: 960, height: 640), scheme: .light, to: outputURL)

        store.route = .review
        store.reviewSection = .organisation
        try render(RootView().environment(store), named: "03-review-light", size: .init(width: 1180, height: 760), scheme: .light, to: outputURL)

        store.reviewSection = .duplicates
        try render(RootView().environment(store), named: "04-duplicates-light", size: .init(width: 1180, height: 760), scheme: .light, to: outputURL)
        try render(RootView().environment(store), named: "05-duplicates-compact", size: .init(width: 960, height: 640), scheme: .light, to: outputURL)

        store.reviewSection = .needsReview
        try render(RootView().environment(store), named: "05a-needs-review-light", size: .init(width: 1180, height: 760), scheme: .light, to: outputURL)
        try render(RootView().environment(store), named: "05a-needs-review-compact", size: .init(width: 960, height: 640), scheme: .light, to: outputURL)

        store.reviewSection = .protectedProjects
        try render(RootView().environment(store), named: "05b-protected-light", size: .init(width: 1180, height: 760), scheme: .light, to: outputURL)

        store.reviewSection = .organisation
        try render(RootView().environment(store), named: "05c-review-dark", size: .init(width: 1180, height: 760), scheme: .dark, to: outputURL)

        store.route = .applying
        store.applyProgress = 0.62
        try render(RootView().environment(store), named: "05d-applying-light", size: .init(width: 1180, height: 760), scheme: .light, to: outputURL)

        store.route = .results
        try render(RootView().environment(store), named: "06-results-dark", size: .init(width: 1180, height: 760), scheme: .dark, to: outputURL)
        try render(RootView().environment(store), named: "06-results-compact", size: .init(width: 960, height: 640), scheme: .light, to: outputURL)

        store.route = .activity
        try render(RootView().environment(store), named: "06a-activity-light", size: .init(width: 1180, height: 760), scheme: .light, to: outputURL)

        try render(ConfirmationView().environment(store), named: "07-confirmation-light", size: .init(width: 650, height: 680), scheme: .light, to: outputURL)
        try render(ConfirmationView().environment(store), named: "07-confirmation-dark", size: .init(width: 650, height: 680), scheme: .dark, to: outputURL)
    }

    private func render<Content: View>(
        _ content: Content,
        named name: String,
        size: CGSize,
        scheme: ColorScheme,
        to directory: URL
    ) throws {
        let view = content
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not create bitmap for \(name)")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        guard let data = representation.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode \(name)")
            return
        }

        XCTAssertGreaterThan(representation.pixelsWide, 0)
        XCTAssertGreaterThan(representation.pixelsHigh, 0)
        XCTAssertGreaterThan(data.count, 5_000, "Rendered snapshot \(name) appears unexpectedly empty")

        try data.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
