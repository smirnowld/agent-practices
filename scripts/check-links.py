#!/usr/bin/env python3
"""Check links in text meant for the owner (P18): a closeout, PR body or update.

Usage: check-links.py [--offline] [FILE]   (reads stdin without FILE)

Fails on:
- a Markdown link whose target is not an https URL;
- a file path in backticks with no GitHub URL for it on the same line;
- a GitHub blob or tree URL pinned to a branch instead of a commit SHA;
- a GitHub URL that does not resolve (skipped with --offline).
Resolving uses `gh api`, so private repositories work when gh is signed in.
"""
import re
import subprocess
import sys

MD_LINK = re.compile(r"\]\(([^)\s]+)\)")
CODE = re.compile(r"`([^`\s]+)`")
PATHLIKE = re.compile(r"^[\w.${}~-]*(/[\w.@${}-]+)+/?(:\d+)?$|^[\w.-]+\.\w{1,5}(:\d+)?$")
GH = re.compile(
    r"https://github\.com/([\w.-]+)/([\w.-]+)/"
    r"(blob|tree|pull|issues|commit|actions/runs)/([^\s)#?>]+)"
)
SHA = re.compile(r"^[0-9a-f]{40}$")


def api_path(owner, repo, kind, rest):
    if kind in ("blob", "tree"):
        ref, _, path = rest.partition("/")
        return f"repos/{owner}/{repo}/contents/{path}?ref={ref}"
    if kind == "pull":
        return f"repos/{owner}/{repo}/pulls/{rest.split('/')[0]}"
    if kind == "issues":
        return f"repos/{owner}/{repo}/issues/{rest.split('/')[0]}"
    if kind == "commit":
        return f"repos/{owner}/{repo}/commits/{rest}"
    return f"repos/{owner}/{repo}/actions/runs/{rest.split('/')[0]}"


def resolves(path):
    r = subprocess.run(["gh", "api", "--silent", path], capture_output=True)
    return r.returncode == 0


def check(text, offline):
    errors = []
    for n, line in enumerate(text.splitlines(), 1):
        for target in MD_LINK.findall(line):
            if not target.startswith("https://"):
                errors.append(f"{n}: link target is not an https URL: {target}")
        for token in CODE.findall(line):
            if "://" in token or not PATHLIKE.match(token):
                continue
            bare = token.split(":")[0].rstrip("/")
            if not any(bare in m.group(0) for m in GH.finditer(line)):
                errors.append(f"{n}: path without a GitHub link on the line: {token}")
        for m in GH.finditer(line):
            owner, repo, kind, rest = m.groups()
            if kind in ("blob", "tree") and not SHA.match(rest.split("/")[0]):
                errors.append(f"{n}: pinned to a branch, not a commit SHA: {m.group(0)}")
            elif not offline and not resolves(api_path(owner, repo, kind, rest)):
                errors.append(f"{n}: does not resolve: {m.group(0)}")
    return errors


def main(argv):
    offline = "--offline" in argv
    args = [a for a in argv if a != "--offline"]
    text = open(args[0]).read() if args else sys.stdin.read()
    errors = check(text, offline)
    for e in errors:
        print(e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
