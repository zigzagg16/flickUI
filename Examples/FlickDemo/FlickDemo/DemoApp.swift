import SwiftUI

/// The apps in the demo, each built around a flick menu.
enum DemoApp: String, CaseIterable, Identifiable {
    case showcase, webcams

    var id: Self { self }

    var title: String {
        switch self {
        case .showcase: "Showcase"
        case .webcams: "Webcams"
        }
    }

    var symbol: String {
        switch self {
        case .showcase: "sparkles"
        case .webcams: "web.camera.fill"
        }
    }
}

struct RootView: View {
    @AppStorage("demoApp") private var app = DemoApp.showcase

    var body: some View {
        switch app {
        case .showcase: ContentView()
        case .webcams: WebcamsView()
        }
    }
}

/// A menu button that switches between the demo apps.
struct AppSwitcher: View {
    @AppStorage("demoApp") private var app = DemoApp.showcase

    var body: some View {
        Menu {
            Picker("App", selection: $app) {
                ForEach(DemoApp.allCases) { app in
                    Label(app.title, systemImage: app.symbol).tag(app)
                }
            }
        } label: {
            Label("Apps", systemImage: "square.grid.2x2")
        }
    }
}
