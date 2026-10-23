import SwiftUI

@main
struct FlickDemoApp: App {
    init() {
        DemoApp.applyLaunchSetting()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
