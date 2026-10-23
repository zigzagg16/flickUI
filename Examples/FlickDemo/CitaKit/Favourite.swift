import Foundation

/// A favourite: a motorway's live stream, or one of its cameras.
struct Favourite: Codable, Hashable, Identifiable, Sendable {
    enum Feed: Codable, Hashable, Sendable {
        case live
        /// A camera, by its identifier.
        case camera(String)
    }

    var motorwayID: String
    var feed: Feed

    var id: String {
        switch feed {
        case .live: "\(motorwayID)/live"
        case let .camera(cameraID): "\(motorwayID)/\(cameraID)"
        }
    }
}

/// Saves the favourites in the App Group, so the widget can offer them too.
enum FavouriteStore {
    private static let key = "favourites"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: RoadReportStore.appGroup) ?? .standard
    }

    static func load() -> [Favourite] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Favourite].self, from: data)) ?? []
    }

    static func save(_ favourites: [Favourite]) {
        defaults.set(try? JSONEncoder().encode(favourites), forKey: key)
    }
}
