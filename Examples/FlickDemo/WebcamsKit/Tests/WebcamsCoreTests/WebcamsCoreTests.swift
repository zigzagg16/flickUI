import Foundation
import Testing
@testable import WebcamsCore

struct CatalogTests {
    @Test func bundledCatalogDecodes() throws {
        let catalog = try #require(CatalogStore.bundled())
        #expect(!catalog.motorways.isEmpty)
        #expect(catalog.orderedMotorways.allSatisfy { !$0.enabledCameras.isEmpty || $0.liveStream != nil })
    }

    @Test func listedCamerasHavePositions() throws {
        let catalog = try #require(CatalogStore.bundled())
        let cameras = catalog.motorways.flatMap(\.cameras)
        #expect(!cameras.isEmpty)
        #expect(cameras.allSatisfy { $0.coordinate != nil && $0.heading != nil })
    }

    @Test func catalogRoundTrips() throws {
        let catalog = try #require(CatalogStore.bundled())
        #expect(try WebcamCatalog.decode(from: catalog.encoded()) == catalog)
    }
}

struct CitaWebcamsTests {
    @Test func parsesCameras() throws {
        let html = """
        <h2>A13 : Autoroute de la Sarre</h2>
        <figure id="cam-13034" class="x"><img data-origin="/cccam_13034.jpg">
        <figcaption>Sanem: <span>direction P&#233;tange</span></figcaption></figure>
        """
        let page = CitaWebcams.parse(html, baseURL: try #require(URL(string: "https://www.cita.lu/fr/webcams/a13")))
        #expect(page.title == "A13 : Autoroute de la Sarre")
        let camera = try #require(page.cameras.first)
        #expect(camera.id == "13034")
        #expect(camera.title == "Sanem → Pétange")
        #expect(camera.imageURL.absoluteString == "https://www.cita.lu/cccam_13034.jpg")
    }
}

struct WebcamLinkTests {
    @Test func roundTrips() throws {
        let link = WebcamLink(motorwayID: "a13", cameraID: "13034")
        let parsed = try #require(WebcamLink(url: link.url))
        #expect(parsed.motorwayID == "a13")
        #expect(parsed.cameraID == "13034")
    }
}

struct LiveCameraTests {
    @Test(arguments: [
        ("a6 wg 13,0", "A6 WG 13.0"),
        ("Gantry  A 6 WG 00.7 ", "A6 WG 00.7"),
        ("Croix de Cessange", nil)
    ])
    func readsLabel(line: String, label: String?) {
        #expect(LiveCamera.label(in: line) == label)
    }
}

struct TrafficEstimatorTests {
    @Test func overlap() {
        let box = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
        #expect(TrafficEstimator.overlap(box, box) == 1)
        #expect(TrafficEstimator.overlap(box, box.offsetBy(dx: 0.5, dy: 0)) == 0)
        #expect(abs(TrafficEstimator.overlap(box, box.offsetBy(dx: 0.1, dy: 0)) - 1.0 / 3) < 1e-9)
    }

    @Test func standingVehiclesMeanAJam() {
        var estimator = TrafficEstimator()
        let boxes = (0..<6).map { CGRect(x: Double($0) * 0.15, y: 0.5, width: 0.1, height: 0.1) }
        _ = estimator.update(with: boxes)
        #expect(estimator.update(with: boxes).traffic == .jammed)
    }

    @Test func noVehiclesIsEmpty() {
        var estimator = TrafficEstimator()
        #expect(estimator.update(with: []).traffic == .empty)
    }
}

struct ImageStatisticsTests {
    @Test func blankPicture() {
        let statistics = ImageStatistics(pixels: [UInt8](repeating: 128, count: 64 * 48), width: 64)
        #expect(statistics.isBlank)
        #expect(statistics.light == .day)
    }

    @Test func darkPictureIsNight() {
        let pixels = (0..<(64 * 48)).map { UInt8($0 % 2 == 0 ? 10 : 40) }
        #expect(ImageStatistics(pixels: pixels, width: 64).light == .night)
    }
}
