---
name: grill-spec
description: Use when a plan needs both a grilled problem description and implementation detail on its risky steps in one reviewed artifact, so that enriching-plans does not have to be run by hand on a brainstorm document afterwards. Reports omit empty sections — no placeholder headings, empty tables, or negative statements like "no issues found".
argument-hint: "[inline] [request]"
disable-model-invocation: true
---

# Spec

Arguments: `$ARGUMENTS`. When the first word is `inline`, the enrichment mode is inline (see Modes) and the rest is the request. Otherwise the whole string is the request and the mode is sub-agent.

Run the `grill-plan` interview on the request: read its SKILL.md (the `grill-plan` directory beside this one) and follow its workflow steps 1–5b and its principles. `grill-plan` and `enriching-plans` are user-invoked only, so the Skill tool cannot load them; read the files instead, here and in any sub-agent. Then produce the artifact: the plan, with its hot points enriched.

## Modes

| Mode | Who enriches | When |
|---|---|---|
| **sub-agent** (default) | a fresh sub-agent, from the artifact and the existing material alone, after the plan is written | Pass 2 |
| **inline** | you, with the user, as each hot point surfaces in the interview | during step 5a, written in Pass 1 |

Sub-agent mode is a free test that the artifact stands alone: if the artifact does not carry a decision, the enricher cannot use it, and neither can the reviewer. Inline mode makes the enrichment decisions interview decisions, at the cost of a longer session. Both modes apply the same Enrichment rules and produce the same artifact shape.

## Pass 1: Plan

Write `docs/process/spec/{Y-m-d-session-name}.md`. When `docs/process/` does not exist, ask once where to write the artifact. Sections, in this order, omitting any that would be empty:

- **Problem Statement**, **Glossary**, **Expected Behavior**, **Scope** — as in the grill-plan template.
- **Decisions**: every decision taken in the interview, numbered, with its reason.
- **Steps**: an ordered list. Each step names what it produces (file, symbol, section, deliverable) and which earlier steps it depends on. A step touches code when it changes a file the project compiles, runs or tests; a markdown or config file is not code even when it quotes a regex. A step that touches code lists its exported signatures under an **Interfaces:** line (Produces / Consumes), in the project's language; the enricher anchors its Seams block there.
- **Hot Points**: the steps that meet a criterion below, each with one line naming the criterion and the specific way an implementer would go wrong.
- **Open Questions**

In inline mode, when a step meets a hot-point criterion during the interview, ask the user the questions the Enrichment rules would otherwise leave to the enricher, and write the step's enrichment block in this pass. Add `## Enrichment Decisions` and `## Questions for Reviewer` as the rules require. Pass 2 is skipped.

### Hot point criteria

A step is hot when any of these holds:

- An implementer could write more than one reasonable thing from it, and the choice changes the outcome, not only the wording.
- It carries a critical-detail trigger: a non-obvious algorithm or formula, an ordering or concurrency sequence, a security check, a regex, a wire format, a migration statement.
- The interview flagged it as a risk or an open decision.

Every other step stays lean. No Hot Points section means Pass 2 is skipped.

## Enrichment rules

Applied by the sub-agent in sub-agent mode, and by you in inline mode.

- Enrich only the steps listed under Hot Points. Edit the artifact in place and keep every original line.
- When the step touches code: read the `enriching-plans` SKILL.md (the directory beside this skill's own) and apply its rules — Seams, enrichment blocks, critical-code blocks, `## Enrichment Decisions` and `## Questions for Reviewer` — to the hot steps only. Its rule that every task needs a Seams block does not apply here; a lean step gets nothing.
- Otherwise: under the step add a `> **Enrichment:**` block holding the exact value, formula, wording or ordering the implementer would otherwise guess, each with its reason. A line that restates the step is not enrichment.
- A value the artifact and the existing material do not settle may come from general domain knowledge. Every such value is logged under `## Enrichment Decisions` with its reason, on both branches.
- A name or decision in the artifact that looks wrong goes under `## Questions for Reviewer`; keep using it as written.

## Pass 2: Enrichment (sub-agent mode)

Dispatch one sub-agent with this brief:

- the absolute path of the artifact and of the project root;
- the absolute path of the `enriching-plans` SKILL.md;
- the existing material each hot step touches, as a list of absolute paths, or the statement "none — the artifact's Decisions are the only source";
- the Hot Points section verbatim;
- the Enrichment rules verbatim, preceded by "Read the artifact and the listed existing material."

When the sub-agent returns, read `## Questions for Reviewer`. Answer the questions the interview already settled by editing the artifact, and leave the rest for the reviewer.

**IMPORTANT** ensure that the artifact you produced is present in the correct directory. No need to display it in the output.
