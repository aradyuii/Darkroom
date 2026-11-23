#!/usr/bin/env python3
"""Downgrade provenance that names a document which cannot support the claim.

The Massive Dev Chart publishes development times. It does not publish latitude,
grain, grain structure, contrast, palette, look or any other visual property, so
a record that cites it for one of those cites a document that does not say it.
The published film lists on Wikipedia give dates, speeds, formats and rebrand
relationships; they give neither visual characteristics nor development times.

Each such citation is rewritten to `unverified`, which is what it is. The claim
stays in place for the verification queue. Citations the document does support
are not touched.

The rewrite is line by line, so each file keeps its layout and the diff shows
exactly which citations changed. Every file is parsed before it is written.

    fix_provenance.py            report only
    fix_provenance.py --write    rewrite the files

Run this where the project lives. It was written and exercised on a build
machine, which is not where these files are kept: the reports above reflect the
bundled JSON as it stands only when it is run against this checkout. As
committed, the repository's own JSON has NOT had this pass applied.
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "Darkroom", "Resources", "Library")

CHART = "massive-dev-chart"
WIKI = "wikipedia-photographic-films"

FACT_KEYS = ('"latitude"', '"grain"', '"grainStructure"', '"contrast"', '"reciprocity"')

CITATION = re.compile(
    r'\{\s*"kind":\s*"community",\s*"source":\s*"(massive-dev-chart|wikipedia-photographic-films)"'
    r'(?:,\s*"note":\s*"[^"]*")?\s*\}'
)


def is_time_line(line):
    return '"film":' in line and '"seconds"' in line


def is_fact_line(line):
    return line.lstrip().startswith(FACT_KEYS) or '"label":' in line


def should_downgrade(source, line):
    if is_time_line(line):
        # The chart is the right source for a development time; Wikipedia is not.
        return source == WIKI
    if source == CHART:
        return True
    # Wikipedia supports dates, speeds, formats and origins, not visual facts.
    return is_fact_line(line)


def rewrite_line(line):
    count = 0

    def replace(match):
        nonlocal count
        if should_downgrade(match.group(1), line):
            count += 1
            return '{ "kind": "unverified" }'
        return match.group(0)

    return CITATION.sub(replace, line), count


def main():
    write = "--write" in sys.argv
    grand = 0
    for path in sorted(glob.glob(os.path.join(LIB, "library*.json"))):
        name = os.path.basename(path)
        # Developer records carry chemistry facts, not film facts. They are out
        # of scope for this rule and are left exactly as they are.
        if name.startswith("library-developers"):
            continue

        with open(path, encoding="utf-8") as handle:
            original = handle.read()

        lines = []
        count = 0
        for line in original.split("\n"):
            new, changed = rewrite_line(line)
            lines.append(new)
            count += changed

        if not count:
            continue

        updated = "\n".join(lines)
        json.loads(updated)  # refuse to write anything that no longer parses
        print(f"{name}: {count}")
        grand += count
        if write:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(updated)

    print(f"total citations {'rewritten' if write else 'to rewrite'}: {grand}{'' if write else ' (report only)'}")


if __name__ == "__main__":
    main()
