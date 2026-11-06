import SwiftUI

@main
struct CirrusApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    await model.bootstrap()
                    #if DEBUG
                    await DebugDriver.run(model)
                    #endif
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.enterForeground()
            case .background: model.enterBackground()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
            await model.backgroundSync()
        }
    }
}
