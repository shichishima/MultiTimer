import SwiftUI

@main
struct MultiTimerApp: App {
    @State private var store = TimerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 800, height: 520)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(store)
        }
        #endif
    }
}
