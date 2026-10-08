#!/usr/bin/env python3
"""Fail-open SessionStart updater; uses only the Python standard library."""

import fcntl
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
DEADLINE = 10
END = None


def git(*args, cleanup=False):
    remaining = 1 if cleanup else (DEADLINE if END is None else END - time.monotonic())
    if remaining <= 0:
        raise RuntimeError("network or Git operation timed out")
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never")
    # Ignore inherited repository selection from the hook's caller.
    for key in list(env):
        if (key.startswith("GIT_") and key != "GIT_TERMINAL_PROMPT") or key == "SSH_ASKPASS":
            del env[key]
    process = subprocess.Popen(
        ["git", "-c", "core.hooksPath=/dev/null", "-c", "merge.autostash=false",
         "-c", "submodule.recurse=false",
         "-c", "credential.helper=", "-c", "core.askPass=", "-C", str(ROOT), *args],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=env, start_new_session=True,
    )
    try:
        out, _ = process.communicate(timeout=remaining)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise RuntimeError("network or Git operation timed out")
    if process.returncode:
        raise RuntimeError("Git operation failed")
    return out.decode().strip()


def origin_url(value):
    match = re.fullmatch(
        r"(?:git@github\.com:|ssh://git@github\.com/|https://github\.com/)"
        r"([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?", value)
    if not match or any(part in (".", "..") for part in match.groups()):
        raise RuntimeError("origin is not an anonymous GitHub repository URL")
    return "https://github.com/{}/{}.git".format(*match.groups())


def checkout_state():
    if git("rev-parse", "--abbrev-ref", "HEAD") != "main":
        return "skipped: checkout is not on main"
    if git("status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none"):
        return "skipped: checkout has local changes"
    return None


def update():
    reason = checkout_state()
    if reason:
        return reason
    url = origin_url(git("remote", "get-url", "origin"))
    if git("ls-remote", "--get-url", url) != url:
        raise RuntimeError("Git URL rewrite changes anonymous HTTPS origin")
    before = git("rev-parse", "HEAD")
    ref = "refs/agent-practices-updater/" + uuid.uuid4().hex
    try:
        git("fetch", "--no-write-fetch-head", "--no-tags", "--no-recurse-submodules",
            url, "refs/heads/main:" + ref)
        reason = checkout_state()
        if reason or git("rev-parse", "HEAD") != before:
            return reason or "skipped: checkout changed during fetch"
        latest = git("rev-parse", ref)
        if latest == before:
            return "already current"
        try:
            git("merge-base", "--is-ancestor", before, latest)
        except RuntimeError:
            return "skipped: main cannot fast-forward"
        git("merge", "--ff-only", "--no-edit", "--no-overwrite-ignore", latest)
        return "updated {} to {}".format(before[:8], latest[:8])
    finally:
        try:
            git("update-ref", "-d", ref, cleanup=True)
        except RuntimeError:
            pass  # A repository error can leave an inert uniquely owned ref.


def inside(path, root):
    return path == root or root in path.parents


def reconcile():
    skills = Path(os.environ.get("AGENT_PRACTICES_SKILLS_DIR", "~/.agents/skills")).expanduser().resolve()
    roles = Path(os.environ.get("AGENT_PRACTICES_ROLES_DIR", "~/.codex/agents")).expanduser().resolve()
    # Overrides must never turn installation into edits of the source checkout.
    if (inside(skills, ROOT) or inside(roles, ROOT)
            or inside(ROOT, skills) or inside(ROOT, roles)
            or inside(skills, roles) or inside(roles, skills)):
        raise RuntimeError("installation targets overlap the checkout or each other")
    skills.mkdir(parents=True, exist_ok=True)
    roles.mkdir(parents=True, exist_ok=True)
    linked = copied = removed = skipped = 0
    for dest in skills.iterdir():
        if dest.is_symlink() and not dest.exists() and inside(dest.resolve(), ROOT):
            dest.unlink()
            removed += 1
    for source in sorted((ROOT / "skills").iterdir()):
        if not source.is_dir():
            continue
        dest = skills / source.name
        if dest.is_symlink() and dest.resolve() == source.resolve():
            continue
        if dest.exists() or dest.is_symlink():
            skipped += 1
            continue
        try:
            dest.symlink_to(source)
            linked += 1
        except FileExistsError:
            skipped += 1
    for source in sorted((ROOT / "adapters/codex/agents").glob("*.toml")):
        dest = roles / source.name
        if dest.is_symlink() or (dest.exists() and not dest.is_file()):
            skipped += 1
            continue
        data = source.read_bytes()
        previous = dest.read_bytes() if dest.exists() else None
        if previous == data:
            continue
        with tempfile.NamedTemporaryFile(dir=roles, prefix=".update-", delete=False) as tmp:
            tmp.write(data)
            temporary = Path(tmp.name)
        try:
            # Preserve a target changed while the replacement was prepared.
            if dest.is_symlink() or (dest.read_bytes() if dest.exists() else None) != previous:
                skipped += 1
                continue
            os.replace(temporary, dest)
            copied += 1
        finally:
            temporary.unlink(missing_ok=True)
    return "skills +{}/-{}, roles {}, collisions skipped {}".format(linked, removed, copied, skipped)


def main(verbose=False):
    global END
    END = time.monotonic() + DEADLINE
    note = "agent-practices: "
    try:
        common = Path(git("rev-parse", "--git-common-dir"))
        if not common.is_absolute():
            common = ROOT / common
        with (common / "agent-practices-update.lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("another updater is running")
            try:
                result = update()
            except Exception as error:
                result = "skipped: " + str(error)
            note += result
            try:
                note += "; " + reconcile()
            except Exception as error:
                note += "; install skipped: " + str(error)
    except Exception as error:
        note += "skipped: " + str(error)
    if verbose:
        print(" ".join(note.split()))


if __name__ == "__main__":
    main(verbose="--verbose" in sys.argv[1:])
