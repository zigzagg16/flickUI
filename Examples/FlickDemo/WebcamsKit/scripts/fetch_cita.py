#!/usr/bin/env python3
"""Fetch the highways, webcams, live streams and traffic listed on https://cita.lu.

Standard library only. Prints JSON to stdout, or writes it to a file:

    python3 fetch_cita.py                 # French labels, to stdout
    python3 fetch_cita.py --lang en -o cita.json
    python3 fetch_cita.py --catalog ../Sources/WebcamsCore/Resources/catalog.json

Output shape:

    {
      "source": "https://www.cita.lu",
      "language": "fr",
      "fetchedAt": "2026-10-23T14:30:00Z",
      "highways":    [{"id", "code", "name", "webcamPage", "liveStreamPage"}],
      "webcams":     {"<highway id>": [{"id", "location", "direction", "imageURL", "pageURL",
                                        "coordinate", "heading", "listed"}]},
      "liveStreams": {"<highway id>": {"url", "poster", "page"}},
      "events":      [{"id", "type", "cause", "road", "destination", "place", "comment",
                       "startTime", "endTime", "updatedAt", "lanesRestricted",
                       "operationalLanes", "length", "coordinate"}],
      "travelTimes": [{"id", "name", "coordinate", "destinations": [{"name", "minutes"}]}]
    }

The cameras come from the official source first: the cameras KML on
data.public.lu lists every camera with its road, "coordinate" (latitude,
longitude) and "heading", the way its map icon points in degrees clockwise
from north. The website then fills in what the KML lacks: the place and
direction, the picture, and the highway page each camera is shown on, which
wins over the KML's road. "listed" is false for a camera the website doesn't
show; its picture is then cita.lu's "camera unavailable" placeholder. The
website has no API, so it is read from the HTML: if cita.lu changes its
markup, the patterns below are the only things to update.

With --catalog, the cameras, live streams and pages are also written into
the app's catalog.json: each motorway's cameras are replaced by the ones
fetched, keeping the hand-tuned fields (see KEPT_CAMERA_FIELDS) of cameras
already there. Unlisted cameras are kept but disabled. Use French labels,
the default, for the bundled catalog.

The traffic comes from the open data feeds published on data.public.lu:
"events" are incidents and roadworks from the DATEX II v3.6 situation
records, "travelTimes" are the overhead signs from the travel times KML.
Both change by the minute, so the app reads them live; this snapshot shows
what it gets. Their keys match WebcamsKit's TrafficEvent and TravelTimeSign.
"""

import argparse
import html
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

BASE = "https://www.cita.lu"
USER_AGENT = "Mozilla/5.0 (compatible; cita-fetch/1.0)"

# Links to a highway's page, e.g. <a href="/fr/webcam/a1.html">A1</a>
NAV_LINK = r'href="/{lang}/{section}/([a-z0-9]+)\.html"'
# The page title, e.g. <h2>A1 : Autoroute Luxembourg - Trèves</h2>
TITLE = re.compile(r"<h2>\s*[^<:]+:\s*([^<]+?)\s*</h2>")
# One webcam tile: image URL and "Location: <span>direction X</span>" caption
WEBCAM = re.compile(
    r'<figure id="cam-(\d+)".*?'
    r'data-origin="([^"]+)".*?'
    r"<figcaption>\s*(.*?)\s*:\s*<span>\s*(.*?)\s*</span>",
    re.S,
)
STREAM_URL = re.compile(r"""['"](https?://[^'"]+\.m3u8)['"]""")
POSTER = re.compile(r'<video[^>]*\bposter="([^"]+)"')
DIRECTION_PREFIX = re.compile(r"^(direction|Richtung|towards)\s+", re.I)

EVENTS_URL = "https://cita.lu/info_trafic/datex/situationrecord36"
TRAVEL_TIMES_URL = "https://www.cita.lu/kml/temps_parcours.kml"
CAMERAS_URL = "https://www.cita.lu/kml/cameras.kml"
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
IMAGE_URL = BASE + "/info_trafic/cameras/images/cccam_{id}.jpg"
# One camera: <Placemark id="camera_14"><name>A6 - Camera 14</name> … the icon
# cctv_185.png points to 185° … <coordinates>lon,lat
CAMERA = re.compile(
    r'<Placemark id="camera_(\d+)">\s*<name>\s*([A-Z]+\d+)?.*?'
    r"(?:cctv_(\d+)\.png.*?)?"
    r"<coordinates>\s*([-\d.]+),([-\d.]+)",
    re.S,
)
# "LUX-SUD:\t19min"; the time may be missing when a sign is off
SIGN_LINE = re.compile(r"<span class='time'>\s*([^:<]+?)\s*:\s*([^<]*?)\s*</span>")


def get(path):
    return get_url(BASE + path).decode("utf-8", errors="replace")


def get_url(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def text(fragment):
    return " ".join(html.unescape(re.sub(r"<[^>]+>", "", fragment)).split())


def nav_links(page, lang, section):
    """Highway ids linked from a page, in site order, without duplicates."""
    pattern = re.compile(NAV_LINK.format(lang=lang, section=section))
    return list(dict.fromkeys(pattern.findall(page)))


def fetch_webcams(page):
    cams = []
    for cam_id, image, location, direction in WEBCAM.findall(page):
        cams.append({
            "id": int(cam_id),
            "location": text(location),
            "direction": DIRECTION_PREFIX.sub("", text(direction)),
            "imageURL": image,
            "pageURL": f"{BASE}/webcam/map/{cam_id}/full",
        })
    return cams


def fetch_official_cameras():
    """Every camera in the cameras KML, by id, in its order: road, coordinate, heading."""
    kml = get_url(CAMERAS_URL).decode("utf-8", errors="replace")
    return {
        int(cam_id): {
            "road": road.lower() if road else None,
            "coordinate": {"latitude": float(latitude), "longitude": float(longitude)},
            "heading": int(heading) if heading else None,
        }
        for cam_id, road, heading, longitude, latitude in CAMERA.findall(kml)
    }


def merge_cameras(official, website):
    """The official cameras, filled in with the website's, per highway id."""
    shown_on = {cam["id"]: highway for highway, cams in website.items() for cam in cams}
    webcams = {highway: [] for highway in website}
    # Website order first, as the site lists them, then the cameras it doesn't show.
    for highway, cams in website.items():
        for cam in cams:
            position = official.get(cam["id"])
            if position is None:
                print(f"camera {cam['id']} on {highway} is not in cameras.kml", file=sys.stderr)
            elif position["road"] and position["road"] != highway:
                print(f"camera {cam['id']} is on {position['road']} in cameras.kml, "
                      f"shown on {highway}", file=sys.stderr)
            webcams[highway].append({
                **cam,
                "coordinate": position and position["coordinate"],
                "heading": position and position["heading"],
                "listed": True,
            })
    for cam_id, position in official.items():
        if cam_id in shown_on or not position["road"]:
            continue
        print(f"camera {cam_id} on {position['road']} is on no webcam page", file=sys.stderr)
        webcams.setdefault(position["road"], []).append({
            "id": cam_id,
            "location": None,
            "direction": None,
            "imageURL": IMAGE_URL.format(id=cam_id),
            "pageURL": f"{BASE}/webcam/map/{cam_id}/full",
            "coordinate": position["coordinate"],
            "heading": position["heading"],
            "listed": False,
        })
    return webcams


def fetch_live_stream(page, page_path):
    url = STREAM_URL.search(page)
    if not url:
        return None
    poster = POSTER.search(page)
    return {
        "url": url.group(1),
        "poster": BASE + poster.group(1) if poster else None,
        "page": BASE + page_path,
    }


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


def fetch(lang):
    # The first highway's pages carry the menu listing every highway.
    first_webcam_path = f"/{lang}/webcam/a1.html"
    first_stream_path = f"/{lang}/live-stream/a1.html"
    webcam_menu = nav_links(get(first_webcam_path), lang, "webcam")
    stream_menu = nav_links(get(first_stream_path), lang, "live-stream")

    official = fetch_official_cameras()
    highways, webcams, live_streams = [], {}, {}

    for highway_id in webcam_menu:
        path = f"/{lang}/webcam/{highway_id}.html"
        page = get(path)
        title = TITLE.search(page)
        highways.append({
            "id": highway_id,
            "code": highway_id.upper(),
            "name": text(title.group(1)) if title else highway_id.upper(),
            "webcamPage": BASE + path,
            "liveStreamPage": f"{BASE}/{lang}/live-stream/{highway_id}.html"
            if highway_id in stream_menu else None,
        })
        webcams[highway_id] = fetch_webcams(page)

    # Highways that only have a live stream still belong in the list.
    for highway_id in stream_menu:
        if highway_id not in webcams:
            highways.append({
                "id": highway_id, "code": highway_id.upper(), "name": highway_id.upper(),
                "webcamPage": None,
                "liveStreamPage": f"{BASE}/{lang}/live-stream/{highway_id}.html",
            })

    webcams = merge_cameras(official, webcams)

    for highway_id in stream_menu:
        path = f"/{lang}/live-stream/{highway_id}.html"
        stream = fetch_live_stream(get(path), path)
        if stream:
            live_streams[highway_id] = stream

    return {
        "source": BASE,
        "language": lang,
        "fetchedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "highways": highways,
        "webcams": webcams,
        "liveStreams": live_streams,
        "events": fetch_events(),
        "travelTimes": fetch_travel_times(),
    }


# Camera fields the catalog's editors set by hand, which --catalog keeps.
KEPT_CAMERA_FIELDS = ["refreshInterval", "carriageways"]


def catalog_camera(cam, existing):
    """A catalog camera from a fetched one, keeping the hand-tuned fields of the existing entry."""
    camera = {
        "id": str(cam["id"]),
        "place": cam["location"] or existing.get("place") or f"Caméra {cam['id']}",
        "direction": cam["direction"] or existing.get("direction"),
        "imageURL": cam["imageURL"],
        "coordinate": cam["coordinate"],
        "heading": cam["heading"],
    }
    camera.update({key: existing[key] for key in KEPT_CAMERA_FIELDS if key in existing})
    if not cam["listed"]:
        camera["isEnabled"] = False
    elif "isEnabled" in existing:
        camera["isEnabled"] = existing["isEnabled"]
    return {key: value for key, value in camera.items() if value is not None}


def update_catalog(path, data):
    with open(path, encoding="utf-8") as f:
        catalog = json.load(f)
    motorways = {motorway["id"]: motorway for motorway in catalog["motorways"]}
    for highway in data["highways"]:
        motorway = motorways.get(highway["id"])
        if motorway is None:
            print(f"adding {highway['code']} to the catalog", file=sys.stderr)
            motorway = {"id": highway["id"], "code": highway["code"], "name": highway["name"],
                        "shortName": highway["code"], "cameras": []}
            catalog["motorways"].append(motorway)
            motorways[highway["id"]] = motorway
        if highway["webcamPage"]:
            motorway["website"] = highway["webcamPage"]
        stream = data["liveStreams"].get(highway["id"])
        if stream:
            motorway["liveStream"] = {**motorway.get("liveStream", {}), "url": stream["url"]}
    for highway_id, cams in data["webcams"].items():
        motorway = motorways.get(highway_id)
        if motorway is None:
            print(f"no motorway {highway_id} in the catalog for cameras "
                  f"{[cam['id'] for cam in cams]}", file=sys.stderr)
            continue
        existing = {camera["id"]: camera for camera in motorway["cameras"]}
        motorway["cameras"] = [catalog_camera(cam, existing.get(str(cam["id"]), {})) for cam in cams]
    catalog["updatedAt"] = data["fetchedAt"]
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--lang", choices=["fr", "de", "en"], default="fr")
    parser.add_argument("-o", "--output", help="write to this file instead of stdout")
    parser.add_argument("--catalog", help="also update the cameras in this catalog.json")
    args = parser.parse_args()

    result = fetch(args.lang)
    if args.catalog:
        update_catalog(args.catalog, result)
    data = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(data)
    elif not args.catalog:
        sys.stdout.write(data)


if __name__ == "__main__":
    main()
