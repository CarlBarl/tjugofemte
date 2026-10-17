import SwiftUI

@main
struct TjugofemteApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handleOpenURL($0) }
        }
    }
}
