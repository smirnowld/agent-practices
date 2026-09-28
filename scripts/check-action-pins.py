#!/usr/bin/env python3
"""Check that GitHub Actions references are pinned (baseline C4).

Usage: check-action-pins.py [DIR]   (default: current directory)

Reads every .yml and .yaml file under DIR/.github and DIR/action.yml. Each
`uses:` must be pinned to a full 40-character commit SHA and carry a comment
ending in the version, `# vX.Y.Z`; Dependabot only rewrites comments that end
with the version. Local actions (`./...`) are exempt; `docker://` images must
be pinned to a `@sha256:` digest.

Prints `path:line: reason` for each failure and exits 1 if there are any.
"""
import pathlib
import re
import sys

USES = re.compile(r"^\s*(?:-\s+)?uses:\s*(['\"]?)([^'\"\s#]+)\1\s*(#.*)?$")
SHA_REF = re.compile(r"^[\w.-]+/[\w./-]+@[0-9a-f]{40}$")
VERSION_COMMENT = re.compile(r"#.*\bv\d+\.\d+\.\d+\s*$")
DIGEST = re.compile(r"@sha256:[0-9a-f]{64}$")


def check_line(ref, comment):
    if ref.startswith("./"):
        return None
    if ref.startswith("docker://"):
        return None if DIGEST.search(ref) else "docker image not pinned to a sha256 digest"
    if not SHA_REF.match(ref):
        return f"{ref} not pinned to a 40-character commit SHA"
    if not comment or not VERSION_COMMENT.search(comment):
        return f"{ref} needs a comment ending in the version (# vX.Y.Z)"
    return None


def files(root):
    github = root / ".github"
    found = sorted(p for p in github.rglob("*") if p.suffix in (".yml", ".yaml")) if github.is_dir() else []
    found += [p for p in (root / "action.yml", root / "action.yaml") if p.is_file()]
    return found


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    failures = 0
    for path in files(root):
        for n, line in enumerate(path.read_text().splitlines(), 1):
            m = USES.match(line)
            if not m:
                continue
            reason = check_line(m.group(2), m.group(3))
            if reason:
                print(f"{path.relative_to(root)}:{n}: {reason}")
                failures += 1
    if failures:
        return 1
    print("action pins ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
