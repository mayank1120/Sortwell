import AppKit

@MainActor
final class SortwellAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: PrototypeStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.isOperationActive else { return .terminateNow }

        store.prepareForTermination()
        Task { @MainActor [weak store] in
            while store?.isOperationActive == true {
                try? await Task.sleep(for: .milliseconds(100))
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
