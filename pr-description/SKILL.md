---
name: pr-description
description: Write or rewrite a pull request description that gives the overview of the PR in as few words as clarity allows. Opens with a TL;DR (Problem — the cause, then what the user sees; Solution; one Before / After Example), keeps only what a reader cannot get from the diff, folds reference that only some reviewers need into a <details> block, and reports what it cut. Use whenever you create a PR or MR, when the user asks to write, rewrite, tighten, shorten or clean up a PR description or body, or says a PR description is too long, vague or hard to scan.
---

# PR Description

A PR description is the overview, not the record. The diff, the tests and the ticket hold the detail. The description holds what a reader needs to understand the purpose of the PR and to judge it, and nothing the reader can get faster from the diff.

Rewrite the description of the PR named in the arguments. With no argument, use the current branch's PR (`gh pr view --json number,title,body`). If the PR has no description, or you are about to create the PR, write one from the diff and the commits against the base branch. Read the diff (`gh pr diff`, or `git diff <base>...HEAD` before the PR exists) in every case: you check every fact against it.

## Reader

Write for a reviewer who has not read the ticket, the spec, the brainstorm, or this conversation, and who gives the description two minutes before opening the diff.

Before you draft, write the reader line: who reads this description, and which words they already know (the terms of their trade, the product's names, the stack). Add a second reader who must act on it, such as a domain expert who signs off. Every other word is new to them: the names of internal files, tools, conventions, test sets and scores, ticket titles, spec phrases, and words this conversation made up.

- Give a new word its meaning in parentheses where it first appears, or say the plain thing instead. Define it only when the description uses it again.
- Use the names the code and the UI use, so the reader can search for them. A code name does not explain itself: it is a new word like any other.
- Give each concept one name and keep it. "Working hours" and "working time" for one thing make the reader wonder whether they are two things. When the code, the ticket and a tool each name it differently, use the name the reader already uses (the repo's `GLOSSARY.md`, else the ticket), give the code's name once in parentheses, and keep that name in every PR this one links to.
- Number a list only when another sentence refers to its items by number. Cite a numbered list from outside ("ruling 4") by its own numbers.
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

1. **Problem:** one or two sentences, general: the cause in plain words, then what the user sees because of it. Not a single case. When the PR changes something the reader may not know (test data, a tool, a convention), first say in one sentence what it is and what it is for. "The user" is then whoever uses it, such as the person who reads the test score.
2. **Solution:** one or two sentences, general: what the system now does. State it as a rule, so the reader can predict any case from it.
3. **Example:** one case with real values (times, names, amounts), as Before / After of what the user sees. Before shows the Problem and After shows the Solution: pick the case that shows this most clearly, and among such cases the one where a reader would guess wrong. A case that goes the other way belongs under Risk. Give only the values the case needs.

Problem and Solution alone must tell the reader the purpose of the PR. The Example only makes it concrete. A small `diff` sketch of the change belongs in the TL;DR; when a later screenshot shows the same, keep the sketch and let the screenshot carry the detail.

### Optional sections

Add a section only when you can name the reader who needs it and the TL;DR does not already serve that reader. Visible:

- **What other repos must do**: the change another service, the front end or another team must make, with the file or field. Check each request against that repo first; drop the ones already done.
- **Risk**: a change that is hard to undo (migration, deleted data, removed API field), or one that reaches further than the diff suggests (other screens, other consumers).
- **Please confirm (who)**: what a named person must decide before merge, as a numbered list at the end of the TL;DR. Each item is one statement with real values that they can answer with yes or no. An open question becomes the statement of what the PR does now. Above the list, say whether they must run anything and where the values of each item come from. The reasons go in the fold, numbered to match.
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

1. **Facts.** Check each claim against the diff. A claim the diff cannot show (the state of a test, another repo, a measured number, what happened before) needs its own check, which you name, or it goes. Compare each count with the list or table it counts. Note what you corrected and what you could not verify.
2. **Clarity.** You cannot read your own draft as the reader: you know what every word means. Dispatch a cold reader: a fresh subagent that gets the path of the draft and the reader line, and no diff, ticket or conversation. Ask it to read only that file and to report:
   - the problem and the change in its own words, and which part of that it guessed;
   - every word it needed and the text did not explain, with the sentence;
   - every sentence it read twice;
   - words that may name one thing;
   - numbers or claims that do not agree;
   - what the text asks whom to do before merge.

   Tell it to list every case and to suggest no rewrite. Then act on each finding: fix it, or skip it because the reader line covers the word. A rewrite replaces the sentence; it does not add an explanation beside it. If the fix needs a new term, use a plain word instead. Dispatch a second cold reader only when the first one restated the problem or the change wrongly. When you cannot dispatch a subagent, list every noun the draft uses for a thing in the project, and beside each the sentence that says what it is; a noun without such a sentence is a finding.
3. **Length.** For each sentence, ask: does an earlier sentence or term already say or imply it? Can the reader get it faster from the diff? Would the reader miss it if it went? Cut it unless the answers are no, no, yes. Then apply the Solution to each case the description lists: a case it already predicts is a repeat, so cut it unless it is the Example. Then check the fold line: move to the visible part each folded fact that a reviewer must act on before merge, and fold each visible section that only some reviewers need. If the visible part is still longer than one screen (about 300 words), check that each visible optional section names its reader. This is a signal to check, not a limit: a PR with two fixes may need more.

A rewrite of a short description that already passes these checks stays about as long as it was. Each sentence you add must fix a wrong or missing fact, not restate one.

Clarity adds words; length cuts them. The balance is right when the TL;DR alone lets a reader predict the PR's effect on a case it does not list, and no sentence can go without the reader losing a fact.

## Output

1. Write the draft to a file in the scratchpad.
2. Show the user:
   - the reader line, and the clarity list: one line per finding of the cold reader that you fixed (**before → after**), and the count you skipped;
   - for a rewrite, the cut list: each fact from the old description that you dropped, one line each, with the reason (in the diff, repeats X, history, no reader);
   - any fact you corrected or could not verify;
   - the word count, old → new, for the visible part and the fold;
   - the path to the draft.
3. The visible part is the user's promise to the reviewer that it is worth their time. Show it to the user word for word and ask them to approve or edit it. Apply their edits to the draft.
4. Only after the user approves, create the PR with the draft as its body (`gh pr create --body-file <draft>`). Update an existing PR (`gh pr edit <n> --body-file <draft>`) only when the user says so.
