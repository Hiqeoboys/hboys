#!/usr/bin/env python3
"""Validator paket jalur: struktur GeoJSON, ID unik, batas koordinat, POI dekat jalur."""
import json
import math
import sys

LAT_RANGE = (-11.5, 6.5)     # perkiraan batas Indonesia
LON_RANGE = (94.5, 141.5)
POI_MAX_DISTANCE_M = 150     # POI jauh dari semua jalur dicurigai salah koordinat


def haversine(lat1, lon1, lat2, lon2):
    r = 6371008.8
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    dp = p2 - p1
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(h)))


def point_segment_m(p, a, b):
    """Jarak titik (lon,lat) ke segmen a-b dengan proyeksi lokal, meter."""
    m = 6371008.8 * math.pi / 180
    cos_lat = math.cos(math.radians(p[1]))
    def xy(q):
        return ((q[0] - p[0]) * cos_lat * m, (q[1] - p[1]) * m)
    ax, ay = xy(a)
    bx, by = xy(b)
    dx, dy = bx - ax, by - ay
    len2 = dx * dx + dy * dy
    t = 0.0 if len2 == 0 else max(0.0, min(1.0, (-ax * dx - ay * dy) / len2))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(cx, cy)


def check_coord(c, where, errors):
    if not (isinstance(c, list) and len(c) >= 2 and all(isinstance(v, (int, float)) for v in c[:2])):
        errors.append(f"{where}: koordinat tidak valid {c!r}")
        return False
    lon, lat = c[0], c[1]
    if not (LAT_RANGE[0] <= lat <= LAT_RANGE[1] and LON_RANGE[0] <= lon <= LON_RANGE[1]):
        errors.append(f"{where}: koordinat di luar Indonesia ({lat}, {lon}); lon/lat tertukar?")
        return False
    return True


def load(path, errors):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        errors.append(f"{path}: gagal dibaca ({e})")
        return []
    if data.get("type") != "FeatureCollection":
        errors.append(f"{path}: harus FeatureCollection")
        return []
    return data.get("features", [])


def main(argv):
    if len(argv) < 2:
        print("Pemakaian: validate_trails.py trails.geojson [poi.geojson]")
        return 2
    errors, warnings = [], []
    seen = set()

    lines = []
    for i, feat in enumerate(load(argv[1], errors)):
        props = feat.get("properties") or {}
        fid = props.get("id")
        where = f"{argv[1]}#{i}({fid})"
        if not fid:
            errors.append(f"{where}: properties.id wajib")
        elif fid in seen:
            errors.append(f"{where}: id ganda")
        seen.add(fid)
        geom = feat.get("geometry") or {}
        if geom.get("type") != "LineString":
            errors.append(f"{where}: jalur harus LineString")
            continue
        coords = geom.get("coordinates", [])
        if len(coords) < 2:
            errors.append(f"{where}: minimal 2 titik")
            continue
        if all(check_coord(c, where, errors) for c in coords):
            lines.append(coords)
            length = sum(haversine(a[1], a[0], b[1], b[0]) for a, b in zip(coords, coords[1:]))
            print(f"OK  {fid}: {len(coords)} titik, {length / 1000:.2f} km, verified={props.get('verified')}")
        if not props.get("verified"):
            warnings.append(f"{where}: belum terverifikasi (jangan tampilkan label 'terverifikasi')")

    if len(argv) > 2:
        for i, feat in enumerate(load(argv[2], errors)):
            props = feat.get("properties") or {}
            fid = props.get("id")
            where = f"{argv[2]}#{i}({fid})"
            if not fid:
                errors.append(f"{where}: properties.id wajib")
            elif fid in seen:
                errors.append(f"{where}: id ganda")
            seen.add(fid)
            geom = feat.get("geometry") or {}
            if geom.get("type") != "Point":
                errors.append(f"{where}: POI harus Point")
                continue
            c = geom.get("coordinates", [])
            if check_coord(c, where, errors) and lines:
                best = min(point_segment_m(c, a, b) for ln in lines for a, b in zip(ln, ln[1:]))
                if best > POI_MAX_DISTANCE_M:
                    warnings.append(f"{where}: {best:.0f} m dari jalur terdekat (> {POI_MAX_DISTANCE_M} m)")

    for w in warnings:
        print("PERINGATAN:", w)
    for e in errors:
        print("GALAT:", e)
    print(f"Selesai: {len(errors)} galat, {len(warnings)} peringatan")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
