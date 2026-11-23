---
name: pr-comments
description: Put a finished code review on a GitHub pull request or GitLab merge request as draft comments on the diff, for you to edit and submit.
disable-model-invocation: true
---

# pr-comments

Put this review on the pull request as draft comments: $ARGUMENTS (a PR or MR number or URL, then the review: a file path or an artifact link). With no review named, use the review in this conversation. With no pull request named, ask.

You create drafts only: one pending review on GitHub, draft notes on GitLab. Only the user sees the drafts, and the user submits the review. You never publish, approve or request changes.

`P="python3 <this skill's directory>/scripts/post_drafts.py"`

## 1. Read the pull request

```bash
$P threads <pr>   # the head commit, the title and description, every existing thread, your own drafts
$P diff <pr>      # the diff that the comments are checked against
```

## 2. List the findings

A finding is one problem with its reason and its fix. One finding becomes one comment.

- The verdict becomes the `summary`: two or three sentences to the author on whether the change can merge and the main reason. A review with no verdict gets no summary.
- Other sections that are not findings (scope, known trade-offs, filtered-out lists) become no comment.
- A finding that an open thread or one of your drafts already raises becomes no comment, also when it adds a fix. It goes in the report with that thread's place.

## 3. Place each finding

Find the code that the finding quotes in the head commit that `threads` printed, and take the line number from there. If the local checkout is at another commit, read files with `git show <head>:<path>`. The number in the review is a hint: the branch can have moved since the review.

| The finding is about | Comment |
| --- | --- |
| lines of the new file that the diff shows | `path`, `line` |
| lines that the change removed | `path`, `old_line`, numbered as in the old file. The comment stays there, also when the fix goes in other lines |
| a line of a changed file that the diff does not show | GitLab: `path`, `line`. GitHub: `path` only, and the text names the line and says the fix in words |
| a file outside the diff that a changed line breaks | `path` and `line` of that changed line; the text names the other file and line |
| nothing in the diff where a fix can start: a missing requirement, missing tests, the scope or the description of the change | `body` only: a general comment |

A finding with several places, in one file or in several, is one comment on the place where its fix starts. Its text names every other place as `path:line`, with the path from the repository root: `post` turns each into a link to that line.

A finding that quotes several lines covers all of them: `line` or `old_line` is the last quoted line, and `start_line` is the first, counted in the same file.

On GitHub the general comments join the summary in the text of the pending review; on GitLab each is a draft note of its own.

## 4. Write each comment

```
**<label> (<decoration>):** <the problem in one or two sentences; for an `issue`, what a person or a caller sees go wrong>

**Example:** <one case with real values: what was done, what was expected, what came out>

**Cause:** <why it goes wrong, with the evidence that the review gives>

**Fix:** <the change in words>   (or a suggestion block in place of this paragraph)

**Trade-off:** <what the fix costs>
```

The Example, Cause, Fix and Trade-off paragraphs exist only when the review gives one: a finding with no case that has values has no Example paragraph, a finding whose first sentence already says the cause has no Cause paragraph, a finding with no fix has no Fix paragraph, and "Trade-off: none" gives no Trade-off paragraph.

Cases that differ on two things (a request and a state, an input and a result) go in a table.

A comment with more than about 300 words folds what only the person who makes the fix needs into a `<details>` block: the rules for corner cases, the callers to change, the list of tests. The first sentence, the Example, the Cause and the Fix in its shortest form stay outside the block. The summary of the block names its content. Leave a blank line after `</summary>` and before `</details>`, or the Markdown inside shows as raw text.

| Label | Use it when |
| --- | --- |
| `issue` | the code is wrong or will fail |
| `suggestion` | the code works and the review proposes a better way |
| `question` | the review cannot decide without an answer from the author |
| `nit` | the point is small and local: a name, a comment, a format |
| `consideration` | the review names a risk or trade-off and asks for no change |

The decoration is `(blocking)` for a finding in the highest severity group of the review (must-fix, critical, blocker) and for a missing requirement, and `(non-blocking)` for the rest. A `question` has no decoration.

The reader is the author of the change. The author knows the code: its identifiers, and the words that its comments and its UI use. The author has not seen the review, and reads each comment alone, in its own thread.

- Keep the facts, the evidence and the fix of the review. Every claim in the comment comes from the review. The one addition you can make is what you checked in the head commit: a place (`path:line`), such as the caller of a renamed function, or what the code does today where the review proposes a change.
- Keep the facts, not the words. The Reader section and the Writing rules of the `pr-description` skill (`../pr-description/SKILL.md`, from this skill's directory) apply to every comment. A word that the review made up for a thing is new to the author: use the name that the code or the UI gives the thing, or say the plain thing. Give each thing one name in all comments.
- A claim about the pull request itself (its title, its description, its commits) must hold for the pull request as `threads` and `git log` show it now. The review can be older: correct the claim, or drop it.
- Each comment stands alone:
  - Replace each reference to another finding ("finding 3") with what that finding says.
  - When a comment uses a thing that another comment proposes (a new function, a field, a state), it says in one sentence what the thing is, and names that other comment by its place ("the review comment on `path:line`").
  - When the fix of a comment works only after the fix of another comment, it says what holds in the code today.
  - Two comments on different problems do not describe them with the same words.
- A sentence that speaks to the person who asked for the review ("the findings you supplied") speaks to the author instead, or goes.
- Inline code is for names: an identifier, a path, a short value. A line of code, an error message or an output that the comment quotes stands in a code block of its own.
- Quote code only from other places: the diff already shows the commented lines.

A suggestion block holds the full new text of the commented lines, with their indentation. An empty block deletes them. Use one only when the review gives the exact replacement and the code still works after that block alone is applied. Say every other fix in words: a rename with callers elsewhere, a fix that needs a second edit.

## 5. Check that the author can read the comments

You know what every word means, so you cannot read the comments as the author does. Write the summary and all comments to one file, each under a line with its place. Then dispatch one cold reader: a fresh subagent that gets the path of that file and the reader line, and no diff, review or conversation.

The reader line says who the author is and which words the author knows: everything in backticks, the words that the code's comments and the UI use, the terms of the trade, and the linked tickets. Without this the cold reader reports every name in the code.

Ask the cold reader to report, for each comment:

- the problem and the fix in its own words, and which part of that it guessed;
- every word it needed and the text did not explain, with the sentence;
- words that may name one thing, in the comment and across the comments;
- claims or numbers that do not agree, in the comment and across the comments;
- what the comment asks the author to do.

Tell it to list every case and to suggest no rewrite. Then act on each finding: fix it, skip it because the reader line covers the word, or report it because the review itself holds the disagreement (two findings that ask for different things). A fix replaces the sentence; it does not add an explanation beside it, and it changes no fact. When you cannot dispatch a subagent, list every noun that the comments use for a thing in the project and that is not an identifier, and beside each the sentence that says what it is; a noun without such a sentence is a finding. Dispatch a second cold reader only when the first one restated a problem or a fix wrongly.

## 6. Check, then create the drafts

Write `comments.json`, one object per comment with the keys from step 3:

````json
{"summary": "**Do not merge yet.** The export drops the last page of every result, and no test has more than one page.",
 "comments": [
  {"path": "export/pager.py", "line": 17,
   "body": "**issue (blocking):** The export never returns the last page.\n\n`range(1, pages)` stops one page early: a result of 3 pages returns 2. The spec says \"The export contains every row.\"\n\n```suggestion\n    for page in range(1, pages + 1):\n```"},
  {"path": "export/pager.py", "start_line": 30, "old_line": 33, "body": "..."},
  {"body": "..."}]}
````

```bash
$P post <pr> comments.json --dry-run   # checks every comment against the diff, writes nothing
$P post <pr> comments.json             # creates the drafts
```

Run the real `post` after the dry run accepts every comment, and one time only: a second run creates every draft again. If it reports failed comments, post those alone.

## 7. Report

Give the user one table with a row per finding: its label, and its place or the reason it has no comment. Then give:

- one line for each finding of the cold reader that you fixed (before → after), and the count that you skipped;
- each claim of the review that you corrected or dropped, with the reason;
- each disagreement between findings that the review itself holds;
- the link that `post` printed, and that nothing is published until they submit the review there.
