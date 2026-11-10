---
name: pr-description
description: Write or rewrite a pull request description that gives the overview of the PR in as few words as clarity allows. Opens with a TL;DR (Problem — the cause, then what the user sees; Solution; one Before / After Example), keeps only what a reader cannot get from the diff, folds reference that only some reviewers need into a <details> block, and reports what it cut. Use whenever you create a PR or MR, when the user asks to write, rewrite, tighten, shorten or clean up a PR description or body, or says a PR description is too long, vague or hard to scan.
---

# PR Description

A PR description is the overview, not the record. The diff, the tests and the ticket hold the detail. The description holds what a reader needs to understand the purpose of the PR and to judge it, and nothing the reader can get faster from the diff.

Rewrite the description of the PR named in the arguments. With no argument, use the current branch's PR (`gh pr view --json number,title,body`). If the PR has no description, or you are about to create the PR, write one from the diff and the commits against the base branch. Read the diff (`gh pr diff`, or `git diff <base>...HEAD` before the PR exists) in every case: you check every fact against it.

## Reader

Write for a reviewer who has not read the ticket, the spec, the brainstorm, or this conversation, and who gives the description two minutes before opening the diff.

- Do not reuse ticket titles or spec phrases as if the reader knows them. Say what they mean.
- Prefer plain words to new terms. Define a term, in parentheses where it first appears, only when the description uses it again.
- Give each concept one name and keep it. "Working hours" and "working time" for one thing make the reader wonder whether they are two things.
- Use the names the code and the UI use, so the reader can search for them. If the repo has a `GLOSSARY.md`, use its terms.
- Write each abbreviation out, or replace it with its plain name ("DH" → "the hub"). Keep only abbreviations the code or the UI shows.

## Shape

Keep the repo's title format (look at its recent merged PRs). Do not change the title unless the user asks.

```markdown
<one sentence per merge constraint, only when one exists: deploy order, stacked on #N, required migration; the constraint and its reason, nothing the TL;DR says>
<ticket link>

## TL;DR

**Problem:** …
**Solution:** …
**Example:** …
- Before: …
- After: …

<visible optional sections>

<details>
<summary><what the block holds, e.g. "Side effects, known gaps, call tree"></summary>

<folded optional sections>

</details>
```

The visible part is the overview: a reviewer who never opens the fold must still know the purpose of the PR and everything they must act on before merge. The `<details>` block holds reference that only some reviewers need. Its summary names the content, so a reviewer can decide whether to open it; never use a model or tool name as the summary. Leave a blank line after `</summary>` and before `</details>`, or GitHub and GitLab show the Markdown inside as raw text. With nothing to fold, leave out the block.

### TL;DR

1. **Problem:** one or two sentences, general: the cause in plain words, then what the user sees because of it. Not a single case.
2. **Solution:** one or two sentences, general: what the system now does. State it as a rule, so the reader can predict any case from it.
3. **Example:** one case with real values (times, names, amounts), as Before / After of what the user sees. Pick the case that shows the change most clearly, or the one where a reader would guess wrong. Give only the values the case needs.

Problem and Solution alone must tell the reader the purpose of the PR. The Example only makes it concrete. A small `diff` sketch of the change belongs in the TL;DR; when a later screenshot shows the same, keep the sketch and let the screenshot carry the detail.

### Optional sections

Add a section only when you can name the reader who needs it and the TL;DR does not already serve that reader. Visible:

- **What other repos must do**: the change another service, the front end or another team must make, with the file or field. Check each request against that repo first; drop the ones already done.
- **Risk**: a change that is hard to undo (migration, deleted data, removed API field), or one that reaches further than the diff suggests (other screens, other consumers).
- **Screenshots** of a visual change, each with a one-line caption that says what to look at.
- Any section the repo's PR template or AGENTS.md requires.

Folded:

- **What else changes**: behaviour the reader would not predict from the Solution: a side effect, a second fix, a case where the rule surprises. One bullet each.
- **Known gaps**: what the PR knowingly leaves broken, as the outcome a user sees, and the follow-up.
- Structural views larger than the TL;DR sketch (writing rule 6).

The fold is for reference, not for what you would otherwise cut. Leave out, in both parts, what the diff, the commits or CI already show, and what no reader acts on:
- file-by-file change lists, test lists, golden-file names, counts of tests that passed;
- refactors with no visible effect: one line at most ("`X` moved to `Y`; output unchanged");
- history: what was tried, how the bug was found, earlier review rounds;
- a table or list of cases that the Solution sentence already decides;
- links to Claude sessions.

## Writing rules

1. **Observable outcomes.** State a problem as what the user sees, where, what they expected, and what they got.
   - Bad: "An exclusion row reports a period that its own rule does not define."
   - Good: "The holiday row ends at Sat 10:43, the next SOF event. The holiday ends at Sat 08:00."
2. **No abstract nouns without a referent.** "Rule", "period", "behaviour", "semantics", "logic", "handles", "defines", "edge case": say which one and what it does, or cut the sentence.
3. **No figurative language.** Write the literal claim.
4. **ASD-STE100 where it fits.** Active voice, one idea per sentence, sentences under 25 words.
5. **Positive form; a change reads as a change.** "Laytime now stops at 17:00", not "Laytime no longer fails to stop". "Now" marks what is new; "should" marks a follow-up that is not done yet.
6. **Structure over prose.** When the content is structural, pick the smallest view that shows the change, and keep only the calls, files, props or states the point needs:
   - a `diff` of the shape that changes, matched to the topic: pseudocode for logic, a call tree for control flow, a component tree for UI, a shallow file tree for a move;
   - an ASCII diagram (`hub ──► calculator ──► claim page`) when the change is in who calls whom; Mermaid only when the flow has more steps or branches than ASCII shows clearly;
   - a table when cases differ on two axes.

   Lead each section with its answer. Keep a list to five items; group and rank longer ones, most important first.
7. **Zinsser:** simplicity, brevity, clarity, humanity. Cut filler: "just", "basically", "note that", "in order to", "it is worth mentioning". Cut a hedge ("perhaps", "might", "could possibly") unless it carries real uncertainty; then say what is unverified.

## An example

The top of a calculator PR, after the length pass:

> Deploy to dev before hub MR !573 merges: its test requires the hub's default for each stoppage to equal the calculator's.
>
> **Problem:** When the charter party (CP) says nothing about waiting for tide or mooring, the calculator counts that time in full, but the hub counts it only while cargo is worked. So a request with no value for these stoppages uses up laytime that the hub would not count.
>
> **Solution:** The calculator's default for `WAITING_FOR_TIDE` and `MOORING` becomes the hub's: laytime counts the time only while cargo is worked, and demurrage counts it in full.
>
> **Example:** CFL Proud waits 3 hours for the tide after laytime started. The request has no value for `WAITING_FOR_TIDE`.
> - Before: the 3 hours count as laytime. Demurrage is EUR 8,967.60.
> - After: they do not count. Demurrage is EUR 8,248.85.

Why it works:
- The merge constraint comes first, because it asks the reader to act.
- The Solution is a rule. The reader can work out every mix of laytime or demurrage, cargo worked or not.
- The first draft also had a four-row table of exactly those mixes. The Solution decides every row, so the table went.
- The Example gives one ship, one wait and one amount, not the voyage timeline.

## Check before you hand it over

Three passes, in this order:

1. **Facts.** Check each claim against the diff. Note what you corrected and what you could not verify.
2. **Clarity.** Read the draft as the reader above. List each sentence the reader could not picture or act on, and rewrite it. A rewrite replaces the sentence; it does not add an explanation beside it. If the fix needs a new term, use a plain word instead. Check the TL;DR first, then each sentence that paraphrases a ticket or spec, then each sentence with a word from writing rule 2.
3. **Length.** For each sentence, ask: does an earlier sentence or term already say or imply it? Can the reader get it faster from the diff? Would the reader miss it if it went? Cut it unless the answers are no, no, yes. Then apply the Solution to each case the description lists: a case it already predicts is a repeat, so cut it unless it is the Example. Then check the fold line: move to the visible part each folded fact that a reviewer must act on before merge, and fold each visible section that only some reviewers need. If the visible part is still longer than one screen (about 300 words), check that each visible optional section names its reader. This is a signal to check, not a limit: a PR with two fixes may need more.

A rewrite of a short description that already passes these checks stays about as long as it was. Each sentence you add must fix a wrong or missing fact, not restate one.

Clarity adds words; length cuts them. The balance is right when the TL;DR alone lets a reader predict the PR's effect on a case it does not list, and no sentence can go without the reader losing a fact.

## Output

1. Write the draft to a file in the scratchpad.
2. Show the user:
   - the clarity list, one line per sentence (**before → after**);
   - for a rewrite, the cut list: each fact from the old description that you dropped, one line each, with the reason (in the diff, repeats X, history, no reader);
   - any fact you corrected or could not verify;
   - the word count, old → new, for the visible part and the fold;
   - the path to the draft.
3. The visible part is the user's promise to the reviewer that it is worth their time. Show it to the user word for word and ask them to approve or edit it. Apply their edits to the draft.
4. Only after the user approves, create the PR with the draft as its body (`gh pr create --body-file <draft>`). Update an existing PR (`gh pr edit <n> --body-file <draft>`) only when the user says so.
