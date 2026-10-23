import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the app gets its ``WebcamCatalog``: the backend when there is one, the last
/// catalog it sent, or the one bundled with the app.
///
/// The backend's address is the `WebcamCatalogURL` Info.plist key; while it is empty,
/// the bundled `catalog.json` is used. The last downloaded catalog is kept in the
/// ``SharedContainer``, so the widget sees it too.
public enum CatalogStore {
    /// The backend's address, if the app has one.
    public static var remoteURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "WebcamCatalogURL") as? String,
              !value.isEmpty
        else { return nil }
        return URL(string: value)
    }

    /// The catalog available right away, without the network: the last downloaded
    /// one, or the bundled one.
    public static func current() -> WebcamCatalog {
        cached() ?? bundled() ?? .empty
    }

    /// Asks the backend for a new catalog when the current one is too old, and falls
    /// back to ``current()`` when it can't.
    public static func refreshed() async -> WebcamCatalog {
        let current = current()
        guard let remoteURL else { return current }
        let maxAge = current.settings.catalogMaxAge ?? 24 * 60 * 60
        if let cached = cached(), Date.now.timeIntervalSince(cached.updatedAt) < maxAge {
            return cached
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let catalog = try WebcamCatalog.decode(from: data)
            if let cacheURL {
                try? data.write(to: cacheURL, options: .atomic)
            }
            return catalog
        } catch {
            return current
        }
    }

    public static func bundled() -> WebcamCatalog? {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? WebcamCatalog.decode(from: data)
    }

    private static func cached() -> WebcamCatalog? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? WebcamCatalog.decode(from: data)
    }

    private static var cacheURL: URL? {
        SharedContainer.url?.appending(path: "WebcamCatalog.json")
    }
}
