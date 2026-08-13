import SwiftUI

struct JarvisDashboardApp: App {
    @StateObject private var store = DataStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 620)
                .onAppear { OverlayController.shared.show(store: store) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 880)
    }
}

JarvisDashboardApp.main()
