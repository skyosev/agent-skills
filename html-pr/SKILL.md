---
name: html-pr
description: Use when the user types /html-pr, or asks for one HTML page that explains a pull request or merge request (what it built, how the parts fit, which decisions it took), so a reader does not have to rebuild it from the diff.
---

# html-pr

Explain this PR: $ARGUMENTS (a PR number, a PR URL or a branch; nothing means the current branch).

You write one linear HTML page. The runtime in this skill's `runtime/` folder draws it: `h2` sections, the contents rail, the blocks and the Comment sheet. `runtime/pack.mjs` checks the page and makes one file of it. The skeleton in step 3 is all the page structure you need: each `h2` makes a section and an entry in the contents rail, and the runtime adds the rest. The reader did not write the PR and has not read the ticket. Every fact about this repo on the page comes from two commits, BASE and HEAD.

`runtime/` is an unchanged copy of the html-plan runtime (anthropics/claude-plugins-community, commit 163301d, Apache-2.0, see `runtime/LICENSE`).

## Needs

`R=<this skill's directory>/runtime`. Node runs `$R/pack.mjs`.

- If `agent-browser` is not on `PATH`, draw every picture (step 3) and skip the page screenshots (step 7). Say so in the hand-over.

Work in one folder: `D=<session scratchpad, else ${TMPDIR:-/tmp}>/html-pr/<repo>-<n>` (for a branch, `<repo>-<branch>`). Run git and `gh` in the checkout of the PR's repo. Read code only through git (`git show $HEAD:<path>`), never from the working tree: it can be at another commit and hold the user's edits.

## 1. Freeze BASE and HEAD

GitHub:

```bash
gh pr view $N --json number,title,state,url,body,baseRefName,baseRefOid,headRefName,headRefOid,mergeCommit,commits,additions,deletions,changedFiles > $D/pr.json
```

- `state` MERGED: `BASE=baseRefOid`, `HEAD=mergeCommit.oid`. The page explains what landed. After a squash merge, the PR's own head commit is often not in the clone; you do not need it.
- `state` OPEN or CLOSED: `git fetch origin pull/$N/head`, `HEAD=$(git rev-parse FETCH_HEAD)`, `BASE=$(git merge-base <baseRefOid> $HEAD)`.
- A branch with no PR: `HEAD=$(git rev-parse <branch>)`, `BASE=$(git merge-base origin/HEAD $HEAD)`.

GitLab (`glab mr view $N --output json`): an open MR fetches `merge-requests/$N/head` and takes `diff_refs.base_sha` as BASE. A merged MR takes `merge_commit_sha` (else `squash_commit_sha`) as HEAD and its first parent as BASE.

Both SHAs must be full and local: `git cat-file -e $SHA^{commit} || git fetch origin $SHA`.

Check that the host and git agree on the files:

```bash
diff <(git diff --name-only $BASE $HEAD) <(gh pr diff $N --name-only | LC_ALL=C sort)
```

If the lists differ, stop and show both. GitLab: `glab mr diff $N --raw | grep '^diff --git'`.

If you got a PR number or URL and `gh` (or `glab`) fails, or the host does not know the PR, stop. Ask for the branch or for the two SHAs. Never explain the current branch in place of the PR the user named. If you got a branch and the host fails, go on with git, and put "No PR body or ticket: the host did not answer." under the `h1`.

## 2. Read

```bash
jq -r '.body' $D/pr.json
jq -r '.commits[] | "\(.messageHeadline)\n\(.messageBody)\n"' $D/pr.json
gh pr view $N --comments
gh api "repos/{owner}/{repo}/pulls/$N/comments" --jq '.[] | "\(.path):\(.line // .original_line) \(.user.login): \(.body)"'
git diff --stat $BASE $HEAD
git diff $BASE $HEAD
```

- The ticket: find its key in the title, the branch name or the body (`LAY-1141`, `#123`). Read it with the tracker tool you have (Linear `get_issue`, `gh issue view`). If no tool reads it, say so and quote the PR body.
- To find a line number: `git show $HEAD:<path> | grep -n '<symbol>'`. Use `$BASE` for the old code.
- If the diff changes a contract with another repo (an API, a generated client, a message), read that repo too. Name the integration pattern on the page ("the generated client follows the hub").

## 3. Write the page

Save it as `$D/<repo>-<n>.html`. Copy this skeleton. Keep the sections in this order. Leave out a section when the diff gives it nothing, as the comments say. For the attributes of each block, read `references/blocks.md` in this skill's directory.

```html
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>Upload Refusals by Reason</title>  <!-- a name, 2 to 4 words -->
<link rel="stylesheet" href="htmlplan.css">
<script src="htmlplan.js" defer></script>
<style>
  ol.steps { list-style: none; counter-reset: s; padding: 0; margin: 0 0 18px; }
  ol.steps > li { counter-increment: s; position: relative; padding: 0 0 6px 46px; margin: 0 0 22px; border-bottom: 1px solid var(--line-2); }
  ol.steps > li::before { content: counter(s); position: absolute; left: 0; top: 0; width: 30px; height: 30px; border-radius: 50%; background: var(--sunk); border: 1px solid var(--line); font: 600 12px/30px var(--sans); text-align: center; color: var(--ink-2); }
  ol.steps.why > li::before { background: var(--accent); border-color: var(--accent); color: var(--paper); }
  .loc { font: 12px/1.5 var(--mono); color: var(--ink-3); margin: 0 0 4px; }
  .loc b { color: var(--ink); font-weight: 500; }
  ul.checks { list-style: none; padding: 0; } ul.checks li { padding-left: 24px; position: relative; margin: 0 0 6px; }
  ul.checks li::before { content: "✓"; position: absolute; left: 2px; color: var(--green); font-weight: 700; }
</style>
<body>
<header>
  <p class="kicker">PR #257 · AbraxaGroup/monorepo · merged into main</p>
  <h1>Upload refusals, grouped by reason</h1>  <!-- the change, 3 to 7 words -->
  <p class="meta"><span>15 files</span><span>+280 −105</span><span>f0e5ba1 → 1b9d235</span></p>
  <div class="tldr"><p><!-- 40 words at most: the cause and what the user saw, then what the system now does --></p></div>
  <details class="thread"><summary>Why · LAY-1141</summary>
    <doc-quote via="linear" from="<author>" at="<date>" href="<ticket url>"><!-- the ticket, word for word, trimmed with … ; else the PR body; else the commit messages --></doc-quote>
  </details>
</header>
<main>

<h2>Before and after</h2>
<!-- One case with real values. A UI change (the diff changes what a screen of this repo draws): two doc-shot (or drawn doc-mock), BASE then HEAD.
     No UI: the input, then two .card in .cols with what a caller gets at BASE and at HEAD.
     A pure refactor: only the line "Nothing a caller sees changes." -->
<p>One drop on a full queue: three spreadsheets, one 30 MB scan and two small PDFs.</p>
<div class="cols">
  <doc-shot src="shot-base.png" caption="Before, at f0e5ba1: one line per file."></doc-shot>
  <doc-shot src="shot-head.png" caption="After, at 1b9d235: one entry per reason."></doc-shot>
</div>
<ul>  <!-- one line per behaviour change: its step, and its test or "no test" -->
  <li>A file over the size cap is refused for its size. <a href="#step-3">Step 3</a> · <a href="#test-2">test</a></li>
</ul>

<h2>How it fits</h2>
<!-- Only when the diff changes how parts relate: a new caller, a record that crosses parts, a moved responsibility.
     Groups only where the code has them. Each box links to its step.
     doc-flow: "+" new, "-" removed, "~" changed, on a box or an arrow. [#id] links a box. An indented line under a box adds detail.
     Then a Terms table, only when the PR adds or renames a domain term or uses two names for one. -->
<p>Three layers, one record across them: <code>RejectionGroup</code>.</p>
<doc-flow marks="new,removed,changed" caption="Tap a box to go to its step.">
<script type="text/plain">
~ q  = useDocumentQueue / addFiles() [#step-1]
~ va = validateAddition / one pass [#step-2]
+ gr = groupRejections / one entry per reason [#step-4]
group "State": q
group "Rule": va, gr
| q  | .  |
| va | gr |
q -> va : drop
q -> gr : refused
</script>
</doc-flow>
<table>
  <thead><tr><th>Term · in the code</th><th>Means</th></tr></thead>
  <tbody><tr><td><b>refusal</b> · <code>RejectedFile</code></td><td>A file the queue does not take. The code also calls it a rejection.</td></tr></tbody>
</table>

<h2>Walkthrough</h2>
<!-- Numbered steps in data-flow order. Each: file :lines at HEAD, one or two sentences, one exhibit (step 5). -->
<ol class="steps">
  <li id="step-1">
    <p class="loc"><b>use-document-queue.ts</b> :26–42</p>
    <p><code>addFiles</code> keeps the refusals as entries. Before, it joined them into one string.</p>
    <doc-code src="hunks/use-document-queue.diff" lines="34-46" diff file="apps/laytime/src/features/claims/creation/use-document-queue.ts"></doc-code>
  </li>
</ol>

<h2>Decisions</h2>
<!-- A choice between two ways that both work. None found: one line says so. -->
<ol class="steps why">
  <li>
    <p><b>Size before count.</b> A 30 MB file on a full queue is refused for its size: a free slot would not let it in. <a href="#step-3">Step 3</a></p>
    <p class="loc">Source: comment, file-constraints.ts:158</p>  <!-- or "Inferred" when no source says it -->
  </li>
</ol>

<h2>What the tests pin</h2>
<!-- New or changed test cases. No test changed: one line says so. -->
<ul class="checks">
  <li id="test-2">A file over the size cap is refused for its size, also on a full queue. <a href="#step-3">Step 3</a></li>
</ul>

<h2>Also in this PR</h2>
<!-- Every changed file that no step shows, test files and docs too. A row can group files under their common folder. -->
<div class="table-wrap"><table>
  <thead><tr><th>Files</th><th>What</th></tr></thead>
  <tbody><tr><td><code>libs/api-client/src/</code> (6 files) <small>−52</small></td><td><code>FormFile</code> left the generated client, to follow the hub.</td></tr></tbody>
</table></div>
<p>Not changing: the allowed types, the 10-file and 25 MB caps, and where the alert shows.</p>

</main>
</body></html>
```

### The pictures in "Before and after"

For a UI change, take real screenshots where the app runs. Give each side one attempt:

```bash
git worktree add --detach $D/wt-head $HEAD   # and $D/wt-base $BASE
```

1. In the worktree, install and start the app the way the repo says: a run skill, the README, the package scripts.
2. Reach the changed screen and capture it (the agent-browser commands in step 7, with `open http://localhost:<port>/<route>` and `screenshot $D/shot-head.png`).
3. If the install or the start fails, or the screen needs a login or data you cannot make, stop that side. Draw it as a `doc-mock` from the code at that SHA, with the caption "Drawn from the code at `<short sha>`; not a screenshot." Each side falls back on its own.
4. Stop every server you started, free its port, and run `git worktree remove --force` on each worktree.

## 4. Defaults

- 5 steps or fewer, 5 decisions or fewer, 8 boxes or fewer in 2 or 3 columns, approximately 350 words of prose.
- These are defaults, not limits. Every behaviour change in the diff goes on the page, in "Before and after" or in a step, even when it breaks a default.
- A behaviour that was true before the PR goes in the "Not changing" line. It gets no diagram, no code and no step.
- One exhibit per concept on the whole page. If "How it fits" shows the layers, no step shows them again.
- A decision needs a source: a code comment, a commit message, a test name, the PR body, the ticket or a review comment. Write it as "Source: <kind>, <file:line or who>". If no source says it, label it "Inferred", or leave it out.

## 5. Code on the page comes from git

- A changed part of a file: a hunk from git, never pasted or typed.

  ```bash
  mkdir -p $D/hunks
  git diff $BASE $HEAD -- <path> > $D/hunks/<name>.diff
  grep -n '^@@' $D/hunks/<name>.diff   # a hunk runs from its @@ line to the line before the next @@
  ```

  Cite it as `<doc-code src="hunks/<name>.diff" lines="<@@ line>-<last line>" diff file="<path>">`.
- New code: `<doc-code src="<path>" lines="a-b" ref="<HEAD, full SHA>">`.
- A replaced rule: two `doc-code` blocks, one under the other, `ref=<BASE>` with the caption "Before" and `ref=<HEAD>` with "After".
- `ref=` takes only BASE or HEAD, as a full SHA.

## 6. Prose

Write for a reader who did not write the PR, has not read the ticket, and gives the page a few minutes.

**ASD-STE100 Simplified Technical English (STE)** for all prose: the `.tldr`, step text, decisions, test lines, captions, pins and table cells.

- **Approved words only.** Use a word only if the STE dictionary approves it, and only with its approved meaning and part of speech. If you are not sure about a word, use the most common short word that has the same meaning.
- **Technical names and technical verbs are permitted.** Names from the code, product names, UI labels and units are technical names. Verbs of the field (*compile*, *deploy*, *merge*, *render*) are technical verbs.
- **Short sentences.** One topic for each sentence. A description has 25 words at most. A paragraph has 6 sentences at most.
- **Active voice.** Say who does what: "The worker claims the row." Not "The row is claimed."
- **Simple tenses.** Use the present, the past and the future. Do not write *has sent* or *is sending*. Do not use an *-ing* word unless it is part of a technical name.
- **`must` and `can`.** Use *must* for a rule and *can* for what is possible. Do not use *should*, *may* or *might*.
- **Noun groups of 3 words at most.** "The retry limit of the send worker." Not "the send worker retry limit setting".
- **Full grammar.** Keep *the*, *a* and *an*. Do not use contractions, idioms, metaphors or jokes.

| Do not write | Write |
|---|---|
| utilize, leverage | use |
| perform, carry out | do |
| ensure, verify, check (as a verb) | make sure |
| demonstrate, indicate | show |
| commence, begin · terminate | start · stop |
| obtain · provide | get · give |
| prior to · in order to | before · to |
| however · additionally | but · also |
| about 50 | approximately 50 |

These are not STE and stay as they are: quoted words in a `doc-quote`, code, and the text in a screenshot or mock.

**Names**

- Use the names that the code and the UI use, so the reader can search for them. If the repo has a `GLOSSARY.md`, use its terms.
- Give each concept one name and keep it. "Working hours" and "working time" for one thing make the reader wonder whether they are two things.
- Do not reuse ticket titles or spec phrases as if the reader knows them. Say what they mean.
- Prefer plain words to new terms. A term the page uses again goes in the Terms table.
- Write each abbreviation out, or use its plain name ("DH" → "the hub"). Keep only abbreviations the code or the UI shows.

**Content**

- **The `.tldr`:** the cause in plain words, then what the user saw because of it; then what the system now does, as a rule, so the reader can predict a case the page does not show.
- **Observable outcomes.** State a problem as what the user sees, where, what they expected, and what they got. Not "An exclusion row reports a period that its own rule does not define." But "The holiday row ends at Sat 10:43, the next SOF event. The holiday ends at Sat 08:00."
- **No abstract noun without a referent.** For "rule", "period", "behaviour", "logic", "handles", "edge case": say which one and what it does, or cut the sentence.
- **A change reads as a change, in positive form.** "Laytime now stops at 17:00", not "Laytime no longer fails to stop". "Now" marks what is new.
- **Lead each section with its answer.**
- **Cut filler** ("just", "basically", "note that"). Cut a hedge unless it carries real uncertainty; then say what is not verified.

**Three passes, in this order:**

1. **Facts.** Check each sentence against the diff and the code at BASE and HEAD. Note what you corrected and what you could not verify.
2. **Clarity.** Read the page as the reader. Rewrite each sentence the reader could not picture or act on. A rewrite replaces the sentence; it does not add an explanation beside it. Start with the `.tldr`, then each sentence that paraphrases the ticket, then each sentence with an abstract noun.
3. **Length.** For each sentence, ask: does a sentence, a picture or a code block above already say it? Would the reader miss it if it went? Cut it unless the answers are no and yes. Cut a case that the `.tldr` rule already predicts.

## 7. Pack and look

```bash
node $R/pack.mjs $D/<repo>-<n>.html --root <checkout> --root $D
```

- Every "filled … from <checkout>@<sha>" line must name BASE or HEAD. A line filled from `hunks/` names no commit; step 5's `git diff` is its source.
- A line "no git ref … using the plain file" is an error: pack read the working tree. Fix the `ref=`.
- Fix every error. Never drop a citation to get a clean pack.
- The prose warning ("words of prose … ≤ ~30 per block") and the paragraph warning ("paragraph over 40 words") come on almost every html-pr page. Pack counts the step, decision and test lists as prose, and each list item as one paragraph. Make the length pass of step 6 once, pack again, and keep the warnings.
- Fix each other warning once, or keep it. Name every warning you keep in the hand-over.

Then look at the page:

```bash
export AGENT_BROWSER_SESSION="$(agent-browser session id --scope worktree --prefix html-pr)"
agent-browser set viewport 1280 900
agent-browser open "file://$D/<repo>-<n>.packed.html"
agent-browser wait --load networkidle
agent-browser screenshot $D/page-desk.png --full
agent-browser set viewport 390 844
agent-browser screenshot $D/page-phone.png --full
agent-browser close
```

Open both images once. Fix a clipped mock or picture, and arrows that cross labels. Take the screenshots again only if you changed the page.

## 8. Hand over

- The path of `$D/<repo>-<n>.packed.html` and of the two page screenshots.
- BASE and HEAD.
- The files whose code is inside the page: the last lines of the pack output, with each `hunks/<name>.diff` replaced by the path in its `file=`.
- Which pictures are drawn, and why the screenshot failed.
- The pack warnings you kept.
- The facts you corrected, and the facts you could not verify.

Publish the page as an artifact only when the user asks.
