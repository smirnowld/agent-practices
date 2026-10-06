#!/usr/bin/env python3
"""Generate vendor agent definitions from roles/ and each adapter's tiers.json.

Run after changing a role or a tier mapping; commit the output. A role whose
frontmatter has `extends: OTHER` gets OTHER's instructions, then its own.
  python3 scripts/build-adapters.py          # write
  python3 scripts/build-adapters.py --check  # fail if output is stale (CI)
"""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HEADER = "Generated from roles/{name}.md by scripts/build-adapters.py; do not edit."


def roles():
    parsed = {}
    for path in sorted((ROOT / "roles").glob("*.md")):
        _, fm, body = path.read_text().split("---", 2)
        meta = {k: v.strip() for k, v in re.findall(r"^(\w+): (.*)$", fm, re.M)}
        parsed[path.stem] = meta, body.strip()
    for name, (meta, body) in parsed.items():
        base = ""
        if "extends" in meta:
            parent = parsed.get(meta["extends"])
            if parent is None or "extends" in parent[0]:
                sys.exit(f"roles/{name}.md: extends must name a role without its own extends")
            base = parent[1]
        yield meta, "\n\n".join(part for part in (base, body) if part)


def claude(meta, body, t):
    lines = [f"name: {meta['name']}", "description: " + json.dumps(meta["description"])]
    if t["tools"][meta["tools"]]:
        lines.append(f"tools: {t['tools'][meta['tools']]}")
    lines += [f"model: {t['models'][meta['tier']]}", f"effort: {t['effort'][meta['effort']]}"]
    body = re.sub(r"`((?:practices|templates|skills)/[^`]+)`", r"`${CLAUDE_PLUGIN_ROOT}/\1`", body)
    text = "---\n" + "\n".join(lines) + "\n---\n\n<!-- " + HEADER.format(**meta) + " -->\n\n" + body + "\n"
    return f"adapters/claude/agents/{meta['name']}.md", text


def toml_str(s):
    """TOML basic string. JSON escapes are valid TOML escapes, except that TOML
    has no \\u escape for surrogate pairs, so keep non-ASCII as is."""
    return json.dumps(s, ensure_ascii=False)


def toml_multiline(s):
    """TOML multi-line basic string: escape backslashes and any run of three
    quotes, and control characters other than newline and tab."""
    s = s.replace("\\", "\\\\").replace('"""', '""\\"')
    s = re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", lambda m: f"\\u{ord(m.group()):04x}", s)
    return '"""\n' + s + '\n"""'


def codex(meta, body, t):
    # Codex standalone custom-agent schema: https://learn.chatgpt.com/docs/agent-configuration/subagents (checked 2026-09-27).
    lines = ["# " + HEADER.format(**meta), f"name = {toml_str(meta['name'])}",
             f"description = {toml_str(meta['description'])}"]
    if t["models"][meta["tier"]]:
        lines.append(f"model = {toml_str(t['models'][meta['tier']])}")
    lines.append(f"model_reasoning_effort = {toml_str(t['effort'][meta['effort']])}")
    if meta["tools"] != "write":
        lines.append('sandbox_mode = "read-only"')
    lines.append("developer_instructions = " + toml_multiline(body))
    return f"adapters/codex/agents/{meta['name']}.toml", "\n".join(lines) + "\n"


PLUGIN = ".claude-plugin/plugin.json"


def plugin_json(names):
    """plugin.json with its "agents" list generated from roles; other keys kept."""
    data = json.loads((ROOT / PLUGIN).read_text())
    data["agents"] = [f"./adapters/claude/agents/{n}.md" for n in names]
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def main():
    check = "--check" in sys.argv
    tiers = {v: json.loads((ROOT / f"adapters/{v}/tiers.json").read_text()) for v in ("claude", "codex")}
    outputs, names = {}, []
    for meta, body in roles():
        names.append(meta["name"])
        for rel, text in (claude(meta, body, tiers["claude"]), codex(meta, body, tiers["codex"])):
            outputs[rel] = text
    outputs[PLUGIN] = plugin_json(names)

    stale, removed = [], []
    for rel, text in outputs.items():
        path = ROOT / rel
        if path.exists() and path.read_text() == text:
            continue
        stale.append(rel)
        if not check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    # Generated agents whose role no longer exists.
    for vendor, ext in (("claude", "md"), ("codex", "toml")):
        for path in sorted((ROOT / f"adapters/{vendor}/agents").glob(f"*.{ext}")):
            rel = path.relative_to(ROOT).as_posix()
            if rel not in outputs:
                removed.append(rel)
                if not check:
                    path.unlink()
    if stale:
        print(("stale: " if check else "wrote: ") + ", ".join(stale))
    if removed:
        print(("stale (no role): " if check else "removed: ") + ", ".join(removed))
    sys.exit(1 if check and (stale or removed) else 0)


if __name__ == "__main__":
    main()
