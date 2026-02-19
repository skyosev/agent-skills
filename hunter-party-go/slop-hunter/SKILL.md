---
name: slop-hunter
description: |
  Audit Go code for AI-generated noise — redundant comments, verbose documentation, style
  drift from project conventions and gofmt, trivially dead code, and unnecessary error
  wrapping. Surface-level hygiene pass; defaults to branch diff but supports any scope.

  Use when: reviewing AI-assisted Go code before merge, cleaning up generated code,
  enforcing project style on new contributions, or reducing review noise.
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
- Over-wrapping errors: `fmt.Errorf("failed to do X: %w", fmt.Errorf("error doing X: %w", err))`
- Excessive `nil` checks already guaranteed by preceding logic

**Action:** Delete hedging and narration. Keep only comments that document concrete constraints or known issues with
references.

### 6. Unnecessary Error Wrapping

Error handling that adds noise without context.

**Signals:**

- `return fmt.Errorf("error: %w", err)` — the word "error" adds nothing
- `return fmt.Errorf("failed to X: failed to Y: %w", err)` — double-wrapping with redundant context
- Wrapping errors at every level of the call stack, creating messages like
  `"failed to process: failed to validate: failed to parse: invalid syntax"`
- Error messages that repeat the function name: `func Save() { return fmt.Errorf("Save: %w", err) }`

**Action:** Wrap errors once at the boundary where context is meaningful. Use the package/operation name, not redundant
verbiage. Let `errors.Is`/`errors.As` handle the chain.

## Audit Workflow

### Phase 1: Establish Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project
   If unspecified, default to **diff**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent scans to the resolved surface.
2. Identify the project's style conventions by examining established files outside the audit surface.
3. Note the project's documentation patterns (godoc style, comment conventions, naming, import grouping).

### Phase 2: Scan for Noise

In **diff mode**, focus on added lines to isolate new noise from pre-existing patterns:

```bash
# Added comments (single-line)
git diff $(git merge-base HEAD $BASE)...HEAD | rg '^\+\s*//'

# Added godoc blocks (multi-line doc comments)
git diff $(git merge-base HEAD $BASE)...HEAD | rg '^\+\s*/\*\*|^\+\s*//\s*[A-Z]\w+\s'
```

In **path/codebase mode**, scan the resolved surface directly:

```bash
EXCLUDE='--glob !**/vendor/** --glob !**/testdata/**'

# Comments (then classify manually)
rg '^\s*//' --type go $EXCLUDE

# Godoc on unexported functions
rg -B1 '^func\s+[a-z]' --type go $EXCLUDE --glob '!**/*_test.go'
```

In all modes:

```bash
# TODO/FIXME markers
rg 'TODO|FIXME|HACK|XXX' --type go

# Log statements that narrate flow
rg 'log\.\w+\("(entering|exiting|starting|finished|begin|end)' --type go

# Redundant error wrapping
rg 'fmt\.Errorf\("(error|failed|err)' --type go

# nolint without justification
rg 'nolint' --type go

# gofmt check
gofmt -l .
```

### Phase 3: Classify Each Finding

For each finding, determine:

- Is this noise or does it add value?
- Does this match or break project conventions?
- Is this clearly AI-generated or an intentional choice?

### Phase 4: Produce Report

## Output Format

Save as `YYYY-MM-DD-slop-hunter-audit.md` in the project's docs folder (or project root if no docs folder exists).

```md
# Slop Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

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

1. **Must-fix**: {style drift that breaks project conventions, gofmt violations}
2. **Should-fix**: {redundant comments, dead code, unnecessary error wrapping}
3. **Consider**: {verbose godoc, AI verbal patterns}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: surface noise only.** Do not flag type safety (→ invariant-hunter), type design (→ type-hunter),
  structural complexity (→ simplicity-hunter), package boundary issues (→ boundary-hunter), interface design
  (→ solid-hunter), missing documentation (→ doc-hunter), security (→ security-hunter), or test quality
  (→ test-hunter). If a finding doesn't answer "is this noise?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code.
- **Preserve intent.** Flag noise, not substance. If a comment captures genuine design intent, keep it regardless of
  verbosity.
- **Precedence: `gofmt` > project conventions > Effective Go.** `gofmt` formatting is mandatory — it is not a style
  choice. Project-specific conventions (naming, error handling, import grouping) take precedence next. Fall back to
  standard Go idioms (Effective Go, Code Review Comments wiki) only when the project has no established convention.
  When flagging drift, always cite the existing project pattern or the Go convention being applied.
