#!/usr/bin/env python3
"""Audit the bundled film library against itself and against the DX database.

Nothing here edits anything: it reports. The point is to catch the class of
error that cannot be seen by reading one record at a time -- a speed that
contradicts a number in the record's own text, an origin that points at a film
that does not exist, a film the expiry model cannot place.

Usage:
    audit_library.py summary     counts, contradictions, model placement
    audit_library.py films       the compact film table
    audit_library.py dx          films that appear in the DX database, with both
                                 speeds side by side
"""

import csv
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "Darkroom", "Resources", "Library")


def load():
    films, developers, times, sources, broken = [], [], [], [], []
    for path in sorted(glob.glob(os.path.join(LIB, "library*.json"))):
        name = os.path.basename(path)
        try:
            with open(path, encoding="utf-8") as handle:
                document = json.load(handle)
        except Exception as error:  # noqa: BLE001 - report, never raise
            broken.append((name, str(error)))
            continue
        for film in document.get("films", []) or []:
            films.append((film, name))
        for developer in document.get("developers", []) or []:
            developers.append((developer, name))
        for entry in document.get("times", []) or []:
            times.append((entry, name))
        for source in document.get("sources", []) or []:
            sources.append((source, name))
    return films, developers, times, sources, broken


def norm(text):
    return re.sub(r"[^a-z0-9]", "", (text or "").lower())


def number_after(text, pattern=r"\b(?:iso|asa)\s*(\d{2,5})"):
    return [int(match) for match in re.findall(pattern, (text or "").lower())]


# The rule set in ExpiryParameters.swift, mirrored so the audit can report where
# every film lands in the model rather than only checking that it decodes.
MODERN = ["t-max", "tmax", "delta", "acros", "pan f", "retro 80", "p30", "cms 20", "silvermax", "ortho"]
PROFESSIONAL = [
    "portra", "ektar", "pro 160", "pro 400", "pro 800", "400h", "reala", "vericolor",
    "vps", "vpl", "nps", "nph", "npz", "ultra color",
]


def rule_group(film):
    name = (film.get("name") or "").lower()
    process = film.get("process")
    iso = film.get("iso") or 0
    if process == "colourReversal":
        return "slide"
    if process == "cinemaNegative":
        return "cineECN2"
    if process == "colourNegative":
        if any(marker in name for marker in PROFESSIONAL):
            return "professionalColourNegative"
        return "consumerColourNegative"
    if iso >= 400:
        return "fastBW"
    if iso < 200 and any(marker in name for marker in MODERN):
        return "slowModernBW"
    return "classicBW"


def base_material(film):
    for entry in film.get("characteristics") or []:
        if (entry.get("label") or "").lower() == "base":
            text = (entry.get("value") or "").lower()
            if "paper" in text:
                return "paper"
            if "polyester" in text or "estar" in text or "pet " in text:
                return "polyester"
            if "acetate" in text:
                return "acetate"
    formats = film.get("formats") or []
    if "sheet4x5" in formats or "sheet8x10" in formats:
        return "polyester?"
    if "size135" in formats or "size120" in formats:
        return "acetate?"
    return "unknown"


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "summary"
    films, developers, times, sources, broken = load()

    if mode == "films":
        for film, origin in films:
            print("\t".join([
                film.get("key", "?"),
                film.get("manufacturer", "?"),
                film.get("name", "?"),
                str(film.get("iso", "?")),
                film.get("process", "?"),
                ",".join(film.get("formats") or []),
                film.get("status", "?"),
                (film.get("generationLabel") or film.get("generation") or ""),
                origin,
            ]))
        return

    if mode == "dx":
        rows = []
        with open(os.path.join(LIB, "dx_database.csv"), encoding="utf-8", errors="replace") as handle:
            for row in csv.DictReader(handle, delimiter=";"):
                rows.append(row)
        print("library key\tlibrary iso\tDX name\tDX speed")
        disagreements = 0
        matched = 0
        for film, _ in films:
            iso = film.get("iso") or 0
            wanted = norm(film.get("name"))
            if len(wanted) < 4:
                continue
            seen = set()
            for row in rows:
                name = row.get("Name") or ""
                candidate = norm(name)
                if wanted not in candidate:
                    continue
                speeds = number_after(name)
                if not speeds:
                    # "Gold 200" carries its speed with no ISO in front of it.
                    trailing = re.findall(r"(\d{2,4})\s*$", name)
                    speeds = [int(value) for value in trailing]
                for speed in speeds:
                    if speed < 20 or speed > 3200:
                        continue
                    if speed == iso:
                        matched += 1
                    else:
                        key = (film.get("key"), name)
                        if key in seen:
                            continue
                        seen.add(key)
                        print(f"MISMATCH\t{film.get('key')}\t{iso}\t{name}\t{speed}")
                        disagreements += 1
                        break
        print(f"\nagreements: {matched}   disagreements: {disagreements}")
        return

    # summary
    keys = {}
    stable = {}
    for film, origin in films:
        keys.setdefault(film.get("key"), []).append(origin)
        stable.setdefault(
            "|".join([
                (film.get("manufacturer") or "").lower(),
                (film.get("name") or "").lower(),
                str(film.get("iso")),
                (film.get("generation") or "").lower(),
            ]),
            [],
        ).append(film.get("key"))

    print(f"documents decoded: {len(glob.glob(os.path.join(LIB, 'library*.json')))}")
    print(f"films: {len(films)}  developers: {len(developers)}  times: {len(times)}  sources: {len(sources)}")
    if broken:
        print("UNDECODABLE:")
        for name, error in broken:
            print(f"  {name}: {error}")

    duplicates = {key: where for key, where in keys.items() if len(where) > 1}
    print(f"duplicate film keys: {len(duplicates)}")
    for key, where in sorted(duplicates.items())[:20]:
        print(f"  {key} in {where}")

    print("self-contradictions (a speed in the record's own text that disagrees with its iso):")
    contradictions = 0
    for film, origin in films:
        iso = film.get("iso") or 0
        texts = [film.get("name"), film.get("generationLabel")]
        for entry in film.get("characteristics") or []:
            if "speed" in (entry.get("label") or "").lower():
                texts.append(entry.get("value"))
        for text in texts:
            # A record may name the wrong speed in order to correct it ("Not ISO
            # 25"). Those are negations, not claims, and are skipped.
            if re.search(r"\bnot\s+(?:iso|asa)\s*\d", (text or ""), re.IGNORECASE):
                continue
            for speed in number_after(text):
                if speed >= 20 and speed != iso and speed not in (iso // 3, iso * 3, iso // 2, iso * 2):
                    print(f"  {film.get('key')}: iso={iso} but text says {speed} ({text!r}) in {origin}")
                    contradictions += 1
                    break
    print(f"  total: {contradictions}")

    print("origin links:")
    missing = 0
    for film, origin in films:
        source = (film.get("origin") or {})
        target = source.get("stockFilm")
        if target and target not in keys:
            print(f"  {film.get('key')}: origin.stockFilm {target!r} is not a film in the library")
            missing += 1
        if source.get("kind") in ("respool", "rebrand", "converted") and not source.get("stock"):
            print(f"  {film.get('key')}: {source.get('kind')} with no stock named")
            missing += 1
    print(f"  total: {missing}")

    overrides_path = os.path.join(LIB, "expiry-overrides.json")
    overrides = []
    if os.path.exists(overrides_path):
        with open(overrides_path, encoding="utf-8") as handle:
            overrides = json.load(handle).get("films", [])
    override_keys = {entry.get("filmKey") for entry in overrides}
    print(f"expiry overrides: {len(overrides)}; keys not in the library:")
    orphaned = sorted(key for key in override_keys if key not in keys)
    for key in orphaned:
        print(f"  {key}")
    print(f"  total: {len(orphaned)}")

    print("model placement:")
    placement = {}
    for film, _ in films:
        curated = film.get("key") in override_keys
        group = rule_group(film)
        placement.setdefault((group, curated), 0)
        placement[(group, curated)] += 1
    for (group, curated), count in sorted(placement.items()):
        print(f"  {group}{' (curated)' if curated else ''}: {count}")

    print("base material:")
    bases = {}
    for film, _ in films:
        base = base_material(film)
        bases[base] = bases.get(base, 0) + 1
    for base, count in sorted(bases.items()):
        print(f"  {base}: {count}")

    print("formats in use:")
    formats = set()
    for film, _ in films:
        for fmt in film.get("formats") or []:
            formats.add(fmt)
    print("  " + ", ".join(sorted(formats)))


if __name__ == "__main__":
    main()
