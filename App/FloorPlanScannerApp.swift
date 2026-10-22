import SwiftUI

@main
struct FloorPlanScannerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environment(model)
        }
    }
}
