#!/usr/bin/env python3
"""Check a project's ADR records (baseline C5).

Usage: check-adrs.py [DIR]   (default: current directory)

ADR files live at docs/adr/NNNN-kebab-slug.md (in force or proposed) and
docs/adr/archive/NNNN-kebab-slug.md (superseded or rejected). docs/adr/README.md
is the index, not an ADR. A 0000-*.md file in either directory is ignored (a
project may keep a template copy there). Any other .md file in those two
directories whose name is not NNNN-kebab-case.md fails.

Each ADR must carry a `**Status:** VALUE` line. In docs/adr/ the value must be
`proposed` or `accepted` (case-insensitive); in docs/adr/archive/ it must be
`rejected` or `superseded by ADR-NNNN`. A recognised status in the wrong
directory fails; an unrecognised value fails and reports what was found.

ADR numbers run 1..N across docs/adr/ and docs/adr/archive/ together: every
duplicate and every gap fails.

docs/adr/README.md must list every active ADR (a Markdown table row linking
its file), must not list an archived ADR, and every link it has to an ADR
file must resolve; a link may carry a `#anchor` or a title. Each row's last
cell must equal the ADR's status (case-insensitive). Links in prose outside
table rows are ignored, as are lines inside ``` or ~~~ code fences.

Prints `path:line: reason` for each failure (path relative to DIR; line is
omitted where there is no specific line). Exits 1 if there are any failures,
0 and `adrs ok` when clean. Exits 2 if DIR is not a directory or has no
docs/adr/ directory, so a mistyped path never passes.
"""
import fnmatch
import pathlib
import re
import sys

NAME_RE = re.compile(r"^(\d{4})-[a-z0-9]+(?:-[a-z0-9]+)*\.md$")
STATUS_RE = re.compile(r"^\*\*Status:\*\*\s*(.*?)\s*$")
SUPERSEDED_RE = re.compile(r"^superseded by adr-(\d{4})$", re.IGNORECASE)
LINK_RE = re.compile(r"\]\(([^)]+)\)")
ACTIVE_STATUSES = {"proposed", "accepted"}
ARCHIVE_STATUSES = {"rejected"}


def is_recognised(value):
    v = value.lower()
    return v in ACTIVE_STATUSES or v in ARCHIVE_STATUSES or SUPERSEDED_RE.match(v)


def belongs_in_archive(value):
    v = value.lower()
    return v in ARCHIVE_STATUSES or SUPERSEDED_RE.match(v)


def belongs_in_active(value):
    return value.lower() in ACTIVE_STATUSES


def adr_files(dir_path):
    if not dir_path.is_dir():
        return []
    found = []
    for p in sorted(dir_path.glob("*.md")):
        if p.name == "README.md":
            continue
        if fnmatch.fnmatch(p.name, "0000-*.md"):
            continue
        found.append(p)
    return found


def check_status(path, label, rel, failures):
    lines = path.read_text().splitlines()
    status_line = None
    status_value = None
    for n, line in enumerate(lines, 1):
        m = STATUS_RE.match(line)
        if m:
            status_line = n
            status_value = m.group(1)
            break
    if status_value is None:
        failures.append(f"{rel}: missing **Status:** line")
        return None
    if not is_recognised(status_value):
        failures.append(f"{rel}:{status_line}: status outside the set: {status_value}")
        return None
    if label == "active" and belongs_in_archive(status_value):
        failures.append(
            f"{rel}:{status_line}: superseded/rejected status in docs/adr/; move to docs/adr/archive/"
        )
    elif label == "archive" and belongs_in_active(status_value):
        failures.append(
            f"{rel}:{status_line}: proposed/accepted status in docs/adr/archive/"
        )
    return status_value.lower() if label == "active" and belongs_in_active(status_value) else None


def check_numbering(numbered, root, failures):
    by_number = {}
    for path, num in numbered:
        by_number.setdefault(num, []).append(path)
    if not by_number:
        return
    for num in sorted(k for k, v in by_number.items() if len(v) > 1):
        names = ", ".join(str(p.relative_to(root)) for p in sorted(by_number[num]))
        failures.append(f"docs/adr: duplicate ADR-{num:04d}: {names}")
    highest = max(by_number)
    for num in range(1, highest + 1):
        if num not in by_number:
            failures.append(f"docs/adr: ADR-{num:04d} missing: gap in numbering")


def check_index(root, adr_dir, active_names, archive_names, statuses, failures):
    readme = adr_dir / "README.md"
    rel_readme = readme.relative_to(root)
    if not readme.is_file():
        failures.append(f"{rel_readme}: missing index")
        return
    listed_active = set()
    fence = None
    for n, line in enumerate(readme.read_text().splitlines(), 1):
        stripped = line.lstrip()
        marker = stripped[:3]
        if marker in ("```", "~~~"):
            if fence is None:
                fence = marker
            elif fence == marker:
                fence = None
            continue
        if fence is not None:
            continue
        if not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.strip().strip("|").split("|")]
        row_status = cells[-1].lower() if cells else ""
        for target in LINK_RE.findall(line):
            clean = target.split()[0].split("#")[0] if target.split() else ""
            if clean.startswith("./"):
                clean = clean[2:]
            basename = clean.rsplit("/", 1)[-1]
            if not NAME_RE.match(basename):
                continue
            is_archive_link = clean.startswith("archive/") or (
                basename in archive_names and basename not in active_names
            )
            if is_archive_link:
                failures.append(
                    f"{rel_readme}:{n}: lists archived {basename}; archived ADRs leave the index"
                )
            elif basename not in active_names:
                failures.append(
                    f"{rel_readme}:{n}: lists {basename}, which does not exist"
                )
            else:
                listed_active.add(basename)
                expected = statuses.get(basename)
                if expected and row_status != expected:
                    failures.append(
                        f"{rel_readme}:{n}: lists {basename} as {cells[-1] or 'blank'}, "
                        f"but its Status line says {expected}"
                    )
    for name in sorted(active_names - listed_active):
        failures.append(f"{rel_readme}: does not list {name}")


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 2
    adr_dir = root / "docs" / "adr"
    if not adr_dir.is_dir():
        print(f"error: no docs/adr directory under {root}; pass the project root", file=sys.stderr)
        return 2
    archive_dir = adr_dir / "archive"

    failures = []
    numbered = []
    active_names = set()
    archive_names = set()
    statuses = {}

    for label, dir_path, names in (
        ("active", adr_dir, active_names),
        ("archive", archive_dir, archive_names),
    ):
        for path in adr_files(dir_path):
            rel = path.relative_to(root)
            m = NAME_RE.match(path.name)
            if not m:
                failures.append(f"{rel}: file name must be NNNN-kebab-case.md")
                continue
            names.add(path.name)
            numbered.append((path, int(m.group(1))))
            status = check_status(path, label, rel, failures)
            if status:
                statuses[path.name] = status

    check_numbering(numbered, root, failures)
    check_index(root, adr_dir, active_names, archive_names, statuses, failures)

    if failures:
        for f in failures:
            print(f)
        return 1
    print("adrs ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
