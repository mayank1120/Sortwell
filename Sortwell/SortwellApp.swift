import SwiftUI

@main
struct SortwellApp: App {
    @NSApplicationDelegateAdaptor(SortwellAppDelegate.self) private var appDelegate
    @State private var store = PrototypeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Review") {
                ForEach(Array(ReviewSection.allCases.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) {
                        store.reviewSection = section
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(store.route != .review)
                }
            }
        }

        Settings {
            SortwellSettingsView()
                .environment(store)
        }
    }
}
