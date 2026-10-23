#!/usr/bin/env python3
"""Fetch the highways, webcams and live streams listed on https://cita.lu.

Standard library only. Prints JSON to stdout, or writes it to a file:

    python3 fetch_cita.py                 # French labels, to stdout
    python3 fetch_cita.py --lang en -o cita.json

Output shape:

    {
      "source": "https://www.cita.lu",
      "language": "fr",
      "fetchedAt": "2026-10-23T14:30:00Z",
      "highways":    [{"id", "code", "name", "webcamPage", "liveStreamPage"}],
      "webcams":     {"<highway id>": [{"id", "location", "direction", "imageURL", "pageURL"}]},
      "liveStreams": {"<highway id>": {"url", "poster", "page"}}
    }

The site has no API, so this reads the HTML. If cita.lu changes its
markup, the patterns below are the only things to update.
"""

import argparse
import html
import json
import re
import sys
import urllib.request
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


def get(path):
    request = urllib.request.Request(BASE + path, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace")


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


def fetch(lang):
    # The first highway's pages carry the menu listing every highway.
    first_webcam_path = f"/{lang}/webcam/a1.html"
    first_stream_path = f"/{lang}/live-stream/a1.html"
    webcam_menu = nav_links(get(first_webcam_path), lang, "webcam")
    stream_menu = nav_links(get(first_stream_path), lang, "live-stream")

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
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--lang", choices=["fr", "de", "en"], default="fr")
    parser.add_argument("-o", "--output", help="write to this file instead of stdout")
    args = parser.parse_args()

    data = json.dumps(fetch(args.lang), ensure_ascii=False, indent=2) + "\n"
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(data)
    else:
        sys.stdout.write(data)


if __name__ == "__main__":
    main()
