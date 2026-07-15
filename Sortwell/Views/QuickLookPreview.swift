import QuickLookUI
import SwiftUI

struct SecurityScopedQuickLookPreview: NSViewRepresentable {
    let fileURL: URL
    let accessRootURL: URL?

    final class Coordinator {
        var accessedURL: URL?
        var isAccessing = false

        func updateAccess(to url: URL?) {
            let standardURL = url?.standardizedFileURL
            guard standardURL != accessedURL?.standardizedFileURL else { return }
            stopAccessing()
            guard let standardURL else { return }
            accessedURL = standardURL
            isAccessing = standardURL.startAccessingSecurityScopedResource()
        }

        func stopAccessing() {
            if isAccessing, let accessedURL {
                accessedURL.stopAccessingSecurityScopedResource()
            }
            accessedURL = nil
            isAccessing = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.updateAccess(to: accessRootURL)
        guard let view = QLPreviewView(frame: .zero, style: .compact) else {
            let fallback = NSTextField(labelWithString: "Preview unavailable")
            fallback.alignment = .center
            fallback.setAccessibilityLabel("Preview unavailable for \(fileURL.lastPathComponent)")
            return fallback
        }
        view.autostarts = false
        view.shouldCloseWithWindow = false
        view.previewItem = fileURL as NSURL
        view.setAccessibilityLabel("Preview of \(fileURL.lastPathComponent)")
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.updateAccess(to: accessRootURL)
        guard let view = view as? QLPreviewView else { return }
        if (view.previewItem as? URL) != fileURL {
            view.previewItem = fileURL as NSURL
            view.setAccessibilityLabel("Preview of \(fileURL.lastPathComponent)")
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        (view as? QLPreviewView)?.close()
        coordinator.stopAccessing()
    }
}
