import SwiftUI

/// The menu items of the demo: one full-screen page each.
enum DemoPage: String, CaseIterable, Identifiable {
    case home, explore, music, photos, messages, settings

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .explore: "safari.fill"
        case .music: "music.note"
        case .photos: "photo.on.rectangle.angled"
        case .messages: "message.fill"
        case .settings: "gearshape.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .home: [.blue, .indigo]
        case .explore: [.teal, .green]
        case .music: [.pink, .purple]
        case .photos: [.orange, .red]
        case .messages: [.green, .mint]
        case .settings: [.gray, .black]
        }
    }
}

struct PageView: View {
    let page: DemoPage
    let lastEvent: String
    let onCustomize: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: page.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: page.symbol)
                    .font(.system(size: 72, weight: .semibold))
                    .symbolEffect(.bounce, value: page)
                Text(page.title)
                    .font(.largeTitle.bold())
                Text("Swipe in from an edge, slide to an item, lift to choose.\nOr tap the indicator.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                Text(lastEvent)
                    .font(.footnote.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                Button("Customize", systemImage: "slider.horizontal.3", action: onCustomize)
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.25))
            }
            .foregroundStyle(.white)
        }
        .animation(.smooth, value: page)
    }
}
