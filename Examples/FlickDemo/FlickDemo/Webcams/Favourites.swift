import Foundation
import Observation
import SwiftUI

/// The user's favourites, in their order, saved as they change.
@MainActor @Observable
final class Favourites {
    private(set) var items = FavouriteStore.load()

    func contains(_ favourite: Favourite) -> Bool {
        items.contains(favourite)
    }

    func toggle(_ favourite: Favourite) {
        if let index = items.firstIndex(of: favourite) {
            items.remove(at: index)
        } else {
            items.append(favourite)
        }
        FavouriteStore.save(items)
    }

    func remove(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        FavouriteStore.save(items)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        FavouriteStore.save(items)
    }
}

/// Lists, orders and adds favourites: a motorway first, then its live stream or a camera.
struct FavouritesEditor: View {
    let motorways: [Motorway]
    /// A favourite's name, such as "A13 · Sanem → Pétange".
    let name: @MainActor (Favourite) -> String
    /// A motorway's cameras, read from its page if the catalog lists none.
    let cameras: @MainActor (Motorway) async -> [Webcam]
    @Environment(Favourites.self) private var favourites
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(favourites.items) { favourite in
                        Label(name(favourite), systemImage: favourite.feed == .live ? "play.tv.fill" : "web.camera.fill")
                    }
                    .onDelete { favourites.remove(atOffsets: $0) }
                    .onMove { favourites.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Favourites")
                } footer: {
                    if favourites.items.isEmpty {
                        Text("Choose a motorway below, then its live stream or a camera.")
                    } else {
                        Text("They show under ★ Favourites in the motorway menu.")
                    }
                }
                Section("Add a Favourite") {
                    ForEach(motorways) { motorway in
                        NavigationLink {
                            FavouritePicker(motorway: motorway, cameras: cameras)
                        } label: {
                            Label(motorway.title, systemImage: motorway.menuSymbol)
                        }
                    }
                }
            }
            .navigationTitle("Favourites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A motorway's live stream and cameras, each with a star to add or remove it.
struct FavouritePicker: View {
    let motorway: Motorway
    let cameras: @MainActor (Motorway) async -> [Webcam]
    @State private var loaded: [Webcam]?
    @Environment(Favourites.self) private var favourites

    var body: some View {
        List {
            if motorway.liveStream != nil {
                row(Favourite(motorwayID: motorway.id, feed: .live), title: "Live stream", symbol: "play.tv.fill")
            }
            Section("Cameras") {
                if let loaded {
                    ForEach(loaded) { camera in
                        row(Favourite(motorwayID: motorway.id, feed: .camera(camera.id)), title: camera.title, symbol: camera.symbol)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle(motorway.shortName)
        .task {
            loaded = await cameras(motorway)
        }
    }

    private func row(_ favourite: Favourite, title: String, symbol: String) -> some View {
        Button {
            favourites.toggle(favourite)
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: favourites.contains(favourite) ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityAddTraits(favourites.contains(favourite) ? .isSelected : [])
    }
}
