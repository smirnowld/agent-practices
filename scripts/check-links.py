#!/usr/bin/env python3
"""Check links in text meant for me (P18): a closeout, PR body or update.

Usage: check-links.py [--offline] [--closeout | --closeout-pr] FILE   (reads stdin without FILE)

Fails on:
- a Markdown link whose target is not an https URL;
- a file path, in backticks or plain text, with no GitHub link to that file
  on the same line (a file path has an extension or ends in "/"; a bare name
  needs a common extension; branches, versions and owner/repo names are not
  paths);
- a GitHub blob or tree URL not pinned to a full commit SHA;
- a GitHub URL that does not resolve (skipped with --offline).
Resolving uses `gh api`, so private repositories work when gh is signed in.

With --closeout, also fails on a required chat field of templates/closeout.md
(one above "## Record" not marked "only when") missing from the draft. With
--closeout-pr, also fails on any Record field missing, for the PR description.
"""
import os
import re
import shutil
import subprocess
import sys

MD_LINK = re.compile(r"\]\(([^)\s]+)\)")
TOKEN = re.compile(r"`([^`\s]+)`|(?<![\w/`~])((?:~|\.{0,2})?/?[\w.-]+(?:/[\w.@-]+)+/?)")
EXT = r"\.[A-Za-z][A-Za-z0-9]{0,4}"
FILE_PATH = re.compile(
    rf"^(?:~|\.{{0,2}})/?(?:[\w.@-]+/)*[\w@-][\w.@-]*{EXT}(?::\d+)?$"
    rf"|^(?:~|\.{{0,2}})/?(?:[\w.@-]+/)+$"
)
VERSION = re.compile(r"^v?\d+(\.\d+)+$")
# A name with no folder counts as a file only with a common extension.
KNOWN_EXT = re.compile(
    r"\.(md|txt|py|sh|js|ts|tsx|jsx|json|ya?ml|toml|html|css|swift|kt|go|rs|rb"
    r"|java|sql|cfg|conf|ini|env|lock|mjs|cjs|xml|svg|png)(?::\d+)?$"
)
GH = re.compile(
    r"https://github\.com/([\w.-]+)/([\w.-]+)/"
    r"(blob|tree|pull|issues|commit|actions/runs)/([^\s)#?>`]+)"
)
TRAILING = ".,;:*_'\""
SHA = re.compile(r"^[0-9a-f]{40}$")


def api_path(owner, repo, kind, rest):
    if kind in ("blob", "tree"):
        ref, _, path = rest.partition("/")
        return f"repos/{owner}/{repo}/contents/{path}?ref={ref}"
    first = rest.split("/")[0]
    return {
        "pull": f"repos/{owner}/{repo}/pulls/{first}",
        "issues": f"repos/{owner}/{repo}/issues/{first}",
        "commit": f"repos/{owner}/{repo}/commits/{first}",
    }.get(kind, f"repos/{owner}/{repo}/actions/runs/{first}")


def resolves(path):
    r = subprocess.run(["gh", "api", "--silent", path], capture_output=True)
    return r.returncode == 0


def linked(token, line):
    """True if a link on the line covers this path: a blob or tree URL to it,
    or a PR files view or commit, which P18 allows for diffs."""
    path = re.sub(r":\d+$", "", token).rstrip("/")
    path = re.sub(r"^(\./)+", "", path)
    for m in GH.finditer(line):
        owner, repo, kind, rest = m.groups()
        if kind in ("pull", "commit"):
            return True
        if kind not in ("blob", "tree"):
            continue
        target = rest.rstrip(TRAILING).partition("/")[2].rstrip("/")
        if target and (target == path or path.endswith("/" + target)
                       or target.endswith("/" + path)):
            return True
    return False


def check(text, offline):
    errors = []
    fenced = False
    for n, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        for target in MD_LINK.findall(line):
            if not target.startswith("https://"):
                errors.append(f"{n}: link target is not an https URL: {target}")
        prose = MD_LINK.sub(" ", line)
        prose = GH.sub(" ", re.sub(r"https?://\S+", " ", prose))
        for m in TOKEN.finditer(prose):
            token = (m.group(1) or m.group(2)).rstrip(TRAILING)
            if VERSION.match(token) or not FILE_PATH.match(token):
                continue
            if "/" not in token and not KNOWN_EXT.search(token):
                continue
            if not linked(token, line):
                errors.append(f"{n}: path without a GitHub link on the line: {token}")
        for m in GH.finditer(line):
            owner, repo, kind, rest = m.groups()
            rest = rest.rstrip(TRAILING)
            url = m.group(0).rstrip(TRAILING)
            if kind in ("blob", "tree") and not SHA.match(rest.split("/")[0]):
                errors.append(f"{n}: not pinned to a full commit SHA: {url}")
            elif not offline and not resolves(api_path(owner, repo, kind, rest)):
                errors.append(f"{n}: does not resolve: {url}")
    return errors


TEMPLATE = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                        "..", "templates", "closeout.md")
FIELD = re.compile(r"^\*\*([^*]+):\*\*\s*(<only when)?", re.M)


def missing_fields(text, record=False):
    """Field labels of the closeout template that the draft does not use:
    the required chat fields, plus every Record field with record=True."""
    chat, _, rest = open(TEMPLATE).read().partition("\n## Record")
    fields = [f for f, optional in FIELD.findall(chat) if not optional]
    if record:
        fields += [f for f, _ in FIELD.findall(rest)]
    return [f"closeout field missing: **{f}:**" for f in fields
            if not re.search(rf"\*\*{re.escape(f)}:\*\*", text)]


def main(argv):
    offline = "--offline" in argv
    closeout = "--closeout" in argv or "--closeout-pr" in argv
    args = [a for a in argv if a not in ("--offline", "--closeout", "--closeout-pr")]
    if not offline and not shutil.which("gh"):
        print("error: gh not found; rerun with --offline for the local checks",
              file=sys.stderr)
        return 2
    text = open(args[0]).read() if args else sys.stdin.read()
    errors = check(text, offline)
    if closeout:
        errors += missing_fields(text, record="--closeout-pr" in argv)
    for e in errors:
        print(e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
