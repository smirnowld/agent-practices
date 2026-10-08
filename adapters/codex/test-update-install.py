#!/usr/bin/env python3
"""Exercise the updater against disposable repositories and an isolated home."""

import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).with_name("update-install.py")


class UpdaterTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        home = self.base / "home"
        home.mkdir()
        self.env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"))
        for key in list(self.env):
            if key.startswith("GIT_") or key.startswith("AGENT_PRACTICES_"):
                del self.env[key]
        self.skills = self.base / "installed-skills"
        self.roles = self.base / "installed-roles"
        self.env.update(AGENT_PRACTICES_SKILLS_DIR=str(self.skills),
                        AGENT_PRACTICES_ROLES_DIR=str(self.roles))
        self.origin = self.base / "origin.git"
        self.seed = self.base / "seed"
        self.repo = self.base / "checkout with spaces"
        self.run_git(self.base, "init", "--bare", str(self.origin))
        self.run_git(self.base, "init", "-b", "main", str(self.seed))
        self.configure(self.seed)
        (self.seed / "skills/example").mkdir(parents=True)
        (self.seed / "skills/example/SKILL.md").write_text("skill\n")
        (self.seed / "adapters/codex/agents").mkdir(parents=True)
        (self.seed / "adapters/codex/agents/example.toml").write_text("role\n")
        shutil.copyfile(SCRIPT, self.seed / "adapters/codex/update-install.py")
        self.commit(self.seed)
        self.run_git(self.seed, "remote", "add", "origin", str(self.origin))
        self.run_git(self.seed, "push", "origin", "main")
        self.run_git(self.base, "clone", "--branch", "main", str(self.origin), str(self.repo))
        self.configure(self.repo)
        self.run_git(self.repo, "remote", "set-url", "origin", "git@github.com:example/policy.git")
        # Substitute transport only in this test executable, after production
        # has validated the effective URL. Production has no test bypass.
        tools = self.base / "transport-tools"
        tools.mkdir()
        wrapper = tools / "git"
        self.real_git = shutil.which("git")
        wrapper.write_text("#!/usr/bin/env python3\nimport os, sys\n"
                           "args = sys.argv[1:]\n"
                           "if 'fetch' in args:\n"
                           "    assert 'SSH_ASKPASS' not in os.environ and 'GIT_ASKPASS' not in os.environ\n"
                           "    assert 'core.askPass=' in args\n"
                           "    args = [" + repr(str(self.origin)) +
                           " if arg == 'https://github.com/example/policy.git' else arg for arg in args]\n"
                           "os.execv(" + repr(self.real_git) + ", [" + repr(self.real_git) + "] + args)\n")
        wrapper.chmod(0o755)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]

    def run_git(self, where, *args):
        return subprocess.check_output(["git", "-C", str(where), *args], env=self.env,
                                       stderr=subprocess.DEVNULL, text=True).strip()

    def configure(self, repo):
        self.run_git(repo, "config", "user.name", "Test")
        self.run_git(repo, "config", "user.email", "test@example.invalid")

    def commit(self, repo):
        self.run_git(repo, "add", ".")
        self.run_git(repo, "commit", "-m", "fixture")

    def advance(self):
        (self.seed / "new-file").write_text("remote update\n")
        self.commit(self.seed)
        self.run_git(self.seed, "push", "origin", "main")

    def update(self, verbose=True):
        command = ["python3", str(self.repo / "adapters/codex/update-install.py")]
        if verbose:
            command.append("--verbose")
        result = subprocess.run(command,
                                env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        if verbose:
            self.assertEqual(len(result.stdout.splitlines()), 1)
            self.assertTrue(result.stdout.startswith("agent-practices: "))
        else:
            self.assertEqual(result.stdout, "")
        return result.stdout.strip()

    def test_default_quiet_still_installs_and_updates(self):
        self.update(verbose=False)
        self.assertEqual((self.skills / "example").resolve(), (self.repo / "skills/example").resolve())
        self.assertEqual((self.roles / "example.toml").read_text(), "role\n")
        self.advance()
        self.update(verbose=False)
        self.assertEqual(self.run_git(self.repo, "rev-parse", "HEAD"),
                         self.run_git(self.seed, "rev-parse", "HEAD"))

    def test_fast_forward_and_idempotency(self):
        self.advance()
        fetch_head = self.repo / ".git/FETCH_HEAD"
        fetch_head.write_text("another fetch's state\n")
        self.assertIn("updated ", self.update())
        self.assertEqual(fetch_head.read_text(), "another fetch's state\n")
        self.assertEqual(self.run_git(self.repo, "for-each-ref", "refs/agent-practices-updater"), "")
        self.assertEqual(self.run_git(self.repo, "rev-parse", "HEAD"),
                         self.run_git(self.seed, "rev-parse", "HEAD"))
        role = self.roles / "example.toml"
        stamp = role.stat().st_mtime_ns
        self.assertIn("already current; skills +0/-0, roles 0", self.update())
        self.assertEqual(role.stat().st_mtime_ns, stamp)

    def test_dirty_checkout(self):
        self.advance()
        target = self.repo / "skills/example/SKILL.md"
        target.write_text("local work\n")
        self.assertIn("checkout has local changes", self.update())
        self.update(verbose=False)
        self.assertEqual(target.read_text(), "local work\n")
        self.assertFalse((self.repo / "new-file").exists())

    def test_other_branch_and_detached_head(self):
        self.run_git(self.repo, "switch", "-c", "work")
        self.assertIn("not on main", self.update())
        self.run_git(self.repo, "checkout", "--detach")
        self.assertIn("skipped:", self.update())

    def test_unreachable_origin(self):
        self.origin.rename(self.base / "unavailable.git")
        self.assertIn("Git operation failed", self.update())
        self.update(verbose=False)

    def test_url_rewrite_and_askpass_blocked(self):
        marker = self.base / "prompt-was-run"
        askpass = self.base / "askpass"
        askpass.write_text("#!/bin/sh\ntouch '" + str(marker) + "'\n")
        askpass.chmod(0o755)
        self.env.update(SSH_ASKPASS=str(askpass), GIT_ASKPASS=str(askpass))
        self.run_git(self.repo, "config", "core.askPass", str(askpass))
        self.run_git(self.repo, "config", "url.ssh://git@example.invalid/.insteadOf",
                     "https://github.com/")
        self.assertIn("URL rewrite changes anonymous HTTPS", self.update())
        self.assertFalse(marker.exists())
        self.run_git(self.repo, "config", "--unset-all", "url.ssh://git@example.invalid/.insteadOf")
        self.assertIn("already current", self.update())
        self.assertFalse(marker.exists())

    def test_deadline(self):
        tools = self.base / "tools"
        tools.mkdir()
        wrapper = tools / "git"
        real_git = str(Path(self.env["PATH"].split(os.pathsep)[0]) / "git")
        wrapper.write_text("#!/usr/bin/env python3\nimport os, sys, time\n"
                           "if 'fetch' in sys.argv: time.sleep(30)\n"
                           "os.execv(" + repr(real_git) + ", [" + repr(real_git) + "] + sys.argv[1:])\n")
        wrapper.chmod(0o755)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        start = time.monotonic()
        self.assertIn("timed out", self.update())
        self.assertLess(time.monotonic() - start, 13)

    def test_diverged(self):
        (self.repo / "local-file").write_text("committed local work\n")
        self.commit(self.repo)
        before = self.run_git(self.repo, "rev-parse", "HEAD")
        self.advance()
        self.assertIn("cannot fast-forward", self.update())
        self.assertEqual(self.run_git(self.repo, "rev-parse", "HEAD"), before)

    def test_reconcile_preserves_foreign_entries(self):
        self.skills.mkdir()
        self.roles.mkdir()
        (self.skills / "gone").symlink_to(self.repo / "skills/gone")
        (self.skills / "foreign-dangling").symlink_to(self.base / "missing")
        (self.skills / "example").mkdir()
        (self.roles / "example.toml").write_text("old role\n")
        (self.roles / "foreign.toml").write_text("foreign\n")
        note = self.update()
        self.assertIn("skills +0/-1, roles 1, collisions skipped 1", note)
        self.assertTrue((self.skills / "example").is_dir())
        self.assertTrue((self.skills / "foreign-dangling").is_symlink())
        self.assertEqual((self.roles / "foreign.toml").read_text(), "foreign\n")
        self.assertEqual((self.roles / "example.toml").read_text(), "role\n")
        (self.skills / "example").rmdir()
        self.assertIn("skills +1/-0", self.update())
        self.assertEqual((self.skills / "example").resolve(), (self.repo / "skills/example").resolve())

    def test_role_symlink_collision(self):
        self.roles.mkdir()
        foreign = self.base / "foreign"
        foreign.write_text("foreign\n")
        (self.roles / "example.toml").symlink_to(foreign)
        self.assertIn("collisions skipped 1", self.update())
        self.assertEqual(foreign.read_text(), "foreign\n")

    def test_bad_origin_and_overlapping_targets(self):
        self.run_git(self.repo, "remote", "set-url", "origin", "https://user:password@github.com/example/policy")
        self.assertIn("not an anonymous GitHub", self.update())
        self.env["AGENT_PRACTICES_SKILLS_DIR"] = str(self.repo / "skills")
        self.assertIn("targets overlap", self.update())

    def test_another_updater_holds_lock(self):
        with (self.repo / ".git/agent-practices-update.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertIn("another updater is running", self.update())
            self.assertFalse(self.skills.exists())

    def test_local_change_during_fetch(self):
        self.advance()
        tools = self.base / "tools"
        tools.mkdir()
        wrapper = tools / "git"
        real_git = str(Path(self.env["PATH"].split(os.pathsep)[0]) / "git")
        target = self.repo / "skills/example/SKILL.md"
        wrapper.write_text("#!/usr/bin/env python3\nimport os, sys\nfrom pathlib import Path\n"
                           "if 'fetch' in sys.argv: Path(" + repr(str(target)) + ").write_text('concurrent work')\n"
                           "os.execv(" + repr(real_git) + ", [" + repr(real_git) + "] + sys.argv[1:])\n")
        wrapper.chmod(0o755)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        self.assertIn("checkout has local changes", self.update())
        self.assertEqual(target.read_text(), "concurrent work")
        self.assertFalse((self.repo / "new-file").exists())

    def test_ignored_local_work_blocks_merge(self):
        (self.repo / ".git/info/exclude").write_text("new-file\n")
        (self.repo / "new-file").write_text("ignored local work\n")
        self.advance()
        self.assertIn("Git operation failed", self.update())
        self.assertEqual((self.repo / "new-file").read_text(), "ignored local work\n")


if __name__ == "__main__":
    unittest.main()
