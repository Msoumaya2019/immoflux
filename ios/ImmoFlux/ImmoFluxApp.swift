import SwiftUI

@main struct ImmoFluxApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .task { await store.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refresh() } }
                }
        }
    }
}
