---
name: project-visuals
description: Create or regenerate the one-page HTML visuals in docs/visuals/ from a project's roadmap, plan, architecture and tech-stack docs, following templates/docs/visuals.md. Use when a source doc changed or the drift check reports a visual older than its source.
---

# Project visuals

1. **Pick the visuals to update.** A visual is due when its source doc has a
   newer commit than the visual. Compare with `git log -1 --format=%cI -- <file>`.
2. **Read the source doc only.** Everything in the visual must come from it.
   If the visual needs something the doc lacks, update the doc first.
3. **Build to the spec** in `templates/docs/visuals.md`: shared encoding,
   legend, eyebrow and headline, the shape for that doc, light and dark.
   Reuse the project's existing visual CSS so all its visuals look alike.
   For the plan: group work packages into 10–15 deliverables named by what
   they deliver; draw only direct dependencies (dashed for "best after") and
   list the rest under "Needs" in the table; take status from merged or open
   PRs and mark anything without evidence "unknown", never guessed; put work
   carried from earlier phases in a "beside the phase" panel.
4. **Check.** Open it in a browser in light and dark; every item in the
   source's main sections appears; no internal IDs; links resolve.
5. **Deliver** in the same PR as the source change when possible. Update
   `docs/visuals/README.md` with the GitHub link (P18).
