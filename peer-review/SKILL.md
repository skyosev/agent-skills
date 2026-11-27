---
name: peer-review
description: Use when asked to peer-review, critique or re-review a brainstorm.md, spec.md or implementation plan (00.plan.md and its task files) that the grill-plan, grill-spec, grill-reverse or implementation-plan skills wrote, in any review round. Reports omit empty sections — no placeholder headings, empty tables, or negative statements like "no issues found".
argument-hint: "<document or session folder> [request]"
---

# Peer Review

Arguments: `$ARGUMENTS`. The first word is the document to review, or the session folder that holds it. The rest is the request. It may give the round number, your reviewer name and a focus. An instruction in the request outranks this skill.

You review a document for its author, and the author decides what to accept. Your job is to find what is wrong, missing, or weaker than a simpler alternative, and to show the evidence for each point. You write one file: the review. The document, the code and the other reviews stay as they are.

## 1. Where the review goes

The document lives in a session folder, `{root}/{Y-m-d-name}/`, which the Artifact folder section of `grill-plan/SKILL.md` (beside this skill's directory) describes. The review goes into a subfolder of that session folder, chosen by the kind of document:

| Document | Written by | Review subfolder |
|---|---|---|
| `brainstorm.md` | `grill-plan` | `review-brainstorm/` |
| `spec.md` | `grill-spec`, `grill-reverse` | `review-spec/` |
| `00.plan.md` and its task files `NN.<name>.md` (a one-task plan is `01.<name>.md` alone) | `implementation-plan` | `review-plan/` |

When the request names only the session folder and the folder holds more than one kind, review the one furthest along: the plan, else the spec, else the brainstorm.

The file is `round-<N>-<reviewer>.md`, for example `review-spec/round-2-codex.md`:

- `<reviewer>` is the name the request gives you. Otherwise it is the lowercase name of the agent you run as: `claude`, `codex`, `gemini`, `grok`.
- `<N>` is the round the request gives. Otherwise it is one more than the highest round in the subfolder, or 1 when the subfolder is empty or missing. Only the request can put two reviewers into the same round.

## 2. Read

- The document in full, and every file it links.
- The material it builds on: the code at the current commit, or the skills, documents and data it names. Every claim the document makes about that material (a signature, a value, a behavior, a line reference) must be grounded in it: check each one against the source.
- The current documentation of each third-party service or library the document relies on. Check that it supports what the document claims, and whether it offers a more up-to-date approach.
- The other documents in the session folder. A plan answers to its spec, and a spec to its brainstorm.
- From round 2 on: every earlier review in the subfolder, from every reviewer, any author responses beside them, and what changed in the document since the latest round (`git log -p -- <document>`).

When a claim can be measured, measure it: run the code, the tests or a probe from a temporary directory outside the repository. Delete what the run leaves in the repository, such as a cache folder.

## 3. What to look for

The document is a proposal, not a set of final decisions. Be skeptical. Challenge each decision that does not look thoroughly considered, including the ones in its Decisions section, and state each objection plainly.

- Inconsistencies: inside the document, against the other documents in the session folder, or against the code.
- Weak assumptions, missed details and underestimated aspects: assumptions stated as facts, risks that nobody measured, inputs a user would plausibly send, error states, and edge cases that no test or acceptance criterion covers.
- Claims that the code or a third party's documentation does not support.
- Gaps, and parts that can be refined or simplified. Does the proposal solve the stated problem for the stated user? Is there a simpler approach?
- Over-engineering, premature optimisation, cargo cult refactoring and lava layering.
- For a plan: every requirement of the spec maps to a task, names and signatures match across tasks, and each test would fail if the behavior it claims to pin broke.

Recommend a change wherever you see room for improvement, an alternative approach, or a decision or statement you disagree with.

Keep focus on the document's goal. An improvement unrelated to that goal is scope creep, not a finding.

When the document or the request states a compatibility requirement, hold the document to it. Otherwise backward compatibility is not a concern: an API may change without a migration path.

## 4. Write the review

The review holds these parts, in this order:

1. The title: `# Round <N> review of <the document's title>`.
2. One paragraph. It opens with the verdict as one bold sentence that says what to do next, such as **Revise the spec before planning.** or **Ready for implementation.** It then says what holds and what the most important point puts at stake, and links the document.
3. From round 2 on, `## Earlier points`: one line for each point of the earlier rounds, from every reviewer. Each line says fixed, still open or withdrawn, and why.
4. One `## <n>. <Severity>: <the change, as an instruction>` section for each finding, most severe first, for example `## 1. High: Round Retry-After up`. Each one says what is wrong, gives the evidence (a value, a scenario, a file and line), and recommends the change. It closes with links to the places it cites, relative to the review file: `../spec.md#decisions`, `../../../../src/limits.py#L12`.
5. `## Outside this document`: points about the other documents in the session folder, each naming its document.

Include a part only when it has content.

Severity:

- **Critical**: as written, the work fails its goal, loses data or opens a security hole.
- **High**: an implementer would likely build the wrong thing, or an input a user plausibly sends breaks it.
- **Medium**: a gap or a weaker choice that will cost rework later.
- **Low**: a refinement; the document works without it.

Then reply with the review's path and its verdict sentence.
