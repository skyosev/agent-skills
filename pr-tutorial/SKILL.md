---
name: pr-tutorial
description: Use when the user types /pr-tutorial, or asks for a tutorial, a step-by-step explainer or a walkthrough that teaches the new concept, package or architecture of a PR or branch to a reader who knows only the main branch. Makes one tabbed HTML artifact; each step adds one idea, shows its use, the real trimmed source behind it at a pinned commit, and real run output. For one page that explains what a PR changed and why, use html-pr.
argument-hint: "[PR number | PR URL | branch]"
---

# pr-tutorial

Teach the new concept of: $ARGUMENTS (a PR number, a PR URL or a branch; nothing means the current branch).

You write one HTML page that teaches the concept as a tabbed tutorial. Each step adds one idea to the steps before it. The reader knows the code on the main branch. Everything that the branch adds is new to the reader, the internals too.

html-pr explains what a PR changed, on one page. This skill teaches how the new thing works, step by step. If the user wants a review or a change summary, use html-pr.

## Needs

- `T=<this skill's directory>`. Node runs `$T/scripts/check.mjs`.
- The Artifact tool. Before you write the page, follow its contract: call `quickstart` with `intent: "other"`, or load the `artifact-design` skill. `$T/assets/template.html` already follows that contract (title, theme tokens, dark mode, pinned cdnjs script). Keep those parts.
- `agent-browser` for the screenshots in step 6. If it is missing, skip the screenshots and say so.
- Work in `D=<session scratchpad>/pr-tutorial/<repo>-<branch>`.

## 1. Freeze the commit and find what is new

```bash
HEAD=$(git rev-parse <branch>)          # for a PR: gh pr view N --json headRefOid
BASE=$(git merge-base origin/HEAD $HEAD)
git log --oneline $BASE..$HEAD           # what is new to the reader
git diff --stat $BASE..$HEAD
git worktree add --detach $D/wt $HEAD    # read code and run examples here only
git branch -r --contains $HEAD           # empty: the source links will 404
```

- Read code only in `$D/wt`. The main checkout can be at another commit and hold the user's edits.
- Every source link is `https://github.com/<owner>/<repo>/blob/<full HEAD SHA>/<path>#L<a>-L<b>`. A branch name in a link moves; a full SHA does not.
- If no remote branch holds HEAD, tell the user that the links do not open until the branch is pushed.

## 2. Plan the steps

Write the plan before any HTML: one line per step with its title, the names it adds, and the map parts it adds.

- **Start with the smallest set of interfaces and abstractions that shows the intent of the architecture and how the parts talk to each other.** Then add one concept per step. Each step builds on the steps before it and stays short.
- **Smallest set does not mean public API only.** The reader knows only the main branch, so the internals are new too. A tutorial that shows only usage leaves the reader with names and no model. Every step pairs its use with an "Inside the engine" block (step 3).
- **Grow one small example.** Take it from the branch's tests if one fits. Each step continues the code of the step before. The last step shows the real product code that uses the concept.
- **One map.** Draw the architecture once, as the SVG in the template. Each part gets `data-s="<step that adds it>"`; the page dims later parts and marks the parts of the current step.

## 3. Write each step

Copy `$T/assets/template.html` to `$D/tutorial.html`. Its step 1 shows every block, in order, with a comment on what each block holds. A step keeps that order and drops the blocks it has no use for.

Before you write the first step, read `$T/references/example-step.html`. It is a finished step that the user accepted after four rounds of feedback. It shows how much a step must explain. A step that follows the rules below but is much shorter than the example is probably too thin.

1. **The problem first.** Say which questions the concept answers, and why the reader needs the answer before the code. Then give a familiar analogy, mapped term by term ("a spreadsheet: a handle is the cell address, a pick is what you typed"). A step that says what a thing is, but not why, loses the reader.
2. **The use.** The next piece of the example, then its real output in an `.out` table.
3. **The design choice, compared.** When the design picks one of several usual ways, show a table: one column per alternative, one row per consequence (`.ok`, `.err`, `.amb`). Under it, a closed `details.alt` "The N ways in code" with code for each alternative, so the reader sees the failure, not only a cell that says "no". Mark each alternative that is not in the code "sketch · not in the code". When the failure only shows at run time (shared state, a race, a lost value), run the sketch and paste its output. When the usual fix for an alternative leads back to this design, show that too: "to fix B, you make one object per configuration; then the input box needs a name to find its object; that name is a handle". This step convinces the reader more than the table does.
4. **Concrete cases.** Before and after, with real output, and one sentence on what the rejected design does in the same case.
5. **Inside the engine.** An open `details.inside` with the real source that does this step, trimmed, and a link to its exact lines. Say "trimmed" in the link text when you cut lines.
6. **Keep this.** The rule the reader takes away, in the `.rule` box.

Code blocks: escape `<`, `>` and `&`. Write comments as `<span class="c">// …</span>` and new lines as `<span class="hl">…</span>`; the highlighter paints only the text around them. Set `data-lang` on the `code` element when the language is not TypeScript.

## 4. Names and context

- **Never open with undefined context.** The lead says what the package is and what it does. A first sentence such as "a run of the engine at a3f227e" names a commit and a term that the reader has not met.
- **The terms box defines each folder, package, branch and commit before the page uses it.** No bare SHA and no unexplained name ("the engine") anywhere.
- **Define every name at or before its first use**: function, type, parameter (`ctx`), field, error code, term. Add each to the step's "New" list. Before you finish a step, read its code and prose and look for each identifier in the "New" lists of this step and the steps before, or in the terms box.
- A forward reference "(step N)" is allowed only where the sentence makes sense without it.
- **Closed blocks do not define names for the open text.** The reader can skip a closed `details.alt`. A name that only a closed block defines is undefined for the text outside it. Define it in the open text first.
- **Sketches and folded code follow the same rule.** A sketch must not use a helper from a later step or a variable that it does not define. Use a plain value (`- 10`), or add one comment line that defines the name (`// catalog20: the server catalog with a-10 at 20 mm`).

## 5. Every output and claim is real

- Run each example against the code at HEAD: scratch scripts in `$D/run/` that import the real source from `$D/wt` by absolute path. Paste the output as it prints. Trim only with "…".
- Quote compiler errors from a real `tsc --strict --noEmit` run, with the code, for example `error TS2322: Type 'number' is not assignable to type 'string'.` Run the sketches too; a sketch output also comes from a run.
- Check every sentence that states a fact about the code against the source line that proves it. A plausible claim is not proof: one draft said "the browser does not send the values", and the code sends them.
- Keep a list of what you could not run or prove. It goes in the report.

## 6. Check and look

```bash
node $T/scripts/check.mjs $D/tutorial.html
```

It fails on unbalanced tags, an inline script that does not parse, a `[[FILL]]` placeholder, a tab without its panel, and a source link without a full SHA or with a second SHA. Fix each error.

Then take four screenshots and open each one:

```bash
export AGENT_BROWSER_SESSION=pr-tutorial
agent-browser set viewport 1280 900 && agent-browser open "file://$D/tutorial.html#step-1"
agent-browser wait --load networkidle
agent-browser screenshot $D/desk-light.png --full
agent-browser set media dark && agent-browser screenshot $D/desk-dark.png --full
agent-browser set viewport 390 844 && agent-browser screenshot $D/phone-dark.png --full
agent-browser set media light && agent-browser screenshot $D/phone-light.png --full
agent-browser close
```

Look for: text that overflows at 390 px, code without colors (the highlighter failed), a map part that does not dim, low contrast in dark mode. For a step other than 1, open `#step-N`.

## 7. Fresh review

Spawn one reviewer agent that has not seen your work. Give it the page path and this brief:

> Read the steps of `<path>` in order, as a reader who knows only the `<main branch>` branch of `<repo>`. Report per step: (1) names used before they are defined; (2) concepts with no "why"; (3) design choices where a comparison with the alternative, in code, would help; (4) confusing jumps or contradictions. Quote the sentence for each finding.

Check each finding against the page and the code before you act on it or relay it. A reviewer can be wrong.

## 8. Publish and report

Publish `$D/tutorial.html` with the Artifact tool. After the last pass, remove the worktree: `git worktree remove --force $D/wt`.

Deliver in passes, so the user can correct the depth and the style before they spread to every step:

- **A first draft:** write, check (sections 5–7) and publish steps 1 and 2 only. Ask the user if the depth and the style are correct. Then write the other steps.
- **A rewrite of many steps:** rewrite the worst steps first, publish them, and ask again before you do the rest.

Report in ASD-STE100 Simplified Technical English: short sentences, active voice, blunt and factual. Give:

- The artifact link, the pinned SHA, and the screenshot paths.
- The reviewer findings that you fixed, and the findings that you rejected, with the reason.
- What you did not run or prove, by name. Say "not verified" for each; do not soften it.
