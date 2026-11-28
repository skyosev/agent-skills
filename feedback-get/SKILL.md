---
name: feedback-get
description: Use when the reviews of a brainstorm.md, spec.md or implementation plan you wrote are ready and you must address the feedback.
argument-hint: "[document or session folder] [request]"
---

# Feedback Get

Arguments: `$ARGUMENTS`. The first word is the document, or the session folder that holds it. When the arguments name no document, take the one you wrote or revised in this session. The rest is the request. An instruction in the request outranks this skill.

You are the document's author. Other agents reviewed it with `feedback-give`. You read their reviews critically, change the document for the points you accept, and answer each reviewer in a file of its own. A review is advice: accept a point on its evidence, and state plainly where you disagree.

## 1. Find the reviews

The reviews are in a subfolder beside the document: `review-brainstorm/` for `brainstorm.md`, `review-spec/` for `spec.md`, `review-plan/` for a plan (`00.plan.md` and its task files). Each review is `round-<N>-<reviewer>.md`. Each of your answers is `round-<N>-response-<reviewer>.md`, in the same subfolder.

Answer every review that has no response file yet. When none is left, say so and stop.

The subfolder's `ledger.md` logs each review and each time you answered, oldest first:

```markdown
# Review ledger: 00.plan.md
- 2026-11-27 21:03 · round 1 · codex · reviewed · round-1-codex.md
- 2026-11-27 22:10 · round 1 · author · feedback addressed · round-1-response-codex.md
```

When the ledger has no line for a review file, append that line now, dated by the file's time (`date -r <file> '+%Y-%m-%d %H:%M'`). When the ledger is missing, start it with the title `# Review ledger: <document file name>`.

## 2. Read

- Each review you answer, in full. From round 2 on, also that reviewer's earlier reviews and your responses to them.
- The document, and the sources each point cites: the code, the other documents in the session folder, a third party's documentation. Check every claim of a review against its source. When a claim can be measured, measure it: run the code, the tests or a probe from a temporary directory outside the repository, and delete what the run leaves in the repository.

## 3. Decide each point

Decide each point: accepted, accepted in part, or rejected. In a re-review, the points are the earlier points it marks still open or held, its new findings and its known trade-offs. A point it marks fixed or conceded needs no answer.

- Accept a point when its evidence holds and the change serves the document's goal.
- Reject a point when its evidence does not hold, or when the change is over-engineering, premature optimisation or scope creep. Keep the document focused on its goal.
- Backward compatibility is not a concern unless the document or the request states a compatibility requirement: an API may break, without a deprecation flag or a migration path.
- When reviewers recommend different changes for one problem, choose one.
- A known trade-off: accept it and record it in the document beside the decision that causes it, or show the change that removes it.
- The user decides a point that allows more than one valid decision, a borderline call, and a point you would reject a second time. Collect these and ask them together before you change the document: with AskUserQuestion when you have it, else in your reply, and wait for the answer. Give each option with its pros and cons, and your recommendation.

## 4. Change the document

Apply each accepted point and each decision of the user. Answer each open question of the document that the reviews, your checks or the user now settle. Write each change in the document's own terms, as a decision with its reason. The document names no reviewer and no review.

## 5. Answer each reviewer

Write one response file for each review you answer: `round-<N>-response-<reviewer>.md`, with the round and the reviewer name of that review.

- The title: `# Round <N> response to <reviewer>`.
- One `##` section for each point, in the review's order, headed with the point's number and heading as the review gives them. It opens with **Accepted**, **Accepted in part** or **Rejected**, then gives your reason and what the document now says, with a link to the place.
- Prose and lists only.

Each reviewer reads only its own reviews and responses, so that no reviewer anchors on another. Write each response for its reviewer alone: it names no other reviewer and none of their points. Where a change made for another review touches this point, say what the document now does.

Then append one line for each round you answered to the end of the ledger:

```sh
echo "- $(date '+%Y-%m-%d %H:%M') · round <N> · author · feedback addressed · <response files, comma-separated>" >> <review subfolder>/ledger.md
```

## 6. Report

Reply with, for each reviewer: the path of its response file, and in one or two sentences what you accepted and what you rejected. Then the next step: run `feedback-give` in each reviewer's session for the next round.
