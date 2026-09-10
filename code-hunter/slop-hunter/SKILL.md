---
name: slop-hunter
description: |
  Use when reviewing Go, Python, or TypeScript code for AI-generated noise before merging
  AI-assisted changes, cleaning up a branch after heavy AI pair-programming, enforcing
  project conventions on new contributions, or reducing review noise. Defaults to the
  branch diff.

  Covers redundant comments, verbose documentation, style drift from the project's own
  conventions, trivially dead code, hedging and narration, and Go's unnecessary error
  wrapping.
disable-model-invocation: true
---

# Slop Hunter

Audit code for **slop** — text in a source file that carries no information for a reader: comments restating code,
docs restating signatures, style that breaks the project's own conventions, commented-out code, bare lint
suppressions, hedging, narration. Goal: **the code reads as if a careful human wrote it in this project's idiom.**

Supports Go, Python, TypeScript via per-language reference files.

The skill is framed as "AI-generated noise" because that is where slop comes from in practice. The per-finding test
is "is this noise?", never "did an AI write this?".

**Not covered (owned by other hunters):** missing "why" comments, stale or false comments, and the content quality
of public docs (→ doc-hunter); comments over non-trivial code (→ smell-hunter, Comments as Deodorant); live but
unreachable logic, unused functions and constants (→ simplicity-hunter, Dead Code Paths); exported dead symbols and
module organization (→ boundary-hunter); stuttering names as package design (→ smell-hunter); error-chain
correctness (→ invariant-hunter); narration that leaks secrets (→ security-hunter); test quality (→ test-hunter).
Where ownership is *contested*, the category's **Ownership:** note in What to Hunt is authoritative.

## When to Use

- Reviewing AI-assisted code before merge
- Cleaning up a branch after heavy AI pair-programming
- Enforcing project conventions on new contributions
- Reducing noise in pull request reviews

## Quick Reference

Full rules in **What to Hunt**; every finding must also clear Not-a-finding and the Phase 5 evidence bar. Category
names are canonical: the heading here, in What to Hunt, and in the report are identical.

| Category | Core signal | Action | Belongs to another hunter |
| -------- | ----------- | ------ | ------------------------- |
| Redundant Comments | Comment restates trivial code, a name, or a language construct | Delete | Over non-trivial code → smell-hunter; missing "why" → doc-hunter |
| Verbose Documentation | Doc block restates the signature it sits on | Strip the redundant part | Content quality of public docs → doc-hunter |
| Style Drift | Breaks the per-file convention baseline | Conform; one consolidated row when a rule enforces the convention | Stuttering as package design → smell-hunter; module organization → boundary-hunter |
| Trivially Dead Code | Commented-out code, vague `TODO`, leftover `pass`, unused import or binding, bare lint suppression | Delete, or justify the suppression | Unreachable logic, unused functions → simplicity-hunter; exported dead → boundary-hunter |
| Hedging and Narration | Speculative or apologetic comments; logging that narrates flow | Delete; keep concrete constraints with references | Secrets in narration → security-hunter |
| Unnecessary Error Wrapping *(Go only)* | Wrapping that adds words, not context | Wrap once where context is meaningful | Chain correctness → invariant-hunter |

Hunter names are unsuffixed end-state names. Until consolidation completes, live skills are language-suffixed
(`doc-hunter-go`, `doc-hunter-py`, `doc-hunter-ts`, and so on).

## Core Principles

1. **The diff is the default surface.** Slop arrives with new contributions, so the natural surface is the branch
   diff — the one deliberate deviation from the sibling hunters, which default to codebase. In diff mode only what
   the change introduced is a finding, with one stated exception: formatting on touched lines (see Style Drift). In
   path or codebase mode every matching pattern in the eligible surface is a candidate.

2. **The working tree is what gets judged.** The diff nominates; the working tree decides. A comment added in a
   commit and removed in the working tree is not a finding.

3. **Comments explain why, not what.** A comment that restates the code ("increment the counter") is noise. A
   comment that explains intent, constraints, or a non-obvious decision ("rate limit: third-party API allows 100
   req/min") is valuable.

4. **The project's convention is the baseline, resolved per file.** Formatter and lint configuration that applies to
   the file → repository instructions → the dominant pattern in comparable established code nearby → the language
   style guide. When none of these yields a convention there is no baseline and no Style Drift finding. Prescribing
   a convention is not an audit.

5. **Less is more.** AI over-documents, over-explains, and over-hedges. Strip to the minimum that preserves clarity.

6. **Nomination is not proof.** Scans and whole-file checks surface candidates. In diff mode a whole-file check on a
   changed file (unused imports, unused bindings) also surfaces pre-existing problems; report one only with proof
   that the change introduced it.

7. **Preserve intent.** Flag noise, not substance. A comment that explains why a non-obvious design was chosen over
   the seemingly simpler alternative is design rationale, not noise — even at ten or more lines.

**Comment ownership rule** (stated identically in doc-hunter, slop-hunter, and smell-hunter):

- Comment absent and the "why" non-obvious → doc-hunter (add the missing "why" comment).
- Comment present and the code trivial → slop-hunter (delete the redundant comment).
- Comment present and the code non-trivial → smell-hunter (extract/refactor; the comment is deodorant).

## Not a finding on these grounds alone

Conditionals, not category exemptions — each states what does **not** justify a finding and, where a corresponding
finding exists, what would:

- **A design-rationale comment, however long.** Test: would removing it risk someone reimplementing the broken
  approach? If yes, it stays.
- **A restating summary line on a public or exported symbol.** Its presence is convention; its content quality is
  doc-hunter's. *Is* a finding when the block also carries tags repeating parameter names or types.
- **A `TODO` with an owner, ticket, or concrete condition.** *Is* a finding when it has none of the three.
- **A lint suppression with a stated reason.** *Is* a finding when bare.
- **Go blank-identifier idioms.** `import _ "pkg"` for side effects and `var _ Iface = (*T)(nil)` compile-time
  assertions are intentional. Go's compiler rejects unused imports and unused locals outright, so those never appear
  in compiling code and `//nolint` cannot hide them. *Is* a finding: `_ = x` silencing a binding the author meant to
  use.
- **An unused binding whose initializer has side effects.** Unused does not mean deletable; the Action must say what
  is removed and what is kept.
- **Logging with operational intent** — request IDs, durations, error context. Only flow narration is noise.
- **Style with no resolvable baseline.** Not drift. Record `baseline uncertain: <concern>` in Scope instead.
- **A comment that describes behavior the code no longer performs.** Staleness is doc-hunter's; cross-reference.
  Slop-hunter flags only accurate-but-redundant text.

## What to Hunt

Categories are named, not numbered. Cross-references use category names (e.g. "→ Trivially Dead Code").

### Redundant Comments

A comment that restates trivial code, a name, or a language construct.

**Signals:**

- `// Initialize the slice` above `var items []Item`; `# Return the result` above `return result`
- `// Check for errors` above `if err != nil`; `// Loop through items` above a `for` line
- Comments explaining standard-library usage
- Section dividers (`// ---- Helper Functions ----`) in small files
- `# Handle the case where...` before a trivial `None` / `nil` / `undefined` check — the *comment* is slop here; a
  guard already guaranteed by preceding logic is simplicity-hunter's Dead Code Paths

**Action:** Delete. If the code needs explanation, it should be rewritten for clarity first.

**Ownership:** the comment ownership rule above. Trivial code → here. Non-trivial code → smell-hunter. Missing
"why" → doc-hunter. Stale or false comment → doc-hunter.

### Verbose Documentation

A doc block that restates the symbol it sits on.

**Signals:**

- Doc on a private or unexported symbol restating its name or body
- `@param` / `:param:` / `Args:` entries repeating the parameter name or type (`@param name - the name`)
- `@returns` / `:returns:` / `Returns:` restating the return type annotation
- Docs describing the implementation rather than the contract
- A block where every section is present and none adds anything beyond the signature

**Action:** Strip the redundant part. Keep the summary line on public and exported symbols — presence there is
convention (godoc, public API docs). Redundant tags on public symbols *are* flagged.

**Ownership:** whether a public doc says the right thing is doc-hunter's. Whether it says anything at all beyond
the signature is here.

### Style Drift

Naming, import grouping, error-handling pattern, idiom choice, or formatting that breaks the per-file convention
baseline.

**Convention baseline, resolved per file, in this order — the first source that yields a convention wins:**

1. Formatter and lint configuration that applies to the file. Ruff and ESLint resolve the nearest config, not one
   repo-wide file; a monorepo with two configs has two baselines.
2. Repository instructions: `CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`, `.editorconfig`, convention docs.
3. The dominant pattern in comparable established code nearby.
4. The language style guide, named in the reference.

No source yields a convention → no finding; record `baseline uncertain: <concern>` in Scope. The report's
Convention cell names the source used; a finding whose Convention cell cannot name its source is not reportable.

**Signals** are per language (see the reference): naming convention, import grouping, error-handling pattern,
idiom choice (f-string vs `.format`, template string vs concatenation, `pathlib` vs `os.path`), formatter output.

**Formatter — two separate questions.**

- *Adoption*: which formatter the project uses. Established by the command the project itself invokes — package
  scripts, `Makefile`, pre-commit config, CI. A config file alone is not adoption: Ruff lint without Ruff format is
  common. A project running `biome check` with the formatter enabled in `biome.json` has adopted Biome. When unsure,
  the formatter is not adopted. **Go is the exception:** `gofmt` is canonical and runs on every Go file with no
  adoption evidence required.
- *Execution*: what the audit runs. Always the tool's narrow read-only operation, named in the reference
  (`gofmt -l`, `ruff format --check`, `black --check`, `prettier --list-different`, `biome format`). Never install
  anything. Three outcomes, each recorded in Scope: **ran**, **skipped** (none adopted, or adopted but not
  installed), **errored** (the tool exited with a non-format error). Only "ran" produces candidates.

**Formatting on touched lines is the one exception to "introduced by this change."** In diff mode a formatting
violation on a line the change touched is reported as a touched-line violation whether or not it predates the
change: the author edited that line and left it unformatted, and any format-on-save editor would have fixed it.
Violations on untouched lines are not reported in diff mode. Hunk intersection is the rule, not a proof, and the
Convention cell says so (`gofmt, touched line`).

**Consolidation — a reporting decision, separate from the remedy.** When a scan enumerates N occurrences of one
rule-enforceable pattern, report one row: a representative location, `Occurrences: N` (the enumerated count; `≥ N`
if the scan was partial), and an Action that fits the enforcement state, verified in the project's config:

- Rule or formatter **already enabled** → the violations slipped past it; Action is "run `<fixer>`" or "fix the N
  sites". Enabling it again fixes nothing.
- Rule **available but disabled** → Action is "enable `<rule>` and fix the N sites".
- **No rule exists** → no consolidation; report the sites individually, or not at all if they fail the evidence bar.

**Action:** Conform. Cite the baseline source in the Convention cell.

**Ownership:** naming drift introduced by the change is here; stuttering names as package design are smell-hunter's
Stuttering Names. File and folder organization is boundary-hunter's.

### Trivially Dead Code

Text and declarations that compile or parse but do nothing, and can be judged inside one file.

**Signals:**

- Commented-out code, of any size
- `TODO` / `FIXME` / `HACK` / `XXX` with no owner, ticket, or concrete condition
- Leftover `pass` in a non-empty Python body
- Unused imports and unused bindings where the language lets them compile
- Lint suppression with no stated reason: bare `//nolint`; `# noqa`, `# type: ignore`, `# pylint: disable`;
  `// eslint-disable*`, `// @ts-ignore`, `// @ts-expect-error` — each without a trailing reason
- Go: `_ = x` silencing a binding the author meant to use; unused parameters; unused struct fields

**Diff-mode proof.** An import whose last use the change deleted is invisible to the added-line scan. It is found by
checking the changed file's current state and reported only with proof that a use existed at the merge base
(`git show "$MB:<file>"`). Without that proof it is pre-existing and not a finding.

**Action:** Delete. For a suppression: delete it, or state the reason. For an unused binding with a side-effecting
initializer: say what is removed and what is kept.

**Ownership:** commented-out code is here, unconditionally — text is not a code path. Live-but-unreachable *logic*
(guards already guaranteed, stale flags, zero-call helpers), unused functions, and unused constants are
simplicity-hunter's Dead Code Paths, which demands liveness evidence. Exported dead symbols are boundary-hunter's.

### Hedging and Narration

Speculative, apologetic, or self-referential text, and logging that narrates control flow.

**Signals:**

- `// This is a workaround for...` with no issue reference
- `// Note: this might need to be updated if...`
- `// For safety, we also check...`
- `// New, improved version...` — references code that no longer exists
- Logging that narrates flow: `log.Println("entering X")`, `logger.debug("starting")`, `console.log('here')`

**Action:** Delete. Keep comments that document a concrete constraint or a known issue with a reference.

**Ownership:** narration that leaks a secret or PII is security-hunter's; cross-reference, severity is theirs.
Logging with operational intent is not a finding (see Not-a-finding).

### Unnecessary Error Wrapping *(Go only)*

Defined entirely in `references/slop-go.md`: signals, ownership split with invariant-hunter, scans, evaluation, and
table schema. Listed here so the category set is complete in one place.

## Test-code scope

Test files are **fully in scope** for every category. Noise inside a test is slop; test *quality* is test-hunter's.
Each language reference's eligibility rule and scans include test paths.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is:**

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths. Not slop.
- **High** — a defect with likely user-visible, security, or reliability impact. Not slop.
- **Medium** — correctness or maintainability risk without imminent impact. Slop reaches Medium only when the noise
  hides something: a bare suppression masking a real lint finding; narration logging on a hot path with measurable
  cost.
- **Low** — hygiene; no behavioral risk. **The default for every slop category.**

A finding that rises to Critical or High is not slop: cross-reference it to its owner and do not score it here. A
comment describing behavior the code no longer performs is doc-hunter's, not a Medium here.

**Impact — how much the change is worth:** reader burden removed, and how often the affected code is read or
changed. Contextual; never derived from occurrence count or pattern alone. Breadth is evidence, never the
derivation: thirty drifted names in a module every contributor edits weekly are High impact; the same thirty in a
frozen migration script are Low. Low remediation effort says nothing about impact.

- **High** — substantial reduction on code read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the evidence bar but touches a small, rarely hit surface

Recommendations group by Severity (Critical → High → Medium → Low), then by Impact within each group.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve the raw manifest.** Scope may be:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, untracked. **The default
     when unspecified.**
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project (`SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot, treat `scope.txt` as a **file manifest only**
   (one path per line). Read run metadata (base SHA, surface kind, counts) from `scope-meta.txt` when present. Use
   the manifest verbatim; do not re-resolve. The resolution below is for standalone runs only.

   For diff mode, resolve fail-closed:
   ```bash
   BASE=$(git symbolic-ref -q refs/remotes/origin/HEAD | sed 's@^refs/remotes/@@')
   git rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1 || BASE=
   if [ -z "$BASE" ]; then
     for b in origin/main origin/master main master; do
       git rev-parse -q --verify "$b^{commit}" >/dev/null && BASE=$b && break
     done
   fi
   # BASE still empty: STOP and ask for an explicit base. Do not continue.
   MB=$(git merge-base "$BASE" HEAD) || exit 1                        # STOP: no merge base
   CHANGED=$(git diff --name-only --diff-filter=d "$MB") || exit 1    # STOP: diff failed
   UNTRACKED=$(git ls-files --others --exclude-standard) || exit 1    # STOP: ls-files failed
   DELETED=$(git diff --name-only --diff-filter=D "$MB") || exit 1    # STOP: diff failed
   SCOPE=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u)
   ```
   Every command that supplies audit data is checked; only the base-discovery probes may fail, because failure
   there means "try the next candidate". One diff from the merge base to the working tree covers committed, staged,
   and unstaged changes. A file that existed at the merge base and is gone from the working tree lands in
   `$DELETED`; a file added after the merge base and deleted again appears nowhere. A failed command is never an
   empty scope. `$MB` is reused by every added-line scan in Phase 2, so nominations and manifest describe the same
   state.

   If `$SCOPE` is empty, run no scans: write the report with "Audit completed: 0 findings — empty diff scope",
   listing `$DELETED` under "Deleted in diff" if non-empty, and stop. If the resolved surface exceeds the context
   budget, report the file count and ask to narrow or chunk.

   **Record provenance.** Capture `git rev-parse --short HEAD` and whether the working tree is dirty
   (`git status --porcelain -- $SCOPE`); both go in the report's Scope section, with `$BASE` and `$MB` in diff mode.
   On a dirty tree, line numbers match no commit — state that findings must be re-located by symbol name.

   The raw manifest is **immutable** and language-independent. Do not redefine it on a mixed scope — silently
   narrowing breaks the party guarantee that all hunters audit the same surface.

   **Whitespace in paths is unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell expansion
   word-splits on spaces; whitespace paths are a declared limitation.

2. **Detect languages** from manifest extensions alone:
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — is **excluded, not audited**: without a reference there is no eligibility rule, no scan set, no
   evidence form, no baseline precedence. Record `excluded — no reference for .<ext>: {count} files` in Scope,
   naming each extension.

3. **Load language references.** For every detected language, read `references/slop-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/slop-go.md`). **Fail closed:** if a required reference cannot be
   read, **stop and report**; do not continue with shared categories only.

4. **Derive per-language eligible file lists** by applying each reference's eligibility rules to that language's
   manifest files. Drop only: vendored and build trees, lockfiles, Markdown-only inputs, and generated files
   identified by the reference's authoritative **in-file marker** — **never** by filename guessing. The result is
   `$GO_FILES`, `$PY_FILES`, `$TS_FILES`: one path per line, immutable from here on. **Every scan takes its
   language's list, never `$SCOPE`** — there are no scan globs, so no eligible file is silently skipped, and `#` in
   Go strings or `//` in Python URLs cannot cross-fire. In codebase mode the reference says how to enumerate the
   list.

   Record in Scope: raw manifest count, each per-language eligible count, exclusions, and
   `References loaded: {go, python, typescript as present}`.

   If **nothing** eligible remains: write `Audit completed: 0 findings — no eligible source in scope` and stop
   before scanning.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Established files outside it are *read* as **context**: that is where the convention baseline comes from.

5. **Establish the convention baseline.** For each eligible file, resolve the applicable formatter and lint config,
   then read repository instructions (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`, `.editorconfig`, convention
   docs), then look at comparable established code nearby. Note the documentation style in use (godoc; Google,
   NumPy, or Sphinx docstrings; JSDoc). Establish formatter *adoption* from the command the project invokes. Record
   every concern with no resolvable baseline as `baseline uncertain: <concern>`.

### Phase 2: Scan for Noise

Scans produce **candidates only** — each match is judged in the working tree in Phase 5.

For each loaded reference, run its Phase 2 scan block against that language's eligible list.

- **Diff mode** nominates from added lines: `git diff -U0 "$MB" -- $LANG_FILES`, keeping the `@@` hunk headers so
  every candidate has a file and a working-tree line. Untracked files have no diff — scan them whole with the
  path-mode commands. Removed lines (`^-`) are read too: a removed use of a still-imported symbol nominates a
  Trivially Dead Code candidate for Phase 4.
- **Path and codebase mode** scan the whole eligible file.

### Phase 3: Formatter Check

Per language, per the reference's Formatter section. Decide adoption first (Go: always adopted). Run the narrow
read-only operation on `$LANG_FILES`. Record the outcome — ran, skipped with reason, errored with message — in
Scope. In diff mode, keep only violations on lines the change touched: compare the formatter's diff against the
`@@` ranges of `git diff -U0 "$MB" -- <file>`. Untracked files are new in full; every line is touched.

### Phase 4: Whole-file Checks on Changed Files — diff mode only

Some slop is invisible on added lines: an import or binding whose last use the change deleted. For each candidate
the removed-line reading in Phase 2 nominated, check the working tree for remaining uses, then prove the change
caused it: `git show "$MB:<file>"` must show a use at the merge base. No proof → pre-existing → not a finding.
Path and codebase mode need no proof; every unused import in the eligible surface is a candidate.

### Phase 5: Evaluate Each Finding

For each candidate, in the working tree:

1. Apply Not-a-finding first.
2. Noise or value? Would a reader lose anything if it were gone?
3. Matches or breaks the baseline? Name the baseline source, or record `baseline uncertain` and drop it.
4. Does it clear the category's evidence bar — the proof step for whole-file checks, the touched-line rule for
   formatting, the enforcement state for a consolidated row?
5. Run the loaded reference's Phase 5 block for language-specific judgment and language-only categories.

Assign **Severity and Impact** to every finding (both required; they diverge). Nothing is held back;
`Audit completed: N findings` counts every reported finding, a consolidated row counting once.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-slop-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if none exists). A caller-specified output path or return
mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas. Language-only categories
appended by a language reference (today: Unnecessary Error Wrapping for Go) use the table schemas supplied in that
reference.

## Red Flags — stop and re-check

| Thought | Reality |
| ------- | ------- |
| "The added-line scan matched, so it's a finding" | The diff nominates; the working tree decides. Open the file as it is now. |
| "This import is unused in the changed file" | Was it used at the merge base? No proof, no finding — it predates the change. |
| "The formatter listed this file" | Only touched lines count in diff mode, and the Convention cell must say `touched line`. |
| "This comment restates the code" | Is the code trivial? Non-trivial → smell-hunter. Is it still accurate? Stale → doc-hunter. |
| "This function has no callers" | Liveness is simplicity-hunter's question. Slop keeps `_ = x`, unused params, unused fields. |
| "Thirty sites — this is High impact" | Count is evidence, not the derivation. Who reads this code, and how often? |
| "The project has a Ruff config, so Ruff is the formatter" | Adoption is the command the project invokes. A config alone is lint, not format. |
| "I'll recommend enabling the rule" | Is it already enabled? Then the sites slipped past it; the Action is to run the fixer. |
| "The team clearly prefers f-strings, mostly" | Split evenly with no config is no baseline. Record the uncertainty; no finding. |
| "This long comment is verbose" | Would removing it risk someone reimplementing the broken approach? Then it is load-bearing. |
| "This looks AI-written" | Not the test. Is it noise? |
| "The report looks thin — I'll note what I checked and found clean" | Zero-finding sections are omitted. A thin report is a valid result. |
| "I'll just fix it while I'm here" | No code edits. The report is the deliverable. |
| "The language reference won't load — I'll do shared categories only" | Fail closed. Stop and report. |

## Operating Constraints

- **No code edits.** Audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only *categories* with findings. Omit a category heading, table, or list
  entirely when it would contain zero items — no empty tables, placeholder subsections, or negative statements like
  "none found" or "no issues". The Scope section is not a category and is filled in from the template every run,
  including the formatter outcome and any `baseline uncertain` lines.
- **Scope: surface noise only.** A finding that doesn't answer "is this noise?" belongs to another hunter. Contested
  boundaries are resolved at the category that owns them: each **Ownership:** note in What to Hunt states what is
  kept here and what routes away.
- **Evidence required.** Every finding cites `file:line` (path form per the language reference) with the exact
  text. A consolidated Style Drift row satisfies this with its representative location; the Occurrences column
  carries the count.
- **Diff mode reports what the change introduced**, judged in the working tree, with formatting on touched lines as
  the one stated exception and the merge-base proof as the gate for whole-file checks.
- **Baseline before drift.** No Style Drift finding without a named baseline source in the Convention cell.
- **Never install.** A formatter that is adopted but absent is `skipped`, never fetched.
- **Preserve intent.** Flag noise, not substance. Design rationale stays regardless of length.
- **Handoff, not duplication.** When a candidate belongs to another hunter — stale comment, unreachable logic,
  exported dead symbol, leaked secret — cross-reference it and do not score it here.
