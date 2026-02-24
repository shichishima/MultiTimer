import SwiftUI

@main
struct MultiTimerApp: App {
    @State private var store = TimerStore()

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            iOSRootView()
                .environment(store)
            #else
            ContentView()
                .environment(store)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 520)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(store)
        }
        #endif
    }
}
