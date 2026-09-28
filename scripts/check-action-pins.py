#!/usr/bin/env python3
"""Check that GitHub Actions references are pinned (baseline C4).

Usage: check-action-pins.py [DIR]   (default: current directory)

Reads every .yml and .yaml file under DIR/.github and every action.yml or
action.yaml in DIR: files git tracks or would track, or every file outside
.git and node_modules when DIR is not a git work tree. Each `uses:`, first-party actions included, must be pinned
to a full lowercase 40-character commit SHA and carry a comment ending in the
version, `# vX.Y.Z`; Dependabot only rewrites comments that end with the
version. Local actions (`./...`) are exempt; `docker://` images must be pinned
to a `@sha256:` digest.

Fails closed: a line with a `uses` key in any other form (flow mapping, quoted
key, value on the next line, anchor) is reported, not skipped.

Prints `path:line: reason` for each failure and exits 1 if there are any.
"""
import pathlib
import re
import subprocess
import sys

USES = re.compile(r"^\s*(?:-\s+)?uses:\s*(['\"]?)([^'\"\s]+)\1(?:\s+(#.*))?\s*$")
SHA_REF = re.compile(r"^[\w.-]+/[\w./-]+@[0-9a-f]{40}$")
VERSION_COMMENT = re.compile(r"#.*\bv\d+\.\d+\.\d+\s*$")
DIGEST = re.compile(r"@sha256:[0-9a-f]{64}$")
ANY_USES = re.compile(r"(?:^|[\s{,])['\"]?uses['\"]?\s*:")
UNRECOGNISED = "unrecognised uses: form; write `- uses: OWNER/ACTION@SHA # vX.Y.Z` on one line"
SKIP_DIRS = {".git", "node_modules"}


def check_line(ref, comment):
    if ref.startswith("./"):
        return None
    if ref.startswith("docker://"):
        return None if DIGEST.search(ref) else "docker image not pinned to a sha256 digest"
    if not SHA_REF.match(ref):
        return f"{ref} not pinned to a full lowercase 40-character commit SHA"
    if not comment or not VERSION_COMMENT.search(comment):
        return f"{ref} needs a comment ending in the version (# vX.Y.Z)"
    return None


def candidates(root):
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            capture_output=True, check=True, text=True,
        ).stdout
        return [root / name for name in out.split("\0") if name]
    except (OSError, subprocess.CalledProcessError):
        return [p for p in root.rglob("*") if not SKIP_DIRS.intersection(p.relative_to(root).parts)]


def files(root):
    found = set()
    for path in candidates(root):
        rel = path.relative_to(root).parts
        if not path.is_file():
            continue
        if rel[0] == ".github" and path.suffix in (".yml", ".yaml"):
            found.add(path)
        elif path.name in ("action.yml", "action.yaml"):
            found.add(path)
    return sorted(found)


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    failures = 0
    for path in files(root):
        for n, line in enumerate(path.read_text().splitlines(), 1):
            m = USES.match(line)
            if m:
                reason = check_line(m.group(2), m.group(3))
            elif not line.lstrip().startswith("#") and ANY_USES.search(line.split(" #")[0]):
                reason = UNRECOGNISED
            else:
                continue
            if reason:
                print(f"{path.relative_to(root)}:{n}: {reason}")
                failures += 1
    if failures:
        return 1
    print("action pins ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
