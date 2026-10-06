#!/usr/bin/env python3
"""Fill the decision card page from a JSON file (trial; see session.md).

Usage: decision-card.py DATA.json OUT.html

DATA.json: {"title": "REPO: what waits", "id": "W1", "items": [ITEM, ...]}
ITEM keys:
  k   kind: "accept" (a change to accept), "brief" (a session to start),
      or "q" (a numbered question)
  id  what the answer line names: "#78", "1", "Q1"
  t   one-line title
  o   options as [value, label] pairs; required for "q". Each label reads
      as a complete answer on its own. A value of "other" asks for a note.
  d   the proposed value; required for "q" (defaults: accept, start)
  m   detail shown behind the title (optional)
  u   link (optional)
The answer line reads like: #78 accept, Q1 B, Q2 other "...", briefs: 1

Publish OUT.html with the Artifact tool. For the first card in a session,
run its quickstart action first, load the artifact-capabilities skill and
pass capabilities {"db": {}, "user": {}} and icon "checklist". Later cards
take a new id and republish the same OUT path, so the session keeps one
link. Not show_widget: it does not render on the phone (README.md).
"""

import html
import json
import pathlib
import re
import sys

KINDS = {"accept": ["accept", "change", "reject"], "brief": ["start", "later"], "q": None}


def check(data):
    if not isinstance(data, dict):
        sys.exit("DATA.json: an object with title, id and items is required")
    if not isinstance(data.get("title"), str) or not data["title"].strip():
        sys.exit("title: a non-empty string is required")
    if not isinstance(data.get("id"), str) or not data["id"].strip():
        sys.exit("id: a non-empty string is required, new for each wait")
    items = data.get("items")
    if not isinstance(items, list) or not items:
        sys.exit("items: a non-empty list is required")
    seen = set()
    for n, x in enumerate(items, 1):
        where = f"item {n}"
        if not isinstance(x, dict):
            sys.exit(f"{where}: an object is required")
        if x.get("k") not in KINDS:
            sys.exit(f"{where}: k must be one of {', '.join(KINDS)}")
        for key in ("id", "t"):
            if not isinstance(x.get(key), str) or not x[key].strip():
                sys.exit(f"{where}: {key} must be a non-empty string")
        if x["id"] in seen:
            sys.exit(f"{where}: id {x['id']} is used twice")
        seen.add(x["id"])
        opts = x.get("o")
        if opts is None:
            if KINDS[x["k"]] is None:
                sys.exit(f"{where}: a question needs options (o)")
            values = KINDS[x["k"]]
        else:
            if not isinstance(opts, list) or len(opts) < 2 or not all(
                isinstance(p, list) and len(p) == 2 and all(isinstance(s, str) and s for s in p)
                for p in opts
            ):
                sys.exit(f"{where}: o must be two or more [value, label] pairs")
            values = [p[0] for p in opts]
        if x["k"] == "q" and "d" not in x:
            sys.exit(f"{where}: a question needs a proposed value (d)")
        if "d" in x and x["d"] not in values:
            sys.exit(f"{where}: d {x['d']!r} is not one of {values}")
    return items


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    data = json.loads(pathlib.Path(sys.argv[1]).read_text())
    items = check(data)
    template = pathlib.Path(__file__).with_name("decision-card.html").read_text()

    def js(value):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")

    fill = {
        "CARD_TITLE_JSON": js(data["title"]),
        "CARD_ID_JSON": js(data["id"]),
        "CARD_DATA": js(items),
        "CARD_TITLE": html.escape(data["title"]),
    }
    page = re.sub("|".join(sorted(fill, key=len, reverse=True)), lambda m: fill[m.group()], template)
    pathlib.Path(sys.argv[2]).write_text(page)
    print(f"{sys.argv[2]}: card {data['id']}, {len(items)} items, {len(page)} bytes")


if __name__ == "__main__":
    main()
