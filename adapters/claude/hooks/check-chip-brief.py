#!/usr/bin/env python3
"""PreToolUse hook for session starts and cards (start_session, or
spawn_task in older app builds): a started session's prompt must be a brief
(P2c), started at the brief's model and effort.

A call without a prompt passes only as an offer (initiation "offer") or
when it starts an earlier proposal by its proposal_id; any other is blocked.
A prompt that lacks the brief's heading, Model line, Goal or Proof, or whose
Model line lacks a tier followed by its model from tiers.json and then
"at" and a known effort, is blocked with templates/brief.md handed back so
the retry takes one call. A passed model or effort that differs from the
Model line is blocked. A call with a brief whose context is not "fork" (an
omitted context counts as fresh) must pass both model and effort; a fork
inherits the starter's. A session started now ("user_asked") whose Model
line is above the starter's own model or effort is blocked, since the app
would silently run it at the starter's level (cards are capped the same way
when started); ROUTE gives the card-then-switch route instead. spawn_task
has no model or effort parameters, so for it only the brief check applies.
Any error lets the call through with a note on stderr; a broken check must
not block session starts.
"""
import json
import os
import re
import sys

REQUIRED = [
    (r"\A\s*# Brief: \S", "a first line '# Brief: TITLE'"),
    (r"^\s*\*\*Model:\*\* \S", "a '**Model:**' line"),
    (r"^\s*## Goal\s*$", "a '## Goal' section"),
    (r"^\s*## Proof\s*$", "a '## Proof' section"),
]

# Cost order, cheapest first. A model id's family is the alias it contains.
FAMILIES = ["haiku", "sonnet", "opus", "fable"]
EFFORTS = ["low", "medium", "high", "xhigh", "max"]

ROUTE = (
    "The app would start it at your own model and effort, so propose it as a "
    "card instead (initiation \"own_initiative\") passing the brief's model and "
    "effort. When it starts, its model check (P2d) asks you to switch it up, "
    "and the app asks the user to approve the costlier switch."
)


# Older app builds name the start tool this; it has no model or effort parameters.
SPAWN_TASK = "mcp__ccd_session__spawn_task"


def family(model_id):
    found = [f for f in FAMILIES if f in (model_id or "").lower()]
    return found[0] if len(found) == 1 else None


def starter_model(transcript_path):
    model = None
    with open(transcript_path) as f:
        for raw in f:
            try:
                entry = json.loads(raw)
            except ValueError:
                continue
            if isinstance(entry, dict) and entry.get("type") == "assistant":
                m = (entry.get("message") or {}).get("model")
                if m:
                    model = m
    return model


def deny(reason):
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, sys.stdout)


def template_text(root):
    with open(os.path.join(root, "templates/brief.md")) as f:
        return f.read()


def main():
    data = json.load(sys.stdin)
    tool_input = data["tool_input"]
    spawn_task = data.get("tool_name") == SPAWN_TASK
    prompt = tool_input.get("prompt")
    root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.join(os.path.dirname(__file__), "../../..")
    if prompt is None or prompt == "":
        if tool_input.get("initiation") == "offer" or tool_input.get("proposal_id"):
            return
        deny(
            "The start needs the filled brief as its prompt (P2c); only an offer "
            "(initiation \"offer\") or a call with a proposal_id may omit it. "
            "Fill this template, pass it as prompt, and pass the Model line's "
            "model and effort as model and effort.\n\n" + template_text(root)
        )
        return
    if not isinstance(prompt, str):
        raise TypeError("prompt is not a string")
    missing = [what for pattern, what in REQUIRED if not re.search(pattern, prompt, re.M)]
    with open(os.path.join(root, "adapters/claude/tiers.json")) as f:
        tiers = json.load(f)
    models, effort_map = tiers["models"], tiers["effort"]
    pairs_re = "|".join(re.escape(t) + r"\s*\(\s*" + re.escape(m) for t, m in models.items())
    line = re.search(r"^\s*\*\*Model:\*\* .*$", prompt, re.M)
    pair = line and re.search(r"\b(" + pairs_re + r")\b", line.group(0), re.I)
    if line and not pair:
        pairs = ", ".join(f"{t} ({m})" for t, m in models.items())
        missing.append("the model in the Model line, as TIER (MODEL): " + pairs)
    word = brief_effort = None
    if pair:
        # The effort follows the model as "at EFFORT", with punctuation allowed
        # before "at"; "extra high" counts as "extra-high".
        rest = line.group(0)[pair.end():]
        m = re.match(r"\s*\)[\s,;:.-]*at\s+(extra[\s-]+high\b|\S+)", rest, re.I)
        if m:
            word = re.sub(r"\s+", "-", m.group(1).lower()).rstrip(".,;:")
            brief_effort = effort_map.get(word, word if word in EFFORTS else None)
        if not brief_effort:
            valid = list(effort_map) + [e for e in EFFORTS if e not in effort_map]
            got = f"got {m.group(1)!r}" if m else "none found"
            missing.append(
                "a known effort after the model in the Model line, as "
                f"'{pair.group(1)}) at EFFORT' ({got}): " + ", ".join(valid)
            )
    if missing:
        how = (
            "and repeat the Model line's model and effort in the summary, since "
            "spawn_task has no model or effort parameters" if spawn_task else
            "and pass the Model line's model and effort as model and effort"
        )
        deny(
            "A started session's prompt is a brief (P2c). Missing: " + "; ".join(missing) + ". "
            "Refill the prompt from this template, keep what you already wrote, "
            + how + ".\n\n" + template_text(root)
        )
        return
    if spawn_task:
        return

    brief_model = re.split(r"\(\s*", pair.group(1))[-1].lower()
    brief_desc = brief_model + (" at " + word if brief_effort else "")

    problems = []
    passed_model = tool_input.get("model")
    if passed_model and family(passed_model) != family(brief_model):
        problems.append(f"model {passed_model!r} is not the Model line's model {brief_model}")
    passed_effort = tool_input.get("effort")
    if passed_effort and brief_effort and str(passed_effort).lower() != brief_effort:
        problems.append(f"effort {passed_effort!r} is not the Model line's effort {word} ({brief_effort})")
    if problems:
        effort_hint = f" and effort \"{brief_effort}\"" if brief_effort else ""
        deny(
            "The session would not start at its brief's model and effort: " + "; ".join(problems) + ". "
            f"Pass model \"{brief_model}\"{effort_hint} as the Model line says ({brief_desc}), "
            "or fix the Model line."
        )
        return
    if tool_input.get("context") != "fork":
        absent = [k for k in ("model", "effort") if not tool_input.get(k)]
        if absent:
            deny(
                "A fresh session must start at its brief's model and effort, so the "
                "call passes both; missing: " + " and ".join(absent) + ". "
                f"Pass model \"{brief_model}\" and effort \"{brief_effort}\" from the "
                f"Model line ({brief_desc})."
            )
            return

    if tool_input.get("initiation") != "user_asked":
        return
    try:
        s_model = starter_model(data["transcript_path"])
    except Exception as e:
        s_model = None
        why = f"{type(e).__name__}: {e}"
    else:
        why = "no assistant model in the transcript" if not s_model else ""
    s_family = family(s_model)
    s_effort = (os.environ.get("CLAUDE_EFFORT") or "").lower()
    if not s_family or s_effort not in EFFORTS:
        if s_model and not s_family:
            why = f"unknown model family in {s_model!r}"
        if s_effort not in EFFORTS:
            why = (why + "; " if why else "") + f"CLAUDE_EFFORT={s_effort!r}"
        print(f"check-chip-brief: cap unknown, {why}; starter cap not checked", file=sys.stderr)
        return
    over = []
    b_family = family(brief_model)
    if b_family and FAMILIES.index(b_family) > FAMILIES.index(s_family):
        over.append(f"model {brief_model} is above the starter's {s_family}")
    if brief_effort and EFFORTS.index(brief_effort) > EFFORTS.index(s_effort):
        over.append(f"effort {brief_effort} is above the starter's {s_effort}")
    if over:
        deny(
            "A session started now runs at most at the starter's model and effort; "
            f"the app would silently run this brief ({brief_desc}) at the starter's level: "
            + "; ".join(over) + ". " + ROUTE
        )


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"check-chip-brief: skipped, {type(e).__name__}: {e}", file=sys.stderr)
