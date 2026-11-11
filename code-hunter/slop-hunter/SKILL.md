---
name: slop-hunter
description: Audit Go, Python, or TypeScript code for slop — redundant comments, verbose docs, style drift, trivially dead code, hedging and narration, Go error-wrap noise. Defaults to the branch diff.
disable-model-invocation: true
---

# Slop Hunter

Audit code for **slop** — text in a source file that carries no information for a reader: comments restating code,
docs restating signatures, style that breaks the project's own conventions, vague work markers, bare lint
suppressions, hedging, narration. Goal: **the code reads as if a careful human wrote it in this project's idiom.**

The test for every finding is *is this noise?*, never *did an AI write this?*

**Not covered (owned by other hunters):** missing "why" comments, stale or false comments, and the content quality
of public docs (→ doc-hunter); comments that call the code a hack or a workaround and name no cause, or that name a
dependency defect but not when the workaround can go, whatever the marker (→ doc-hunter, Unexplained Workarounds);
names that the code contradicts (→ doc-hunter, Misleading Comments and Names); comments over non-trivial code
(→ smell-hunter, Comments as Deodorant); live but unreachable logic, unused functions and constants
(→ simplicity-hunter, Dead Code Paths); exported dead symbols
(→ boundary-hunter, Dead Exports); generic package / module names (→ boundary-hunter, Generic Boundary Names);
stuttering names as package design (→ smell-hunter); type-checker
suppressions (`# type: ignore`, `@ts-ignore`, `@ts-expect-error`) (→ invariant-hunter); error-chain correctness and
discarded error returns (→ exception-hunter); narration that leaks secrets (→ security-hunter); test quality
(→ test-hunter).
Where ownership is *contested*, the category's **Ownership:** note in What to Hunt is authoritative.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `perf-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

Category names are canonical: the heading here, in What to Hunt, and in the report are identical.

| Category | Core signal | Action |
| -------- | ----------- | ------ |
| Redundant Comments | Comment restates trivial code, a name, or a language construct | Delete |
| Verbose Documentation | Doc block restates the signature it sits on | Strip the redundant part |
| Style Drift | Breaks the per-file convention baseline where no lint rule states it | Conform |
| Trivially Dead Code | Vague `TODO`, bare linter suppression, Go `_ = x` | Delete, or justify the suppression |
| Hedging and Narration | Speculative or apologetic comments; logging that narrates flow | Delete; keep concrete constraints with references |
| Unnecessary Error Wrapping *(Go only)* | Wrapping that adds words, not context | Wrap once where context is meaningful |

## Core Principles

1. **Diff mode reports only what the change introduced.** The diff is the default surface because slop arrives with
   new contributions. In path or codebase mode every match in the eligible surface is a candidate.

2. **Nomination is not proof.** Scans and the diff *nominate*; the working tree decides. A comment added in a commit
   and removed in the working tree is not a finding.

## Not a finding on these grounds alone

Applies to every comment category; each category adds its own **Not a finding:** line.

- **A design-rationale comment, however long.** A comment that explains why a non-obvious design was chosen over the
  seemingly simpler alternative is substance, not noise — even at ten or more lines. Test: would removing it risk
  someone reimplementing the broken approach? If yes, it stays.
- **A comment that describes behavior the code no longer performs.** Staleness is doc-hunter's; cross-reference.
  Slop-hunter flags only accurate-but-redundant text.

## What to Hunt

### Redundant Comments

A comment that restates trivial code, a name, or a language construct.

**Signals:**

- `// Initialize the slice` above `var items []Item`; `# Return the result` above `return result`
- `// Check for errors` above `if err != nil`; `// Loop through items` above a `for` line
- Comments explaining standard-library usage
- Section dividers (`// ---- Helper Functions ----`) in a file where each section holds fewer than three declarations
- `# Handle the case where...` before a trivial `None` / `nil` / `undefined` check — the *comment* is slop here; a
  guard already guaranteed by preceding logic is simplicity-hunter's Dead Code Paths

**Action:** Delete.

**Ownership — the comment ownership rule** (also governs Hedging and Narration):

- Comment contradicts the code it describes → doc-hunter (Misleading Comments and Names), unless it only justifies a
  construct another hunter audits (a discarded error, a type-system bypass) → that hunter.
- Comment calls the code a hack or a workaround but names no cause → doc-hunter (Unexplained Workarounds).
- Comment states an external constraint but not its source, or a dependency defect but not when the workaround can
  go → doc-hunter (Unexplained Business Rules or Unexplained Workarounds).
- Comment states an invariant that no check enforces and the code could → doc-hunter (Undocumented Contracts:
  enforce it, keep the comment until then), unless a status-string, duration, or money type would enforce it →
  smell-hunter.
- Comment states a "why" the code cannot (a source, an external cause, a contract the types cannot state) and the
  code matches it → no finding.
- Comment absent and the "why" non-obvious → doc-hunter (add the missing "why" comment).
- Comment restates what trivial code does → slop-hunter (delete the redundant comment).
- Comment explains what non-trivial code does → smell-hunter (extract/refactor; the comment is deodorant).

*Trivial* code is one statement or one simple condition whose meaning the comment repeats; a comment that summarizes
two or more statements or a compound condition sits over non-trivial code.

### Verbose Documentation

A doc block that restates the symbol it sits on.

**Signals:**

- Doc on a private or unexported symbol restating its name or body
- `@param` / `:param:` / `Args:` entries repeating the parameter name or type (`@param name - the name`)
- `@returns` / `:returns:` / `Returns:` restating the return type annotation
- Docs describing the implementation rather than the contract
- A block where every section is present and none adds anything beyond the signature

**Action:** Strip the redundant part.

**Not a finding:** a restating summary line on a public or exported symbol — presence there is convention (godoc,
public API docs). Redundant tags on the same block *are* findings.

**Ownership:** whether a public doc says the right thing is doc-hunter's. Whether it says anything at all beyond
the signature is here.

### Style Drift

Naming, error-handling pattern, or idiom choice that breaks the per-file convention baseline. A convention that a
formatter or a lint rule enforces is not judged here: each reference lists it under Delegated to tools.

**Convention baseline, resolved per file, in this order — the first source that yields a convention wins:**

1. Configuration that states a convention judged here, such as a docstring `convention` in Ruff's pydocstyle
   settings. Ruff and ESLint resolve the nearest config, not one repo-wide file; a monorepo with two configs has two
   baselines.
2. Repository instructions: `CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`, `.editorconfig`, convention docs.
3. The dominant pattern in comparable established code nearby. Two styles split evenly is no dominant pattern.
4. The language style guide, named in the reference.

No source yields a convention → no finding; record `baseline uncertain: <concern>` in Scope. Prescribing a
convention is not an audit. A finding whose baseline source cannot be named is not reportable.

**Signals** are per language (see the reference): naming idioms, error-handling pattern, idiom choice.

**Action:** Conform.

**Ownership:** naming drift introduced by the change is here; stuttering names as package design are smell-hunter's
Stuttering Names. A generic package or module-directory name is boundary-hunter's Generic Boundary Names; file
placement inside a unit is smell-hunter's.

### Trivially Dead Code

Text and declarations that compile or parse but do nothing, and can be judged inside one file.

**Signals:**

- `TODO` / `FIXME` / `XXX` with no owner, ticket, or concrete condition. A marker comment that calls the code a hack
  or a workaround, or that names a dependency defect the code works around, is doc-hunter's (Unexplained Workarounds)
- Linter suppression with no stated reason: bare `//nolint`, `// #nosec`; `# noqa`, `# nosec`, `# pylint: disable`;
  `// eslint-disable*`, `// biome-ignore` — each without a trailing reason. Type-checker suppressions
  (`# type: ignore`, `# pyright: ignore`, `// @ts-ignore`, `// @ts-expect-error`) are invariant-hunter's Type-System
  Bypasses, with or without a reason
- Go only: `_ = x` silencing a non-error binding the author meant to use

**Action:** Delete. For a suppression: delete it, or state the reason.

**Not a finding:** a `TODO` with an owner, ticket, or concrete condition; a linter suppression with a stated reason;
a language idiom the reference's Trivially Dead Code section lists as intentional (e.g. Go blank-identifier forms).

**Ownership:** live-but-unreachable *logic*
(guards already guaranteed, stale flags, zero-call helpers), unused functions, and unused constants are
simplicity-hunter's Dead Code Paths, which demands liveness evidence. Exported dead symbols are boundary-hunter's
Dead Exports.
Type-checker suppressions, reason or not, are invariant-hunter's Type-System Bypasses — "should this bypass exist?"
subsumes "does it have a reason?"; one line, one hunter. `_ = f()` where `f` returns an `error` is not covered
here. Coverage pragmas (`# pragma: no cover`, `/* istanbul ignore … */`,
`/* c8 ignore … */`, `/* v8 ignore … */`) and skipped or focused tests (`t.Skip()`, `@pytest.mark.skip`, `it.skip`,
`.only`), reason or not, are test-hunter's: whether a test can fail is one line, one hunter.

### Hedging and Narration

Speculative, apologetic, or self-referential text, and logging that narrates control flow.

**Signals:**

- `// Note: this might need to be updated if...`
- `// For safety, we also check...`
- `// New, improved version...` — compares against a version the reader cannot see; accurate, but carries no
  information
- Task history: `// now uses the v2 client`, `// changed to UTC`, `// added on client feedback`, `// tried a map
  first`. It belongs in the commit or the PR
- Logging that narrates flow through a logger: `log.Println("entering X")`, `logger.debug("starting")`

**Action:** Delete. Keep comments that document a concrete constraint or a known issue with a reference.

**Not a finding:** logging with operational intent — request IDs, durations, error context. Only flow narration is
noise.

**Ownership:** narration that leaks a secret or PII is security-hunter's; cross-reference, severity is theirs. The
comment ownership rule (Redundant Comments) applies: a workaround comment that names no cause, or names a defect but
not when the workaround can go, is doc-hunter's Unexplained Workarounds; one that excuses the project's own design is
smell-hunter's Comments as Deodorant.

### Unnecessary Error Wrapping *(Go only)*

Error wrapping that adds words, not context. Defined in `references/slop-go.md`.

### Within-skill routing

A doc comment attached to a declaration (godoc, docstring, JSDoc) → Verbose Documentation. Any other comment →
Redundant Comments, or Hedging and Narration when it speculates or apologizes; one that neither restates the code
nor hedges, and only breaks the file's convention baseline for comments (marker, placement, casing, spacing) → Style
Drift. One finding per site.

**Markers and suppressions.** A `TODO` / `FIXME` / `XXX` comment or a linter suppression → Trivially Dead Code, also
when its text hedges or restates code, and also inside a doc comment. That comment gets no other row; the rest of a
doc comment stays Verbose Documentation. When Trivially Dead Code does not report it (an owner, a ticket, a
condition, a stated reason), no other category does.

**Deleted text gets one row.** When an Action deletes whole lines or a whole comment, no other row reports text
inside them.

**Doc style.** A doc block in another style than the baseline (Google, NumPy, or Sphinx docstrings; JSDoc tag form)
→ Style Drift. Verbose Documentation judges only redundancy.

## Test-code scope

Test files are **fully in scope** for every category. Noise inside a test — comments, docs, style — is slop; whether a test can fail — its assertions, skips, focused tests, and coverage pragmas — is
test-hunter's.
Test paths are listed in each language reference.

## Severity and Impact

Every finding carries **both**.

**Severity — behavioral risk if left as-is:**

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact.
- **Medium** — correctness or maintainability risk without imminent impact. Slop reaches Medium only when the noise
  hides something: a bare suppression masking a real lint finding; narration logging on a hot path with measurable
  cost.
- **Low** — hygiene; no behavioral risk. **The default for every slop category.**

A finding that rises to Critical or High is not slop: cross-reference it to its owner instead of scoring it here.

**Impact — how much the change is worth:** reader burden removed, and how often the affected code is read or
changed. Breadth is evidence, never the derivation: thirty drifted names in a module every contributor edits weekly
are High impact; the same thirty in a frozen migration script are Low. Low remediation effort says nothing about
impact.

- **High** — substantial reduction on code read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the evidence bar but touches a small, rarely hit surface

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve the raw manifest.** Scope may be:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, untracked. **The default
     when unspecified.** Resolve it with `references/diff-scope.md`; `$MB` is reused by every
     added-line scan in Phase 2, so nominations and manifest describe the same state.
   - **Path**: specific files, folders, or packages — `SCOPE=$(git ls-files --cached --others --exclude-standard
     -- <paths>)`, which expands folders to files
   - **Codebase**: the entire project (`SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot, treat `scope.txt` as a **file manifest only**
   (one path per line): `SCOPE=$(cat <snapshot>/scope.txt)`. Read run metadata (base SHA — `$MB` in diff mode —
   surface kind, counts) from `scope-meta.txt` when present. Use the manifest verbatim; the resolution
   above is for standalone runs only.

   **Persist run state.** Shell variables do not survive between tool calls, and `rg … --` with an empty variable
   searches the whole working directory. Create one run directory (`RUN=$(mktemp -d) && echo "$RUN"`) and use the
   printed path literally from then on. Every call starts at the repository root (`cd "$(git rev-parse
   --show-toplevel)"`), because every list holds root-relative paths. Write `$SCOPE` to `<run>/scope.txt` and, in diff mode, `$MB` to `<run>/mb`.
   A later call restores what it uses (`SCOPE=$(cat <run>/scope.txt)`); an empty restore is a STOP, never an empty
   result. If the resolved surface exceeds the context budget, report the file count and ask to narrow. Narrowing is
   the only known recovery: on a 13 600-line Go scope, a whole-codebase run found about half the sites of a run scoped
   to one directory, and splitting the reading over agents did not recover them. With nobody to ask, do one of two
   things and say which in Scope: read alone as far as the budget allows and record what is left as `not read: <n>
   files — context budget`, or split the reading over sub-agents and record the split as `Read split: <n> agents by
   <directory|file list> — merged by this session`. A report with neither line claims that one reader read every file.

   **Record provenance.** Capture `git rev-parse --short HEAD` and whether the working tree is dirty
   (`git status --porcelain -- $SCOPE`); both go in the report's Scope section, with `$BASE` and `$MB` in diff mode.
   On a dirty tree, line numbers match no commit — state that findings must be re-located by symbol name.

   The raw manifest is **immutable** and language-independent: on a mixed scope it stays whole, so every hunter in a
   party audits the same surface.

   **Whitespace in paths is unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell expansion
   word-splits on spaces; whitespace paths are a declared limitation.

2. **Detect languages** from file extensions alone: the manifest's, or in codebase mode those of
   `git ls-files --cached --others --exclude-standard` (Scope records only their counts; the language scans still
   search `.`):
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — is **excluded, not audited**: without a reference there is no eligibility rule, no scan set, no
   baseline precedence. Record `excluded — no reference for .<ext>: {count} files` in Scope,
   naming each extension.

3. **Load language references.** For every detected language, read `references/slop-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/slop-go.md`). **Fail closed:** if a required reference cannot be
   read, **stop and report**.

4. **Derive per-language eligible file lists** with each reference's eligibility block. It drops only what its
   eligibility section lists, and generated files only by its authoritative **in-file marker**, never by filename.
   The result is `$GO_FILES`, `$PY_FILES`, `$TS_FILES`: one path per line, immutable from here on. **Every scan takes
   its language's list, never `$SCOPE`** — there are no scan globs, so no eligible file is silently skipped, and `#`
   in Go strings or `//` in Python URLs cannot cross-fire. In codebase mode the reference says how to enumerate the
   list.

   Record in Scope: raw manifest count, each per-language eligible count, exclusions, and
   `References loaded: {go, python, typescript as present}`.

   Write each list to `<run>/<lang>.txt` (`go.txt`, `python.txt`, `typescript.txt`); each scan call restores its
   list first (`GO_FILES=$(cat <run>/go.txt)`). A language with no eligible file gets no `<lang>.txt` and no scans.

   If **nothing** eligible remains: write `Audit completed: 0 findings — no eligible source in scope` and stop
   before scanning.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Established files outside it are *read* as **context**: that is where the convention baseline comes from.

5. **Establish the convention baseline** for every eligible file, in the Style Drift order. Note the documentation
   style in use (godoc; Google, NumPy, or Sphinx docstrings; JSDoc). Record every concern with no resolvable baseline as `baseline uncertain: <concern>`.

### Phase 2: Scan for Noise

Scans *nominate*; Phase 3 judges each candidate in the working tree.

For each loaded reference, run its Phase 2 scan block against that language's eligible list. `$LANG_FILES` below
stands for `$GO_FILES`, `$PY_FILES`, or `$TS_FILES`.

- **Diff mode** nominates from added lines: `git diff -U0 "$MB" -- $LANG_FILES`, keeping the `+++` file headers and
  `@@` hunk headers so every candidate has a file and a working-tree line. Untracked files have no diff — scan them
  whole with the whole-file commands, restricted to the untracked subset
  (`git ls-files --others --exclude-standard -- $LANG_FILES`).
- **Path and codebase mode** scan the whole eligible file.

Done when every scan in each loaded reference's Phase 2 block has run — in diff mode including the untracked
whole-file scans — and every hit is listed as a candidate.

### Phase 3: Evaluate Each Finding

For each candidate, in the working tree:

1. Apply the general **Not a finding** list and the category's own **Not a finding:** line first.
2. Noise or value? Would a reader lose anything if it were gone?
3. Matches or breaks the baseline? Name the baseline source, or record `baseline uncertain` and drop it.
4. Does it clear the category's evidence bar?
5. Run the loaded reference's Phase 3 block for language-specific judgment and language-only categories.

Assign **Severity and Impact** to every finding. Nothing is held back.

Done when every candidate is a reported finding, dropped (not noise, no baseline, or pre-existing), or
cross-referenced to its owning hunter.

### Phase 4: Produce Report

Save as `YYYY-MM-DD-slop-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or return
mode (e.g. a party-mode orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

**Delegated to tools.** Each loaded reference's `## Delegated to tools` section names, one line per tool, the classes
of defect this hunter leaves to that tool. Do not hunt those classes, run the tool, or read its configuration. Check
only whether the tool is set up, with one `rg` per tool: its configuration file, its section in a shared file
(`[tool.ruff]` in `pyproject.toml`), or its name in a CI workflow. End `## Recommendations (Priority Order)` with the
bold label `**Tooling.**`, the sentence `This hunter does not check the classes below.`, and every line of the loaded
sections, each prefixed `not found, adopt:` or `found, confirm these are on:`. A line that states a condition prints
only when the condition holds. The block prints on every run, also when every tool is set up: a tool can be set up
with a rule off, and naming the rule costs one line.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched.
- **Evidence required.** Every finding cites `file:line` with the exact text.
