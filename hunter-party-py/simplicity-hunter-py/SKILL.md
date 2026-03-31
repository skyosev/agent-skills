---
name: simplicity-hunter-py
description: |
  Audit Python code for unnecessary structural complexity — duplication, avoidable
  abstractions, dead logic paths, flag-heavy APIs, deep nesting, and mixed concerns.
  Recommends the simplest shape that preserves intended behavior.

  Use when: reviewing Python code for over-engineering, reducing complexity after
  prototyping, enforcing reuse over addition, or simplifying before a refactor.
disable-model-invocation: true  
---

# Simplicity Hunter

Audit Python code for **structural complexity** — places where logic is duplicated, abstractions don't earn their keep,
control flow is deeper than it needs to be, or concerns are mixed. The goal: **the simplest code that preserves
intended behavior.**

## When to Use

- Reviewing new code for over-engineering or unnecessary indirection
- Reducing complexity after initial prototyping
- Enforcing reuse over addition before merging
- Preparing code for long-term maintainability
- Deduplicating logic across modules or tests

## Core Principles

1. **Default to delete.** The best simplification is removal. If code can be deleted without changing behavior, delete
   it. If it can be replaced by an existing helper, replace it.

2. **One canonical path.** When two implementations do the same thing, pick one and remove the other. Avoid "shared
   helper + keep both paths" unless required by genuinely different consumers.

3. **Abstractions must earn their place.** Reject new wrappers, managers, and factories unless they reduce total
   complexity through reuse. An abstraction that serves one call site is indirection, not simplification.

4. **Flags are complexity multipliers.** Each boolean parameter can double the logic paths. Prefer one linear flow;
   if a flag is unavoidable, require sharp naming. Stable boolean flags with clear, well-documented semantics
   (e.g., `recursive: bool` on a filesystem operation) are acceptable.

5. **Inline the trivial.** Pass-through wrappers, single-use helpers, and indirection layers that add no logic should be
   inlined. Measure value by what the wrapper adds, not by what it hides.

6. **Separate concerns, don't mix them.** A function that builds data AND formats output AND logs errors has three
   reasons to change. Split into focused helpers with intent-revealing names.

7. **Flatten, don't nest.** Deep nesting (3+ levels) signals mixed concerns or missing early returns. Use guard clauses
   and early returns to keep the main path at low indentation.

## What to Hunt

### 1. Duplication

Repeated logic across functions, modules, or tests.

**Signals:**

- Two functions with near-identical bodies differing only in a value or branch
- Test files with copied setup/assertion blocks
- Multiple implementations of the same algorithm
- Copy-pasted list/dict comprehensions with minor variations

**Action:** Choose one canonical implementation; delete the rest; extract shared logic only if it serves 2+ genuine
consumers.

### 2. Unnecessary Abstractions

Wrappers, managers, registries, or factories that serve a single call site or add no logic.

**Signals:**

- A class/function that delegates to one other function with no transformation
- A "manager" that wraps a single resource
- A factory that returns only one type
- An ABC/Protocol with a single implementation and no plan for more — *unless* the Protocol exists to enable
  test doubles, define a dependency injection boundary, or stabilize a real architectural seam
- A decorator that does nothing beyond calling the wrapped function

**Action:** Inline the abstraction. If it exists for testability, note that and keep if justified.

### 3. Dead Code Paths

Unreachable branches, unused internal helpers, stale feature flags, and leftover alternate implementations.

**Signals:**

- `if` branches that can never be true given the input types or call sites
- Internal helper functions with zero call sites (exported dead symbols are boundary-hunter territory)
- Feature flags that are always on/off
- Commented-out alternate implementations
- `elif`/`else` branches that handle cases already ruled out by prior conditions

**Action:** Delete. If uncertain, flag with evidence of zero usage.

### 4. Over-Parameterized APIs

Functions with many optional parameters, boolean flags, or configuration dicts that create a combinatorial explosion.

**Signals:**

- 4+ parameters, especially booleans
- Functions with `if opts.get('X')` branches for most parameters
- `**kwargs` used as a catch-all configuration pass-through
- Configuration dicts where most fields are optional and defaulted

**Action:** Split into focused functions per use case, or reduce to the parameters actually used by callers.

### 5. Mixed Concerns

Single functions or classes that handle multiple unrelated responsibilities.

**Signals:**

- A function that fetches data AND transforms it AND renders output
- A class with methods spanning different abstraction levels
- Long functions (50+ lines) with distinct logical sections separated by blank lines or comments
- A single function doing I/O, business logic, and formatting

**Action:** Extract each concern into a named helper. The parent function becomes a coordinator.

### 6. Complex Control Flow

Deep nesting, nested ternaries, long `if/elif` chains, and convoluted loops.

**Signals:**

- 3+ levels of nesting
- Nested conditional expressions (`a if b else (c if d else e)`)
- `if/elif` chains with 4+ branches
- Loop bodies with embedded conditionals
- Complex comprehensions with multiple `if` clauses and nested loops

**Action:** Flatten with guard clauses and early returns. Replace nested conditional expressions with explicit
conditionals. Extract loop bodies into named functions when complex.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or layers
   - **Codebase**: the entire project
   If unspecified, default to **codebase**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent scans to the resolved surface.
2. Understand the project's existing helpers, utilities, and conventions.
3. Note any stated design decisions (e.g., intentional duplication for performance).

### Phase 2: Scan for Complexity Signals

```bash
EXCLUDE='--glob !**/venv/** --glob !**/.venv/** --glob !**/dist/**'

# Deep nesting (4+ indentation levels, 4-space indent)
rg '^\s{16,}\S' --type py $EXCLUDE

# Boolean parameters
rg --pcre2 '\w+\s*:\s*bool\b' --type py $EXCLUDE

# Functions with many parameters
rg --pcre2 'def\s+\w+\s*\([^)]{80,}\)' --type py $EXCLUDE

# **kwargs catch-all
rg '\*\*kwargs' --type py $EXCLUDE

# Nested conditional expressions
rg --pcre2 'if\s+.*\s+else\s+.*\s+if\s+' --type py $EXCLUDE

# Long functions (files with significant line spans between def statements)
rg 'def\s+\w+' --type py $EXCLUDE -n
```

### Phase 3: Scan for Duplication

1. Identify repeated patterns across files using targeted searches.
2. Check test files for copied setup and assertion blocks.
3. Look for multiple implementations of the same logic with minor variations.

### Phase 4: Evaluate Each Finding

For each complexity signal, determine:

- Is this genuinely unnecessary, or does it serve a purpose?
- What is the simplest change that eliminates it?
- Does the simplification break any public API? If so, flag but default to follow-up.

### Phase 5: Produce Report

## Output Format

Save as `YYYY-MM-DD-simplicity-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs
folder exists).

```md
# Simplicity Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Findings

### Duplication

| # | Locations | Description | Action |
| - | --------- | ----------- | ------ |
| 1 | file:line, file:line | Near-identical validation logic | Deduplicate into shared helper |

### Unnecessary Abstractions

| # | Location | Abstraction | Consumers | Action |
| - | -------- | ----------- | --------- | ------ |
| 1 | file:line | `ConfigManager` class | 1 | Inline |

### Dead Code Paths

| # | Location | Code | Evidence | Action |
| - | -------- | ---- | -------- | ------ |
| 1 | file:line | `legacy_handler()` | 0 internal call sites | Delete |

### Over-Parameterized APIs

| # | Location | Function | Params | Action |
| - | -------- | -------- | ------ | ------ |
| 1 | file:line | `render(a, b, c, d, e)` | 5 (3 booleans) | Split by use case |

### Mixed Concerns

| # | Location | Function | Concerns | Action |
| - | -------- | -------- | -------- | ------ |
| 1 | file:line | `process_order()` | fetch + transform + log | Extract into 3 helpers |

### Complex Control Flow

| # | Location | Pattern | Depth | Action |
| - | -------- | ------- | ----- | ------ |
| 1 | file:line | Nested conditional expression | 3 | Replace with if/elif |

## Recommendations (Priority Order)

1. **Must-fix**: {high-impact duplication, dead code with confidence}
2. **Should-fix**: {unnecessary abstractions, over-parameterized APIs}
3. **Consider**: {control flow improvements, concern separation}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: structural complexity only.** Do not flag type invariants (→ invariant-hunter-py), type design
  (→ type-hunter-py), module boundary issues (→ boundary-hunter-py), class/interface design (→ solid-hunter-py), missing
  documentation (→ doc-hunter-py), security (→ security-hunter-py), test quality (→ test-hunter-py), or cosmetic style
  (→ slop-hunter-py). If a finding doesn't answer "is this simpler than it could be?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.py:line` with the exact code.
- **Reuse over addition.** When recommending a fix, prefer existing helpers or deletion over new code.
- **Preserve behavior.** Never recommend changes that alter what the code does, only how it's structured.
- **Pragmatism.** Not every abstraction is wrong. Flag, assess, and acknowledge intentional complexity. If a
  simplification breaks public APIs or backwards compatibility, call it out and default to follow-up.
