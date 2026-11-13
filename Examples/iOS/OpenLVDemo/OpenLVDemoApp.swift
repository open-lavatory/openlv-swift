import SwiftUI

@main
struct OpenLVDemoApp: App {
    @StateObject private var model = SessionModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onChange(of: scenePhase) { phase in
                    if phase == .background { model.disconnect() }
                }
        }
    }
}
