import Foundation
import Testing
@testable import WebcamsCore

struct CitaTrafficTests {
    @Test func parsesEvents() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d2:payload xsi:type="sit:SituationPublication" xmlns:com="http://datex2.eu/schema/3/common" \
        xmlns:loc="http://datex2.eu/schema/3/locationReferencing" xmlns:d2="http://datex2.eu/schema/3/d2Payload" \
        xmlns:sit="http://datex2.eu/schema/3/situation" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <com:feedDescription><com:values><com:value lang="en">Active and planned events</com:value></com:values></com:feedDescription>
          <sit:situation id="238034">
            <sit:situationRecord xsi:type="sit:MaintenanceWorks" id="238034-1" version="3">
              <sit:situationRecordVersionTime>2026-10-23T19:53:06+02:00</sit:situationRecordVersionTime>
              <sit:validity><com:validityTimeSpecification>
                <com:overallStartTime>2026-10-23T19:52:34+02:00</com:overallStartTime>
              </com:validityTimeSpecification></sit:validity>
              <sit:impact>
                <sit:numberOfLanesRestricted>2</sit:numberOfLanesRestricted>
                <sit:numberOfOperationalLanes>0</sit:numberOfOperationalLanes>
              </sit:impact>
              <sit:generalPublicComment><sit:comment><com:values>
                <com:value lang="lb">Renouvellement tapis Lankelz</com:value>
              </com:values></sit:comment></sit:generalPublicComment>
              <sit:locationReference xsi:type="loc:LocationGroupByList">
                <loc:locationContainedInGroup xsi:type="loc:LinearLocation">
                  <loc:supplementaryPositionalDescription>
                    <loc:lengthAffected>11.0</loc:lengthAffected>
                    <loc:locationDescription><com:values><com:value lang="fr">Section courante</com:value></com:values></loc:locationDescription>
                    <loc:roadInformation>
                      <loc:roadDestination>Collectrice du Sud, vers Schengen</loc:roadDestination>
                      <loc:roadName>A13</loc:roadName>
                    </loc:roadInformation>
                  </loc:supplementaryPositionalDescription>
                </loc:locationContainedInGroup>
                <loc:locationContainedInGroup xsi:type="loc:PointLocation">
                  <loc:pointByCoordinates><loc:pointCoordinates>
                    <loc:latitude>49.514698</loc:latitude><loc:longitude>5.975032</loc:longitude>
                  </loc:pointCoordinates></loc:pointByCoordinates>
                </loc:locationContainedInGroup>
              </sit:locationReference>
              <sit:roadMaintenanceType>maintenanceWork</sit:roadMaintenanceType>
            </sit:situationRecord>
          </sit:situation>
          <sit:situation id="238033">
            <sit:situationRecord xsi:type="sit:VehicleObstruction" id="238033-1" version="1">
              <sit:validity><com:validityTimeSpecification>
                <com:overallStartTime>2026-10-23T19:15:34+02:00</com:overallStartTime>
                <com:overallEndTime>2026-10-23T21:00:00.5+02:00</com:overallEndTime>
              </com:validityTimeSpecification></sit:validity>
              <sit:vehicleObstructionType>brokenDownVehicle</sit:vehicleObstructionType>
            </sit:situationRecord>
          </sit:situation>
        </d2:payload>
        """
        let events = try CitaTraffic.parseEvents(Data(xml.utf8))
        #expect(events.map(\.id) == ["238034-1", "238033-1"])

        let works = events[0]
        #expect(works.kind == .roadworks)
        #expect(works.cause == "maintenanceWork")
        #expect(works.road == "A13")
        #expect(works.destination == "Collectrice du Sud, vers Schengen")
        #expect(works.place == "Section courante")
        #expect(works.comment == "Renouvellement tapis Lankelz")
        #expect(works.closesRoad)
        #expect(works.length == 11)
        #expect(works.coordinate == WebcamCatalog.Coordinate(latitude: 49.514698, longitude: 5.975032))
        #expect(works.startTime == Date(timeIntervalSince1970: 1_792_777_954))
        #expect(works.isActive(at: Date(timeIntervalSince1970: 1_792_790_000)))

        let breakdown = events[1]
        #expect(breakdown.kind == .breakdown)
        #expect(breakdown.road == nil && breakdown.coordinate == nil)
        let end = try #require(breakdown.endTime)
        #expect(!breakdown.isActive(at: end))
    }

    @Test func parsesTravelTimes() {
        let kml = """
        <kml><Document id ='PMV'><Folder id ='FeatureLayer0'>
        <Placemark id ='ID_00000'><name>Schengen</name><Snippet maxLines ='0'></Snippet><description><![CDATA[
        <span class='time'>LUX-SUD:\t19min</span>
        <span class='time'>BELGIQUE:\t--</span>
        ]]></description><Point><coordinates>6.363120004210724,49.47816817462979</coordinates></Point></Placemark>
        <Placemark id ='ID_00001'><name>Lux-Sud</name><description><![CDATA[
        <span class='time'>FRANCE:\t9min</span>
        ]]></description><Point><coordinates>6.1328,49.5844</coordinates></Point></Placemark>
        </Folder></Document></kml>
        """
        let signs = CitaTraffic.parseTravelTimes(kml)
        #expect(signs.map(\.id) == ["schengen", "lux-sud"])
        #expect(signs[0].coordinate.latitude == 49.47816817462979)
        #expect(signs[0].destinations == [.init(name: "LUX-SUD", minutes: 19), .init(name: "BELGIQUE", minutes: nil)])
    }

    @Test func matchesCamerasAndMotorways() throws {
        var event = TrafficEvent(id: "1", type: "Accident")
        event.road = "a13"
        event.coordinate = .init(latitude: 49.5147, longitude: 5.9750)
        let catalog = try #require(CatalogStore.bundled())
        let motorway = try #require(catalog.motorway(withID: "a13"))
        #expect(motorway.events(in: [event]) == [event])

        let camera = WebcamCatalog.Camera(
            id: "13034", place: "Sanem", imageURL: try #require(URL(string: "https://www.cita.lu/cccam_13034.jpg")),
            coordinate: .init(latitude: 49.52, longitude: 5.975)
        )
        #expect(camera.nearbyEvents(in: [event]) == [event])
        #expect(camera.nearbyEvents(in: [event], within: 100).isEmpty)
    }

    @Test func snapshotDecodes() throws {
        let json = """
        {"id": "238034-1", "type": "MaintenanceWorks", "road": "A13", "startTime": "2026-10-23T17:52:34Z",
         "endTime": null, "coordinate": {"latitude": 49.5, "longitude": 5.9}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(TrafficEvent.self, from: Data(json.utf8))
        #expect(event.startTime == Date(timeIntervalSince1970: 1_792_777_954))
    }
}
