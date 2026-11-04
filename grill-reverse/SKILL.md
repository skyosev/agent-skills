---
name: grill-reverse
description: Use when a branch, PR or MR already exists and its specification needs an independent peer review that the implementation must not anchor — to find missed requirements, wrong assumptions or better approaches. Reports omit empty sections — no placeholder headings, empty tables, or negative statements like "no issues found".
argument-hint: "[branch | PR/MR number or URL] [request]"
disable-model-invocation: true
---

# Reverse Spec

Arguments: `$ARGUMENTS`. The first word names the change (a branch, or a PR/MR number or URL); the rest is the request. With no target, use the current branch.

The artifact is the spec the change should have started from: the problem, the needs, the constraints and the observable behavior, written before any approach was chosen. A reviewer reads it to propose and judge approaches. The branch's approach is the one thing the reviewer must invent for themselves, so it never reaches the artifact — not as a decision, a step, a recommendation, an option among several, or an exclusion.

## 1 Read the change

- Base: the PR/MR target branch, else the default branch. Diff with `git diff <base>...<head>` and read `git log <base>..<head>` with bodies. The spec describes the system at the merge base, even when the change has since been merged. When the branch carries commits that reached the base through another PR, their hunks belong to that PR: leave them out.
- Read the PR/MR description, its review threads and any linked ticket (`gh` / `glab`).
- Read the touched files at the merge base: that is the system the spec describes.

## 2 Build the withheld list (session only)

Write down, for your own use and never for the artifact:

- the approach, in one phrase;
- every name the change adds or renames: files, directories, symbols, config keys, flags, env vars, test names, terms it coins;
- every case its new tests pin, one line each (input → expected result);
- every measurement or result that only exists because of the approach (a probe of the chosen design, a benchmark of the new code).

## 3 Interview

Run `grill-plan` workflow steps 1–5a and its principles: read its SKILL.md in the `grill-plan` directory beside this one (it is user-invoked only, so the Skill tool cannot load it). The diff shows what was built, not what was needed, so aim the questions at intent:

- Is this behavior change required, or a side effect of the approach?
- This edge case is handled (or not handled) — is that the requirement?
- This looks like a bug — what should happen instead?
- Which constraint forced this choice? Does it bind every approach, or only this one?

Skip step 5b: a render of the branch shows the solution. A capture of the base state is fine.

## 4 Write the artifact

Write `docs/process/spec/{Y-m-d-session-name}.md`. The file name, title and text never name the branch, the PR/MR or its author, and never say the work exists. When `docs/process/` does not exist, ask once where to write it.

Every sentence is one of: a fact about the system at the merge base, a need, a constraint, an observable outcome, or an open question. Sections, in this order, omitting any that would be empty:

- **Problem Statement** — what a user or developer sees today, with real values, and why it matters.
- **Glossary** — terms of the domain and of the code at the merge base.
- **Context** — the existing types, signatures, documents and measured facts the work builds on, with file references at the merge base. A fact measured on the branch belongs here only when it describes the system or its environment and holds for any approach.
- **Expected Behavior** — primary flow, alternate flows, error and invalid states, as observable outcomes. A trap the branch handled becomes an edge case here when it holds for any approach. A bug on the branch becomes the intended behavior, stated plainly.
- **Constraints** — each force that shaped the branch's choices, stated as the force ("the login secret is not copied to disk", "must work on hosts where `bwrap` fails"), with its source.
- **Acceptance Criteria** — checks a reviewer can run or picture against any approach. A case from the branch's tests is a criterion only when a different approach would face it too.
- **Scope** — Includes / Excludes, as problems and behaviors.
- **Open Questions** — what the interview did not settle.

## 5 Leak check

Grep the artifact for every entry on the withheld list, case-insensitive, then read it once as a reviewer asking "what does the author already want built?". Reword every hit as the need behind it, or delete it. Repeat until a pass finds nothing.

Then tell the user the artifact path and how many leaks the check removed. Keep the withheld list in chat: it is the user's yardstick for comparing the reviewers' approaches with the branch.
