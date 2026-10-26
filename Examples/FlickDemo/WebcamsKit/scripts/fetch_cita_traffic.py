#!/usr/bin/env python3
"""Fetch the live traffic cita.lu publishes as open data on data.public.lu.

Standard library only. Prints JSON to stdout, or writes it to a file:

    python3 fetch_cita_traffic.py
    python3 fetch_cita_traffic.py -o traffic.json

Output shape:

    {
      "fetchedAt":   "2026-10-23T14:30:00Z",
      "events":      [{"id", "type", "cause", "road", "destination", "place", "comment",
                       "startTime", "endTime", "updatedAt", "lanesRestricted",
                       "operationalLanes", "length", "coordinate"}],
      "travelTimes": [{"id", "name", "coordinate", "destinations": [{"name", "minutes"}]}]
    }

"events" are incidents and roadworks from the DATEX II v3.6 situation
records, "travelTimes" are the overhead signs from the travel times KML.
Both change by the minute, so the app reads them live; this snapshot shows
what it gets. Their keys match WebcamsKit's TrafficEvent and TravelTimeSign.
Like WebcamsKit's Traffic folder, this file can be deleted on its own.
"""

import argparse
import html
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

USER_AGENT = "Mozilla/5.0 (compatible; cita-fetch/1.0)"

EVENTS_URL = "https://cita.lu/info_trafic/datex/situationrecord36"
TRAVEL_TIMES_URL = "https://www.cita.lu/kml/temps_parcours.kml"
SIT = "{http://datex2.eu/schema/3/situation}"
LOC = "{http://datex2.eu/schema/3/locationReferencing}"
COM = "{http://datex2.eu/schema/3/common}"
XSI_TYPE = "{http://www.w3.org/2001/XMLSchema-instance}type"
# The subtype element of each record type, e.g. <sit:vehicleObstructionType>
CAUSES = ["roadMaintenanceType", "constructionWorkType", "vehicleObstructionType",
          "faultyEquipmentOrSystemType", "obstructionType", "abnormalTrafficType",
          "accidentType", "poorEnvironmentType", "roadOrCarriagewayOrLaneManagementType"]
# One sign: <Placemark id ='ID_00000'><name>Schengen</name> … CDATA … <coordinates>lon,lat
SIGN = re.compile(
    r"<Placemark[^>]*>\s*<name>([^<]*)</name>.*?"
    r"<description><!\[CDATA\[(.*?)\]\]></description>.*?"
    r"<coordinates>\s*([-\d.]+),([-\d.]+)",
    re.S,
)
# "LUX-SUD:\t19min"; the time may be missing when a sign is off
SIGN_LINE = re.compile(r"<span class='time'>\s*([^:<]+?)\s*:\s*([^<]*?)\s*</span>")


def get_url(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def text(fragment):
    return " ".join(html.unescape(re.sub(r"<[^>]+>", "", fragment)).split())


def utc(timestamp):
    """A feed time such as 2026-10-23T19:52:34+02:00, in UTC."""
    if not timestamp:
        return None
    date = datetime.fromisoformat(timestamp.strip().replace("Z", "+00:00"))
    return date.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def number(element, cast):
    return cast(float(element.text)) if element is not None and element.text else None


def first_value(element):
    """The first translation in a <com:values> list."""
    if element is None:
        return None
    value = element.find(f".//{COM}value")
    return " ".join(value.text.split()) if value is not None and value.text else None


def fetch_events():
    root = ET.fromstring(get_url(EVENTS_URL))
    events = []
    for record in root.iter(f"{SIT}situationRecord"):
        cause = next((record.findtext(f".//{SIT}{tag}") for tag in CAUSES
                      if record.find(f".//{SIT}{tag}") is not None), None)
        point = record.find(f".//{LOC}pointCoordinates")
        events.append({
            "id": record.get("id"),
            "type": record.get(XSI_TYPE, "").split(":")[-1],
            "cause": cause,
            "road": record.findtext(f".//{LOC}roadName"),
            "destination": record.findtext(f".//{LOC}roadDestination"),
            "place": first_value(record.find(f".//{LOC}locationDescription")),
            "comment": first_value(record.find(f"{SIT}generalPublicComment/{SIT}comment")),
            "startTime": utc(record.findtext(f".//{COM}overallStartTime")),
            "endTime": utc(record.findtext(f".//{COM}overallEndTime")),
            "updatedAt": utc(record.findtext(f"{SIT}situationRecordVersionTime")),
            "lanesRestricted": number(record.find(f".//{SIT}numberOfLanesRestricted"), int),
            "operationalLanes": number(record.find(f".//{SIT}numberOfOperationalLanes"), int),
            "length": number(record.find(f".//{LOC}lengthAffected"), float),
            "coordinate": {
                "latitude": float(point.findtext(f"{LOC}latitude")),
                "longitude": float(point.findtext(f"{LOC}longitude")),
            } if point is not None else None,
        })
    return events


def fetch_travel_times():
    kml = get_url(TRAVEL_TIMES_URL).decode("utf-8", errors="replace")
    signs = []
    for name, description, longitude, latitude in SIGN.findall(kml):
        name = text(name)
        destinations = []
        for destination, time in SIGN_LINE.findall(description):
            minutes = re.fullmatch(r"(\d+)\s*min", time)
            destinations.append({
                "name": text(destination),
                "minutes": int(minutes.group(1)) if minutes else None,
            })
        signs.append({
            "id": re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-"),
            "name": name,
            "coordinate": {"latitude": float(latitude), "longitude": float(longitude)},
            "destinations": destinations,
        })
    return signs


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-o", "--output", help="write to this file instead of stdout")
    args = parser.parse_args()

    data = json.dumps({
        "fetchedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "events": fetch_events(),
        "travelTimes": fetch_travel_times(),
    }, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(data)
    else:
        sys.stdout.write(data)


if __name__ == "__main__":
    main()
