import EigoCore
import SwiftUI

@main
struct EigoMasterApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("英語マスター") {
            ContentView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 640)
                .task { await store.startupChecks() }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("コンテンツを更新…") { Task { await store.updateContent() } }
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .frame(width: 620, height: 520)
        }
    }
}
