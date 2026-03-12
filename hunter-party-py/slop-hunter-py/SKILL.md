---
name: slop-hunter-py
description: |
  Audit Python code for AI-generated noise — redundant comments, verbose documentation,
  style drift from project conventions, and trivially dead code. Surface-level hygiene
  pass; defaults to branch diff but supports any scope.

  Use when: reviewing AI-assisted Python code before merge, cleaning up generated code,
  enforcing project style on new contributions, or reducing review noise.
---

# Slop Hunter

Audit code for **AI-generated noise** — comments that narrate the obvious, documentation that restates code, style
choices that break project conventions, and dead code that slipped in. The goal: **the code reads like a human wrote it,
following existing project idioms.**

## When to Use

- Reviewing AI-assisted code before merge
- Cleaning up a branch after heavy AI pair-programming
- Enforcing project conventions on generated contributions
- Reducing noise in pull request reviews

## Core Principles

1. **Default to the diff.** When scoped to a branch diff, only flag patterns introduced in this branch — pre-existing
   issues are out of scope. When scoped to a path or codebase, flag all matching patterns in the resolved surface.

2. **Comments explain why, not what.** A comment that restates the code ("increment counter") is noise. A comment that
   explains intent, constraints, or non-obvious decisions ("rate limit: 3rd-party API allows 100 req/min") is valuable.

3. **Style is not cosmetic.** Drift from project conventions increases cognitive load for every future reader. New code
   must conform to existing patterns, not introduce alternatives.

4. **Less is more.** AI tends to over-document, over-explain, and over-hedge. Strip to the minimum that preserves
   clarity.

## What to Hunt

### 1. Redundant Comments

Comments that narrate obvious behavior, restate function/variable names, or explain standard language constructs.

**Signals:**

- `# Initialize the list` above `items = []`
- `# Return the result` above `return result`
- Comments explaining standard library usage
- Section dividers (`# ---- Helper Functions ----`) in small files
- `# Loop through items` above `for item in items:`

**Action:** Delete. If the code needs explanation, it should be rewritten for clarity first.

### 2. Verbose Documentation

Over-documentation that adds noise without insight — typically AI-generated docstrings on every function including
trivial private helpers.

**Signals:**

- Docstrings on private/internal functions with obvious behavior
- `:param name:` descriptions that repeat the parameter name ("name: the name")
- `:returns:` that restates the return type annotation
- README sections that describe implementation details instead of usage
- Docstrings on `__init__` that just list the parameters being assigned to `self`
- Google/NumPy-style docstrings where every section is present but adds nothing beyond the signature

**Action:** Keep docstrings only on public API. Strip params/returns that add nothing beyond the type annotation.

### 3. Style Drift

Patterns that diverge from the project's established conventions in naming, formatting, structure, or idioms.

**Signals:**

- Different naming convention (camelCase where project uses snake_case, or vice versa)
- Different error handling pattern than established code
- Different import ordering or grouping (stdlib → third-party → local convention violated)
- Different file/folder organization than existing modules
- f-strings where project uses `.format()` (or vice versa)
- Verbose loops where project idiom uses comprehensions (or vice versa)
- `pathlib` vs `os.path` inconsistency with project convention

**Action:** Conform to existing project conventions. Cite the existing pattern as evidence.

### 4. Trivially Dead Code

Unused imports, unused variables, commented-out code blocks, and placeholder TODOs.

**Signals:**

- `import X` where X is never used in the file
- `x = ...` where x is never referenced
- Blocks of commented-out code (`# old_result = ...`)
- `# TODO: implement` or `# FIXME` without actionable context
- `pass` in non-empty functions/methods (leftover placeholder)

**Action:** Delete unused imports/variables. Delete commented-out code. Convert vague TODOs to actionable tickets or
delete.

### 5. AI-Specific Verbal Patterns

Hedging language, apologetic comments, and over-explanation typical of AI-generated code.

**Signals:**

- `# This is a workaround for...` without specifying the issue
- `# Note: this might need to be updated if...` (speculative)
- `# For safety, we also check...` (unnecessary hedging)
- `# New, improved version..` (references old code)
- Logging that narrates execution flow (`logger.debug('entering function X')`)
- `# Handle the case where...` before a trivial None check

**Action:** Delete hedging and narration. Keep only comments that document concrete constraints or known issues with
references.

## Audit Workflow

### Phase 1: Establish Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or layers
   - **Codebase**: the entire project
   If unspecified, default to **diff**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent scans to the resolved surface.
2. Identify the project's style conventions by examining established files outside the audit surface.
3. Note the project's documentation patterns (docstring style — Google, NumPy, Sphinx; comment conventions; naming).

### Phase 2: Scan for Noise

In **diff mode**, focus on added lines to isolate new noise from pre-existing patterns:

```bash
# Added comments
git diff $(git merge-base HEAD $BASE)...HEAD | rg '^\+.*#'

# Added docstrings
git diff $(git merge-base HEAD $BASE)...HEAD | rg '^\+.*("""|:param|:returns|Args:|Returns:)'
```

In **path/codebase mode**, scan the resolved surface directly:

```bash
EXCLUDE='--glob !**/venv/** --glob !**/.venv/** --glob !**/dist/**'

# Comments (then classify manually)
rg '^\s*#' --type py $EXCLUDE -- $SCOPE

# Docstring blocks
rg '"""' --type py $EXCLUDE -- $SCOPE
```

In all modes:

```bash
# TODO/FIXME markers
rg 'TODO|FIXME|HACK|XXX' -- $SCOPE

# Print/logging statements that narrate flow
rg 'print\(|logger\.(debug|info)' -- $SCOPE
```

### Phase 3: Classify Each Finding

For each finding, determine:

- Is this noise or does it add value?
- Does this match or break project conventions?
- Is this clearly AI-generated or an intentional choice?

### Phase 4: Produce Report

## Output Format

Save as `YYYY-MM-DD-slop-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs folder
exists).

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
| 1 | file:line | `# Initialize the list` | Delete |

### Verbose Documentation

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | Docstring on private helper with obvious behavior | Strip |

### Style Drift

| # | Location | Pattern | Project Convention | Action |
| - | -------- | ------- | ------------------ | ------ |
| 1 | file:line | `camelCase` variable | Project uses `snake_case` | Rename |

### Dead Code

| # | Location | Code | Action |
| - | -------- | ---- | ------ |
| 1 | file:line | Unused import `X` | Delete |

### AI Verbal Patterns

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `# This is a workaround for...` | Delete or add specific issue reference |

## Recommendations (Priority Order)

1. **Must-fix**: {style drift that breaks project conventions}
2. **Should-fix**: {redundant comments, dead code}
3. **Consider**: {verbose docs, AI verbal patterns}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: surface noise only.** Do not flag type invariants (→ invariant-hunter-py), type design (→ type-hunter-py),
  structural complexity (→ simplicity-hunter-py), module boundary issues (→ boundary-hunter-py), class/interface design
  (→ solid-hunter-py), missing documentation (→ doc-hunter-py), security (→ security-hunter-py), or test quality
  (→ test-hunter-py). If a finding doesn't answer "is this noise?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.py:line` with the exact code.
- **Preserve intent.** Flag noise, not substance. If a comment captures genuine design intent, keep it regardless of
  verbosity.
- **Project conventions are the standard.** Always cite existing project patterns when flagging drift.
