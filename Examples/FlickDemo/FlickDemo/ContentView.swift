import flickUI
import SwiftUI

struct ContentView: View {
    @State private var selection = DemoPage.home.id
    @State private var settings = DemoSettings()
    @State private var showsSettings = false
    @State private var lastEvent = "Swipe in from any edge"

    private var page: DemoPage {
        DemoPage(rawValue: selection) ?? .home
    }

    var body: some View {
        PageView(page: page, lastEvent: lastEvent) {
            showsSettings = true
        }
        .flickMenu(DemoPage.allCases, selection: $selection, edges: settings.edges) { page, _ in
            Label(page.title, systemImage: page.symbol)
                .foregroundStyle(.primary)
        } icon: { page in
            Image(systemName: page.symbol)
        }
        .modifier(EdgeAppearanceModifier(appearance: settings.sides, edges: .horizontal))
        .modifier(EdgeAppearanceModifier(appearance: settings.effectiveEnds, edges: .vertical))
        .flickMenuHome(settings.home, position: settings.homePosition)
        .flickMenuFeedback(settings.feedback.feedback)
        .onFlickMenuEvent { event in
            lastEvent = describe(event)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(settings: $settings)
                .presentationDetents([.medium, .large])
        }
    }

    private func describe(_ event: FlickMenuEvent) -> String {
        switch event {
        case let .opened(edge): "opened from \(edge)"
        case let .highlighted(index): "highlighted \(DemoPage.allCases[index].title)"
        case let .chose(index): "chose \(DemoPage.allCases[index].title)"
        case .dismissed: "dismissed"
        }
    }
}

#Preview {
    ContentView()
}
