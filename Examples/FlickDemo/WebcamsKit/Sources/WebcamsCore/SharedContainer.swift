import Foundation

/// Where the app and its widget share files and settings.
///
/// On Apple platforms it is the App Group; elsewhere, such as on Android, there is no
/// such group, and the app's own support directory is used.
public enum SharedContainer {
    public static let appGroup = "group.dev.flickui.FlickDemo"

    /// `nil` without the App Group entitlement, and then nothing is shared.
    public static var url: URL? {
        #if canImport(Darwin)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        #else
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
        #endif
    }

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}
