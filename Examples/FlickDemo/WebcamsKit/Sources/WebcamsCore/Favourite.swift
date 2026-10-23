import Foundation

/// A favourite: a motorway's live stream, or one of its cameras.
public struct Favourite: Codable, Hashable, Identifiable, Sendable {
    public enum Feed: Codable, Hashable, Sendable {
        case live
        /// A camera, by its identifier.
        case camera(String)
    }

    public var motorwayID: String
    public var feed: Feed

    public init(motorwayID: String, feed: Feed) {
        self.motorwayID = motorwayID
        self.feed = feed
    }

    public var id: String {
        switch feed {
        case .live: "\(motorwayID)/live"
        case let .camera(cameraID): "\(motorwayID)/\(cameraID)"
        }
    }
}

/// Saves the favourites in the ``SharedContainer``, so the widget can offer them too.
public enum FavouriteStore {
    private static let key = "favourites"

    private static var defaults: UserDefaults {
        SharedContainer.defaults
    }

    public static func load() -> [Favourite] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Favourite].self, from: data)) ?? []
    }

    public static func save(_ favourites: [Favourite]) {
        defaults.set(try? JSONEncoder().encode(favourites), forKey: key)
    }
}
