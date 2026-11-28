---
name: feedback-give
description: Use when asked to review or re-review a brainstorm.md, spec.md or implementation plan (00.plan.md and its task files).
argument-hint: "[document or session folder] [request]"
---

# Feedback Give

Arguments: `$ARGUMENTS`. The first word is the document to review, or the session folder that holds it. When the arguments name no document, review the one you reviewed earlier in this session. The rest is the request. It may give the round number, your reviewer name and a focus. An instruction in the request outranks this skill.

You review a document for its author, and the author decides what to accept. The author answers your review with `feedback-get`, and you re-review that answer in the next round. You write two things: your review, and one line at the end of the ledger. The document, the code and every other file stay as they are.

## Your files only

Each reviewer works alone, so that no review anchors on another. A review subfolder holds the files of every reviewer. Of these, you open exactly three kinds, where `<reviewer>` is your own name (§1):

- `ledger.md`;
- `round-<N>-<reviewer>.md`: your own reviews;
- `round-<N>-response-<reviewer>.md`: the author's responses to you.

Every other file in a review subfolder (`review-brainstorm/`, `review-spec/`, `review-plan/`) belongs to another reviewer. Never open, search or quote it, in any round, even when a link, a file listing or a search result leads to it. You may see its name, as in the ledger; its content stays unread. Exclude the review subfolders from every search: `rg -g '!review-*'`, `grep -r --exclude-dir='review-*'`.

## 1. Where the review goes

The document lives in a session folder, `{root}/{Y-m-d-name}/`: the folder that holds it. The review goes into a subfolder of that session folder, chosen by the kind of document:

| Document | Written by | Review subfolder |
|---|---|---|
| `brainstorm.md` | `grill-plan` | `review-brainstorm/` |
| `spec.md` | `grill-spec`, `grill-reverse` | `review-spec/` |
| `00.plan.md` and its task files `NN.<name>.md` (a one-task plan is `01.<name>.md` alone) | `implementation-plan` | `review-plan/` |

When the request names only the session folder and the folder holds more than one kind, review the one furthest along: the plan, else the spec, else the brainstorm.

The subfolder holds the reviews `round-<N>-<reviewer>.md`, the author's responses `round-<N>-response-<reviewer>.md`, and `ledger.md`. The ledger has one line for each review and for each time the author answered, oldest first:

```markdown
# Review ledger: 00.plan.md
- 2026-11-27 21:03 · round 1 · codex · reviewed · round-1-codex.md
- 2026-11-27 21:05 · round 1 · gemini · reviewed · round-1-gemini.md
- 2026-11-27 22:10 · round 1 · author · feedback addressed · round-1-response-codex.md, round-1-response-gemini.md
```

Work out your file name from the ledger and the file names, before you open any review file:

- `<reviewer>` is the name the request gives you. Otherwise it is the name you used for this document earlier in this session, or else the lowercase name of the agent you run as: `claude`, `codex`, `gemini`, `grok`.
- `<N>` is the round the request gives. Otherwise take the highest round in the ledger, and add one when that round has a `feedback addressed` line. A missing ledger starts at round 1.
- When `round-<N>-<reviewer>.md` already exists and you wrote it in this session, stop: reply that round `<N>` waits for the author's `feedback-get`. When someone else wrote it, another reviewer runs as the same agent: add `-2` to your name, then `-3`: `round-1-claude-2.md`.

## 2. Read

- The document in full, and every file it links.
- The material it builds on: the code at the current commit, or the skills, documents and data it names. Every claim the document makes about that material (a signature, a value, a behavior, a line reference) must be grounded in it: check each one against the source.
- The current documentation of each third-party service or library the document relies on. Check that it supports what the document claims, and whether it offers a more up-to-date approach.
- The other documents in the session folder. A plan answers to its spec, and a spec to its brainstorm.
- From round 2 on: your own earlier reviews, the author's responses to them, and what changed in the document since your last review. The response says what changed. When the document is under git, check it with `git -C <session folder> log -p -- <file>` and `git -C <session folder> diff -- <file>`.

When a claim can be measured, measure it: run the code, the tests or a probe from a temporary directory outside the repository. Delete what the run leaves in the repository, such as a cache folder.

## 3. What to look for

When your last review has a response from the author, re-review it (3b). Otherwise review in full (3a): that is every round-1 review, and the first review of a reviewer who joins later.

Keep focus on the document's goal. An improvement unrelated to that goal is scope creep, not a finding.

When the document or the request states a compatibility requirement, hold the document to it. Otherwise backward compatibility is not a concern: an API may change without a migration path.

### 3a. Full review

The document is a proposal, not a set of final decisions. Be skeptical. Challenge each decision that does not look thoroughly considered, including the ones in its Decisions section. Each objection, alternative or refinement you would argue for is a finding: state it plainly.

- Inconsistencies: inside the document, against the other documents in the session folder, or against the code.
- Weak assumptions, missed details and underestimated aspects: assumptions stated as facts, risks that nobody measured, inputs a user would plausibly send, error states, and edge cases that no test or acceptance criterion covers.
- Claims that the code or a third party's documentation does not support.
- Gaps, and parts that can be refined or simplified. Does the proposal solve the stated problem for the stated user? Is there a simpler approach?
- Over-engineering, premature optimisation, cargo cult refactoring and lava layering.
- For a plan: every requirement of the spec maps to a task, names and signatures match across tasks, and each test would fail if the behavior it claims to pin broke.

### 3b. Re-review

Re-review the feedback the author addressed. Take each point of your last review with the author's answer to it:

- Accepted: check that the document now does what you recommended, or solves the same problem another way. The point is fixed, or still open with what is missing.
- Rejected, or accepted in part: weigh the author's reason. Defend your position when it is strong enough, or when the counter-evidence does not convince you: give your reason, with new evidence where you have it. Push back where appropriate. Concede where the author is right.
- A downside of the chosen approach that no change can remove: state it as a known trade-off.

Then read the changes the author made since your last review. Each problem they bring in is a new finding: look for it as in 3a.

## 4. Write the review

The review holds these parts, in this order:

1. The title: `# Round <N> review of <the document's title>`.
2. One paragraph. It opens with the verdict as one bold sentence that says what to do next, such as **Revise the spec before planning.** or **Ready for implementation.** It then says what holds and what the most important point puts at stake, and links the document.
3. In a re-review, `## Earlier points`: one entry for each point your last review raised or kept open, in its order. Each says fixed, still open, held or conceded, and why. A held point answers the author's reason.
4. One `## <n>. <Severity>: <the change, as an instruction>` section for each finding, most severe first, for example `## 1. High: Round Retry-After up`. Each one says what is wrong, gives the evidence (a value, a scenario, a file and line), and recommends the change. It closes with links to the places it cites, relative to the review file: `../spec.md#decisions`, `../../../../src/limits.py#L12`.
5. `## Known trade-offs`: each downside that no change can remove, with the decision that causes it.
6. `## Outside this document`: points about the other documents in the session folder, each naming its document.

Include a part only when it has content.

Severity:

- **Critical**: as written, the work fails its goal, loses data or opens a security hole.
- **High**: an implementer would likely build the wrong thing, or an input a user plausibly sends breaks it.
- **Medium**: a gap or a weaker choice that will cost rework later.
- **Low**: a refinement; the document works without it.

Then add your line to the end of the ledger with a shell append, which leaves the other lines as they are:

```sh
cd <review subfolder>
[ -e ledger.md ] || echo '# Review ledger: <document file name>' > ledger.md
echo "- $(date '+%Y-%m-%d %H:%M') · round <N> · <reviewer> · reviewed · round-<N>-<reviewer>.md" >> ledger.md
```

Reply with the review's path and its verdict sentence.
