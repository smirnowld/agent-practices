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
directory fails; an unrecognised value fails and reports what was found. In
`superseded by ADR-NNNN`, NNNN must be an existing ADR other than the file
itself. A near-miss such as `**Status**: accepted` fails naming the expected
form.

ADR numbers run 1..N across docs/adr/ and docs/adr/archive/ together: every
duplicate and every gap fails.

docs/adr/README.md must list every active ADR (a Markdown table row linking
its file), must not list an archived ADR, and every link it has to an ADR
file must resolve; a link may carry a `#anchor` or a title, and its target may
be wrapped in angle brackets. Each row's Status cell (the column headed
Status; the last cell when the table has no such header) must equal the ADR's
status (case-insensitive, emphasis and backticks ignored). A row still holding
the template placeholder link `[<NNNN>](<NNNN-slug>.md)` fails. Links in prose or list items outside
table rows are ignored, except that an ADR listed only that way is reported
with the expected table-row form; lines inside ``` or ~~~ code fences are
ignored.

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
NEAR_STATUS_RE = re.compile(r"^[*_]*status[*_]*\s*:\s*[*_]*\s*(.*?)\s*$", re.IGNORECASE)
PLACEHOLDER_RE = re.compile(r"\[<NNNN>\]|\(<NNNN[->]")
SEPARATOR_CELL_RE = re.compile(r"^:?-+:?$")
EMPHASIS_RE = re.compile(r"[*_`]")
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


def check_status(path, num, label, rel, failures, superseded):
    lines = path.read_text().splitlines()
    status_line = None
    status_value = None
    near_miss = None
    for n, line in enumerate(lines, 1):
        m = STATUS_RE.match(line)
        if m:
            status_line = n
            status_value = m.group(1)
            break
        if near_miss is None and NEAR_STATUS_RE.match(line):
            near_miss = (n, line.strip())
    if status_value is None:
        hint = ""
        if near_miss:
            hint = f'; line {near_miss[0]} reads "{near_miss[1]}"; write **Status:** VALUE'
        failures.append(f"{rel}: missing **Status:** line{hint}")
        return None
    if not is_recognised(status_value):
        failures.append(f"{rel}:{status_line}: status outside the set: {status_value}")
        return None
    m = SUPERSEDED_RE.match(status_value)
    if m:
        superseded.append((rel, status_line, num, int(m.group(1))))
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


def check_superseded(superseded, numbered, failures):
    existing = {num for _, num in numbered}
    for rel, line, own, target in superseded:
        if target == own:
            failures.append(
                f"{rel}:{line}: superseded by itself (ADR-{target:04d}); name the ADR that replaces it"
            )
        elif target not in existing:
            failures.append(
                f"{rel}:{line}: superseded by ADR-{target:04d}, which does not exist; "
                "name an existing ADR other than this one"
            )


def split_row(stripped):
    return [c.strip() for c in re.split(r"(?<!\\)\|", stripped.strip().strip("|"))]


def link_target(target):
    target = target.strip()
    if target.startswith("<"):
        return target[1:].split(">")[0].split("#")[0]
    return target.split()[0].split("#")[0] if target.split() else ""


def link_basename(target):
    clean = link_target(target)
    if clean.startswith("./"):
        clean = clean[2:]
    return clean.rsplit("/", 1)[-1]


def check_index(root, adr_dir, active_names, archive_names, statuses, failures):
    readme = adr_dir / "README.md"
    rel_readme = readme.relative_to(root)
    if not readme.is_file():
        failures.append(f"{rel_readme}: missing index")
        return
    listed_active = set()
    off_table = {}
    fence = None
    prev_cells = None
    status_col = None
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
        is_row = stripped.startswith("|")
        if not is_row:
            prev_cells = status_col = None
            for target in LINK_RE.findall(line):
                basename = link_basename(target)
                if basename in active_names:
                    off_table.setdefault(basename, n)
            continue
        cells = split_row(stripped)
        if all(SEPARATOR_CELL_RE.match(c) for c in cells):
            status_col = None
            if prev_cells:
                heads = [EMPHASIS_RE.sub("", c).strip().lower() for c in prev_cells]
                status_col = heads.index("status") if "status" in heads else None
            prev_cells = None
            continue
        prev_cells = cells
        col = -1 if status_col is None else status_col
        raw_status = cells[col] if -len(cells) <= col < len(cells) else ""
        row_status = EMPHASIS_RE.sub("", raw_status).strip().lower()
        if PLACEHOLDER_RE.search(line):
            failures.append(
                f"{rel_readme}:{n}: placeholder row: replace <NNNN> and the rest with the ADR's "
                "number, title and status, or delete the row"
            )
            continue
        for target in LINK_RE.findall(line):
            basename = link_basename(target)
            clean = link_target(target)
            if clean.startswith("./"):
                clean = clean[2:]
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
                        f"{rel_readme}:{n}: lists {basename} as {raw_status or 'blank'}, "
                        f"but its Status line says {expected}"
                    )
    for name in sorted(active_names - listed_active):
        if name in off_table:
            failures.append(
                f"{rel_readme}:{off_table[name]}: does not list {name} in a table row; "
                f"expected | [NNNN]({name}) | DECISION | STATUS |"
            )
        else:
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
    superseded = []

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
            status = check_status(path, int(m.group(1)), label, rel, failures, superseded)
            if status:
                statuses[path.name] = status

    check_numbering(numbered, root, failures)
    check_superseded(superseded, numbered, failures)
    check_index(root, adr_dir, active_names, archive_names, statuses, failures)

    if failures:
        for f in failures:
            print(f)
        return 1
    print("adrs ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
