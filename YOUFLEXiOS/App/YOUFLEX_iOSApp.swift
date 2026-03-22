import SwiftUI

@main
struct YOUFLEX_iOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppView(model: model)
        }
    }
}
