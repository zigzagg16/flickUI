import Foundation

/// The latest road reports, shared by the app, which makes them, with the widget,
/// which shows them, through an App Group.
enum RoadReportStore {
    static let appGroup = "group.dev.flickui.FlickDemo"

    /// Reports older than this are dropped.
    private static let keptFor: TimeInterval = 24 * 60 * 60

    /// `nil` without the App Group entitlement, and then nothing is shared.
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "RoadReports.json")
    }

    static func load() -> [String: RoadReport] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: RoadReport].self, from: data)) ?? [:]
    }

    /// Adds or replaces reports, by camera number.
    static func save(_ reports: [String: RoadReport]) {
        guard let fileURL else { return }
        var all = load().merging(reports) { _, new in new }
        let oldest = Date.now.addingTimeInterval(-keptFor)
        all = all.filter { $0.value.date > oldest }
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// A camera's report, if it is recent enough to still describe the road.
    static func report(forCamera id: String, maxAge: TimeInterval = 30 * 60) -> RoadReport? {
        guard let report = load()[id], Date.now.timeIntervalSince(report.date) < maxAge else { return nil }
        return report
    }
}
