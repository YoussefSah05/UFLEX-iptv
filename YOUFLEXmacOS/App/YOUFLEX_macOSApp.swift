import SwiftUI

@main
struct YOUFLEX_macOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppView(model: model)
                .frame(minWidth: 1100, minHeight: 720)
        }
    }
}
