---
name: slop-hunter-go
description: |
  Audit Go code for AI-generated noise — redundant comments, verbose documentation, style
  drift from project conventions and gofmt, trivially dead code, and unnecessary error
  wrapping. Surface-level hygiene pass; defaults to branch diff but supports any scope.

  Use when: reviewing AI-assisted Go code before merge, cleaning up generated code,
  enforcing project style on new contributions, or reducing review noise.
disable-model-invocation: true
---

# Slop Hunter

Audit code for **AI-generated noise** — comments that narrate the obvious, documentation that restates code, style
choices that break project conventions, and dead code that slipped in. The goal: **the code reads like a human wrote it,
following existing project idioms and `gofmt` standards.**

## When to Use

- Reviewing AI-assisted code before merge
- Cleaning up a branch after heavy AI pair-programming
- Enforcing project conventions on generated contributions
- Reducing noise in pull request reviews

## Core Principles

1. **Default to the diff.** When scoped to a branch diff, only flag patterns introduced in this branch — pre-existing
   issues are out of scope. When scoped to a path or codebase, flag all matching patterns in the resolved surface.

2. **Comments explain why, not what.** A comment that restates the code ("increment the counter") is noise. A comment
   that explains intent, constraints, or non-obvious decisions ("rate limit: 3rd-party API allows 100 req/min") is
   valuable.

3. **`gofmt` is the law.** Go has a canonical formatter. Code that doesn't pass `gofmt` is wrong, period. Beyond
   formatting, project-specific conventions (naming, error handling, import grouping) must be followed.

4. **Less is more.** AI tends to over-document, over-explain, and over-hedge. Strip to the minimum that preserves
   clarity.

5. **Go idioms are the standard.** Effective Go, the Go Code Review Comments wiki, and the project's existing patterns
   define the style. AI-generated code often brings patterns from other languages.

**Comment ownership rule** (stated identically in doc-hunter, slop-hunter, and smell-hunter):
- Comment absent and the "why" non-obvious → doc-hunter (add the missing "why" comment).
- Comment present and the code trivial → slop-hunter (delete the redundant comment).
- Comment present and the code non-trivial → smell-hunter (extract/refactor; the comment is deodorant).

## What to Hunt

### 1. Redundant Comments

Comments that narrate obvious behavior, restate function/variable names, or explain standard language constructs.

**Signals:**

- `// Initialize the slice` above `var items []Item`
- `// Return the result` above `return result`
- `// Check for errors` above `if err != nil`
- `// Loop through items` above `for _, item := range items`
- Comments explaining standard library usage
- Section dividers (`// ---- Helper Functions ----`) in small files

**Action:** Delete. If the code needs explanation, it should be rewritten for clarity first.

### 2. Verbose Godoc

Over-documentation that adds noise without insight — typically AI-generated godoc on every function including trivial
unexported helpers.

**Signals:**

- Godoc on unexported functions with obvious behavior
- Godoc that repeats the function signature in prose ("DoThing does the thing with the given parameters")
- `// param: name - the name` style parameter descriptions that add nothing
- Godoc that describes the implementation instead of the behavior
- Godoc on interface methods that just restates the method name

**Action:** Keep godoc on exported symbols (Go convention). Strip godoc on unexported functions unless the behavior is
non-obvious. Godoc should describe *what* and *why*, not *how*.

### 3. Style Drift

Patterns that diverge from the project's established conventions or Go idioms.

**Signals:**

- Non-`gofmt` formatted code
- Import grouping that doesn't match project convention (standard, third-party, internal)
- Variable naming that doesn't follow Go conventions (`userName` instead of `username`, `get_user` instead of `getUser`)
- Error variable naming: `error` instead of `err`, `e` instead of `err`
- Constructor naming: `Create*` instead of `New*` (or vice versa if project uses `Create`)
- Receiver naming: multi-letter receivers when project uses single-letter, or vice versa
- Different error handling pattern than established code (e.g., wrapping with `errors.Wrap` when project uses `fmt.Errorf`)
- Java/Python/JS idioms: getters named `GetX()` when Go convention is just `X()`, `toString` instead of `String()`

**Action:** Conform to existing project conventions. Cite the existing pattern as evidence.

**Boundary with smell-hunter:** slop owns Go naming-convention *drift introduced by the audited change* (this
skill's diff orientation); *stuttering* names (`user.UserName`) as a package-design smell belong to smell-hunter.

### 4. Trivially Dead Code

Unused imports, unused variables, commented-out code blocks, and placeholder TODOs.

**Signals:**

- Unused imports (caught by compiler, but AI sometimes adds `//nolint` to suppress)
- Unused variables or constants
- Blocks of commented-out code (`// old implementation`)
- `// TODO: implement` or `// FIXME` without actionable context
- Unused parameters (especially after refactoring)
- `nolint` directives that suppress valid lint findings without justification

**Action:** Delete unused imports/variables (the compiler catches most, but check for suppressed lints). Delete
commented-out code. Convert vague TODOs to actionable issues or delete.

### 5. AI-Specific Verbal Patterns

Hedging language, apologetic comments, and over-explanation typical of AI-generated code.

**Signals:**

- `// This is a workaround for...` without specifying the issue
- `// Note: this might need to be updated if...` (speculative)
- `// For safety, we also check...` (unnecessary hedging)
- `// New, improved version..` (references old code that doesn't exist)
- Logging that narrates execution flow (`log.Println("entering function X")`)
- Excessive `nil` checks already guaranteed by preceding logic

(Over-wrapped errors belong to §6 below — one category, not two.)

**Action:** Delete hedging and narration. Keep only comments that document concrete constraints or known issues with
references.

### 6. Unnecessary Error Wrapping

Error handling that adds noise without context.

**Signals:**

- `return fmt.Errorf("error: %w", err)` — the word "error" adds nothing
- `return fmt.Errorf("failed to X: failed to Y: %w", err)` — double-wrapping with redundant context
- Over-wrapping at call sites: `fmt.Errorf("failed to do X: %w", fmt.Errorf("error doing X: %w", err))`
- Wrapping errors at every level of the call stack, creating messages like
  `"failed to process: failed to validate: failed to parse: invalid syntax"`
- Error messages that repeat the function name: `func Save() { return fmt.Errorf("Save: %w", err) }`

**Action:** Wrap errors once at the boundary where context is meaningful. Use the package/operation name, not redundant
verbiage. Let `errors.Is`/`errors.As` handle the chain.

**Ownership split with invariant-hunter:** slop owns *redundancy* of the wrapping messages; invariant-hunter owns
*correctness* of the error chain (`%w`, `Unwrap`, `errors.Is`/`errors.As`). The two recommendations compose: wrap
correctly, and wrap once where the context is meaningful.

## Audit Workflow

### Phase 1: Establish Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, and untracked
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project

   If unspecified, default to **diff** — unlike the other hunters, which default to codebase: this skill's purpose
   is reviewing freshly introduced (typically AI-assisted) changes, so the diff is its natural surface.

   **Party mode:** when the orchestrator supplies a scope snapshot (a resolved file list), use it verbatim and do
   not re-resolve. The resolution below applies to standalone runs only.

   For diff mode, resolve fail-closed:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
   if [ -z "$BASE" ]; then
     for b in origin/main origin/master main master; do
       git rev-parse -q --verify "$b" >/dev/null && BASE=$b && break
     done
   fi
   # If BASE is still empty: STOP. Ask for an explicit base. Do not continue.

   SCOPE=$( { git diff --name-only --diff-filter=d "$BASE"...HEAD;
              git diff --name-only --diff-filter=d HEAD;
              git ls-files --others --exclude-standard; } | sort -u )
   DELETED=$( { git diff --name-only --diff-filter=D "$BASE"...HEAD;
                git diff --name-only --diff-filter=D HEAD; } | sort -u )
   ```
   If `$SCOPE` is empty, run no scans: write the report with "Audit completed: 0 findings — empty diff scope",
   listing `$DELETED` under "Deleted in diff" if non-empty, and stop. If the resolved surface exceeds what can be
   read within the context budget, report the file count and ask to narrow or chunk.

   **Two surfaces.** Findings are reported only against the **target scope** (`$SCOPE`) — every finding anchors
   (file:line) there. Established files outside the scope are still *read* as **context** — that is how project
   conventions are identified (step 2).
2. Identify the project's style conventions by examining established files outside the audit surface.
3. Note the project's documentation patterns (godoc style, comment conventions, naming, import grouping).

### Phase 2: Scan for Noise

```bash
# Generated code is excluded (authoritative marker: a "// Code generated .* DO NOT EDIT." line before
# the first non-comment text; globs approximate) — noise in generated files is fixed by regenerating,
# not editing. Test files stay in scope: AI noise lands in tests too.
EXCLUDE='--glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'
```

In **diff mode**, focus on added lines to isolate new noise from pre-existing patterns:

```bash
# Added comments (single-line)
git diff "$BASE"...HEAD -- $SCOPE | rg '^\+\s*//'

# Added godoc blocks (multi-line doc comments)
git diff "$BASE"...HEAD -- $SCOPE | rg '^\+\s*/\*\*|^\+\s*//\s*[A-Z]\w+\s'
```

In **path/codebase mode**, scan the resolved surface directly (`SCOPE=.` in codebase mode):

```bash
# Comments (then classify manually)
rg '^\s*//' --type go $EXCLUDE -- $SCOPE

# Godoc on unexported functions
rg -B1 '^func\s+[a-z]' --type go $EXCLUDE --glob '!**/*_test.go' -- $SCOPE
```

In all modes, constrained to the resolved surface:

```bash
# TODO/FIXME markers
rg 'TODO|FIXME|HACK|XXX' --type go $EXCLUDE -- $SCOPE

# Log statements that narrate flow
rg 'log\.\w+\("(entering|exiting|starting|finished|begin|end)' --type go $EXCLUDE -- $SCOPE

# Redundant error wrapping
rg 'fmt\.Errorf\("(error|failed|err)' --type go $EXCLUDE -- $SCOPE

# nolint without justification
rg 'nolint' --type go $EXCLUDE -- $SCOPE

# gofmt check — gofmt -l has no exclusion mechanism and will list vendored/generated files;
# filter its output through the same exclusions before reporting
gofmt -l . | rg -v '^vendor/|/vendor/|\.pb\.go$|_gen\.go$|_generated\.go$'
```

### Phase 3: Classify Each Finding

For each finding, determine:

- Is this noise or does it add value?
- Does this match or break project conventions?
- Is this clearly AI-generated or an intentional choice?

### Phase 4: Produce Report

## Output Format

Save as `YYYY-MM-DD-slop-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies an
output path or return mode (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

```md
# Slop Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Audit completed: {N} findings

## Findings

### Redundant Comments

| # | Location | Comment | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `// Initialize the slice` | Delete |

### Verbose Godoc

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | Godoc on unexported helper with obvious behavior | Strip |

### Style Drift

| # | Location | Pattern | Project Convention | Action |
| - | -------- | ------- | ------------------ | ------ |
| 1 | file:line | `userName` variable | Project uses `username` | Rename |
| 2 | file:line | `GetUser()` method | Go convention: `User()` | Rename |

### Dead Code

| # | Location | Code | Action |
| - | -------- | ---- | ------ |
| 1 | file:line | Commented-out function | Delete |

### AI Verbal Patterns

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `// This is a workaround for...` (no issue link) | Delete or add reference |

### Unnecessary Error Wrapping

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `fmt.Errorf("error: %w", err)` | Simplify to meaningful context |

## Recommendations (Priority Order)

1. **High**: {style drift that breaks project conventions, gofmt violations}
2. **Medium**: {redundant comments, dead code, unnecessary error wrapping}
3. **Low**: {verbose godoc, AI verbal patterns}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: surface noise only.** If a finding doesn't answer "is this noise?", it belongs to another hunter — do
  not flag it here. Named boundaries: apply the comment ownership rule above for the doc/slop/smell split;
  commented-out code is owned here (simplicity keeps unreachable *logic*); error-wrapping *redundancy* is owned
  here while chain *correctness* belongs to invariant-hunter-go; naming drift in the audited change is owned here
  while stuttering belongs to smell-hunter-go.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code.
- **Preserve intent.** Flag noise, not substance. If a comment captures genuine design intent, keep it regardless of
  verbosity. In particular, comments that explain **why a non-obvious design was chosen over the seemingly simpler
  alternative** (e.g., "why not use two separate stoppages instead of a transitioning one") are design rationale, not
  noise — even if they run to 10+ lines. The test is: would removing this comment risk someone reimplementing the
  broken approach? If yes, the comment is load-bearing and must not be flagged.
- **Precedence: `gofmt` > project conventions > Effective Go.** `gofmt` formatting is mandatory — it is not a style
  choice. Project-specific conventions (naming, error handling, import grouping) take precedence next. Fall back to
  standard Go idioms (Effective Go, Code Review Comments wiki) only when the project has no established convention.
  When flagging drift, always cite the existing project pattern or the Go convention being applied.
