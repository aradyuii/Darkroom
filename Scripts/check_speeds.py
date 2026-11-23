#!/usr/bin/env python3
"""Flag films whose stated speed the DX database contradicts.

Each library film is matched to DX rows on its name together with its ISO, so
"Gold 200" only meets rows that say Gold 200. A flag is raised only when such a
row states a speed, in ISO or ASA form, that is not the library's, which keeps
aerial and internal codes out of the result. Nothing is changed here: a flag is
a reason to check the source, not a finding.

    check_speeds.py
"""

import csv
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "Darkroom", "Resources", "Library")

SPEED = re.compile(
    r"(?:\b(?:iso|asa)\s*(\d{2,4})\b|\b(\d{2,4})\s*(?:iso|asa)\b)",
    re.IGNORECASE,
)


def norm(text):
    return re.sub(r"[^a-z0-9]", "", (text or "").lower())


def load_films():
    films = []
    for path in sorted(glob.glob(os.path.join(LIB, "library*.json"))):
        with open(path, encoding="utf-8") as handle:
            document = json.load(handle)
        films.extend(document.get("films", []) or [])
    return films


def dx_names():
    path = os.path.join(LIB, "dx_database.csv")
    with open(path, encoding="utf-8", errors="replace") as handle:
        return [row.get("Name") or "" for row in csv.DictReader(handle, delimiter=";")]


def stated_speeds(text):
    return [int(m.group(1) or m.group(2)) for m in SPEED.finditer(text)]


def main():
    indexed = [(norm(name), name) for name in dx_names()]
    flagged = []
    confirmed = 0
    unmatched = 0

    for film in load_films():
        iso = film.get("iso")
        name = film.get("name") or ""
        if len(norm(name)) < 3 or not iso:
            unmatched += 1
            continue

        key = norm(name) + str(iso)
        candidates = [raw for normalised, raw in indexed if key in normalised]
        if not candidates:
            unmatched += 1
            continue

        contradicting = []
        agrees = False
        for raw in candidates:
            speeds = stated_speeds(raw)
            if not speeds:
                continue
            if iso in speeds:
                agrees = True
            else:
                contradicting.append(raw)

        if agrees:
            confirmed += 1
        elif contradicting:
            flagged.append((film.get("key"), iso, name, contradicting[:3]))
        else:
            unmatched += 1

    for key, iso, name, rows in flagged:
        print(f"{key}\tlibrary ISO {iso}\t{name}")
        for row in rows:
            print(f"    DX: {row}")

    print(
        f"\nflagged {len(flagged)}; confirmed by DX {confirmed}; "
        f"no DX row carrying name and speed {unmatched}"
    )


if __name__ == "__main__":
    main()
