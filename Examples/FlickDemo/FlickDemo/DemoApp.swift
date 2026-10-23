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

    /// The UserDefaults key of the app on screen, remembered between launches.
    static let currentKey = "demoApp"

    /// The UserDefaults key of the app to open at launch: a `DemoApp` raw value, or
    /// nothing to reopen the last one. It can also be passed as a launch argument,
    /// `-launchApp webcams`, as the Webcams scheme does.
    static let launchKey = "launchApp"

    /// Applies the launch setting. Call it once, at launch.
    static func applyLaunchSetting(to defaults: UserDefaults = .standard) {
        guard let raw = defaults.string(forKey: launchKey), let app = DemoApp(rawValue: raw) else { return }
        defaults.set(app.rawValue, forKey: currentKey)
    }
}

struct RootView: View {
    @AppStorage(DemoApp.currentKey) private var app = DemoApp.showcase
    @State private var webcamLink: WebcamLink?

    var body: some View {
        Group {
            switch app {
            case .showcase: ContentView()
            case .webcams: WebcamsView(link: webcamLink)
            }
        }
        .onOpenURL { url in
            guard let link = WebcamLink(url: url) else { return }
            app = .webcams
            webcamLink = link
        }
    }
}

/// A menu button that switches between the demo apps and sets the one opened at launch.
struct AppSwitcher: View {
    @AppStorage(DemoApp.currentKey) private var app = DemoApp.showcase
    @AppStorage(DemoApp.launchKey) private var launchApp = ""

    var body: some View {
        Menu {
            Picker("App", selection: $app) {
                ForEach(DemoApp.allCases) { app in
                    Label(app.title, systemImage: app.symbol).tag(app)
                }
            }
            Picker("Open at Launch", systemImage: "power", selection: $launchApp) {
                Text("Last Used").tag("")
                ForEach(DemoApp.allCases) { app in
                    Text(app.title).tag(app.rawValue)
                }
            }
            .pickerStyle(.menu)
        } label: {
            Label("Apps", systemImage: "square.grid.2x2")
        }
    }
}
