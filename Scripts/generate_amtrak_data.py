#!/usr/bin/env python3
"""
generate_amtrak_data.py

Turns Amtrak's free, keyless GTFS feed into the three slim JSON resources the app
bundles for its US-train features — the build-time counterpart to the Indian
`StationCoordinates.json`:

  • AmtrakStations.json  code -> {name, lat, lon, tz}         (station coordinates)
  • AmtrakSchedule.json  trainNumber -> [variant, ...]        (autofill timetable)
  • AmtrakShapes.json    shapeId -> [[lat, lon], ...]         (real route geometry)

The feed carries a full forward timetable (calendar.txt runs ~a year out), so —
unlike a live-tracking API — a future travel date fills correctly, matching how
the Indian erail integration behaves. Re-run this to refresh the snapshot.

Usage:
    python3 Scripts/generate_amtrak_data.py

No dependencies beyond the standard library.
"""

import csv
import io
import json
import math
import os
import sys
import urllib.request
import zipfile

GTFS_URL = "https://content.amtrak.com/content/gtfs/GTFS.zip"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Runnit iOS", "Services")

# Drop a shape point when it's within this many metres of the last one kept, so a
# transcontinental polyline ships as a few thousand points, not hundreds of
# thousands. Endpoints and stop-adjacent detail survive; the line stays faithful.
SHAPE_MIN_SPACING_M = 1500.0


def load_zip(source):
    # A local path (e.g. a curl-fetched copy) may be passed as argv[1] to sidestep
    # Python's SSL trust store; otherwise fetch straight from Amtrak.
    if os.path.exists(source):
        print(f"Reading {source} …", file=sys.stderr)
        return zipfile.ZipFile(source)
    print(f"Downloading {source} …", file=sys.stderr)
    data = urllib.request.urlopen(source, timeout=120).read()
    print(f"  {len(data) / 1_048_576:.1f} MB", file=sys.stderr)
    return zipfile.ZipFile(io.BytesIO(data))


def read_csv(zf, name):
    with zf.open(name) as f:
        text = io.TextIOWrapper(f, encoding="utf-8-sig")
        return list(csv.DictReader(text))


def haversine_m(a, b):
    (lat1, lon1), (lat2, lon2) = a, b
    r = 6_371_000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def build_stations(zf):
    stations = {}
    for row in read_csv(zf, "stops.txt"):
        code = (row.get("stop_id") or "").strip().upper()
        try:
            lat = float(row["stop_lat"])
            lon = float(row["stop_lon"])
        except (KeyError, ValueError):
            continue
        if not code or (lat == 0 and lon == 0):
            continue
        name = (row.get("stop_name") or "").strip()
        # The feed suffixes most names with " Amtrak Station"; trim it so the pin
        # reads like a place, not a database row.
        for suffix in (" Amtrak Station", " Station"):
            if name.endswith(suffix):
                name = name[: -len(suffix)]
                break
        stations[code] = {
            "name": name,
            "lat": round(lat, 6),
            "lon": round(lon, 6),
            "tz": (row.get("stop_timezone") or "").strip(),
        }
    return stations


def gtfs_days_to_sunday_first(cal):
    """GTFS calendar is Monday-first; the app's running-days mask is Sunday-first
    (index = Swift weekday - 1), matching the Indian erail convention. Return a
    7-char '1'/'0' string, Sunday at index 0."""
    order = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    return "".join("1" if (cal.get(day) or "0").strip() == "1" else "0" for day in order)


def build_schedule_and_shapes(zf):
    routes = {r["route_id"]: r for r in read_csv(zf, "routes.txt")}
    calendars = {c["service_id"]: c for c in read_csv(zf, "calendar.txt")}

    # trip_id -> ordered [(stop_seq, code, arr, dep)]
    stop_times = {}
    for row in read_csv(zf, "stop_times.txt"):
        tid = row["trip_id"]
        try:
            seq = int(row["stop_sequence"])
        except (KeyError, ValueError):
            continue
        stop_times.setdefault(tid, []).append(
            (seq, (row.get("stop_id") or "").strip().upper(),
             (row.get("arrival_time") or "").strip(),
             (row.get("departure_time") or "").strip())
        )
    for tid in stop_times:
        stop_times[tid].sort(key=lambda x: x[0])

    # Group trips by train number (trip_short_name). For each number, keep the
    # trip with the most stops as the canonical variant (the full route), OR the
    # running-days masks across every service that number runs under, and widen
    # the validity window to their union.
    by_number = {}
    for t in read_csv(zf, "trips.txt"):
        number = (t.get("trip_short_name") or "").strip()
        if not number:
            continue
        # Keep rail only. The feed also carries Amtrak Thruway *bus* connections
        # (GTFS route_type 3); this is a train feature, so those are dropped —
        # otherwise a coach's number would autofill as if it were a train.
        if (routes.get(t["route_id"], {}).get("route_type") or "").strip() != "2":
            continue
        by_number.setdefault(number, []).append(t)

    schedule = {}
    used_shape_ids = set()

    for number, trips in by_number.items():
        canonical = None
        canonical_stops = []
        days_mask = 0
        start = None
        end = None
        route_name = ""

        for t in trips:
            cal = calendars.get(t["service_id"])
            if cal:
                mask = gtfs_days_to_sunday_first(cal)
                days_mask |= int(mask, 2)
                s, e = cal.get("start_date"), cal.get("end_date")
                if s and (start is None or s < start):
                    start = s
                if e and (end is None or e > end):
                    end = e
            stops = stop_times.get(t["trip_id"], [])
            if len(stops) > len(canonical_stops):
                canonical = t
                canonical_stops = stops
                route_name = (routes.get(t["route_id"], {}).get("route_long_name") or "").strip()

        if canonical is None or len(canonical_stops) < 2:
            continue

        shape_id = (canonical.get("shape_id") or "").strip()
        if shape_id:
            used_shape_ids.add(shape_id)

        schedule[number] = [{
            "name": route_name,
            "headsign": (canonical.get("trip_headsign") or "").strip(),
            "shapeId": shape_id,
            "days": format(days_mask, "07b"),
            "start": start or "",
            "end": end or "",
            "stops": [
                {"code": code, "arr": arr, "dep": dep}
                for (_seq, code, arr, dep) in canonical_stops
            ],
        }]

    shapes = build_shapes(zf, used_shape_ids)
    return schedule, shapes


def build_shapes(zf, wanted):
    raw = {}
    for row in read_csv(zf, "shapes.txt"):
        sid = (row.get("shape_id") or "").strip()
        if sid not in wanted:
            continue
        try:
            lat, lon = float(row["shape_pt_lat"]), float(row["shape_pt_lon"])
            seq = int(row["shape_pt_sequence"])
        except (KeyError, ValueError):
            continue
        raw.setdefault(sid, []).append((seq, lat, lon))

    shapes = {}
    for sid, pts in raw.items():
        pts.sort(key=lambda x: x[0])
        kept = []
        for _seq, lat, lon in pts:
            p = (lat, lon)
            if not kept or haversine_m(kept[-1], p) >= SHAPE_MIN_SPACING_M:
                kept.append(p)
        # Always keep the true endpoint so the line reaches the last station.
        last = (pts[-1][1], pts[-1][2])
        if kept and kept[-1] != last:
            kept.append(last)
        if len(kept) >= 2:
            shapes[sid] = [[round(lat, 5), round(lon, 5)] for lat, lon in kept]
    return shapes


def write_json(name, obj):
    path = os.path.join(OUT_DIR, name)
    with open(path, "w") as f:
        json.dump(obj, f, separators=(",", ":"), sort_keys=True)
    print(f"  wrote {name}: {os.path.getsize(path) / 1024:.0f} KB", file=sys.stderr)


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else GTFS_URL
    zf = load_zip(source)
    stations = build_stations(zf)
    schedule, shapes = build_schedule_and_shapes(zf)

    print(f"stations: {len(stations)} | trains: {len(schedule)} | shapes: {len(shapes)}",
          file=sys.stderr)
    write_json("AmtrakStations.json", stations)
    write_json("AmtrakSchedule.json", schedule)
    write_json("AmtrakShapes.json", shapes)


if __name__ == "__main__":
    main()
