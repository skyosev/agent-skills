---
name: simplicity-hunter
description: |
  Audit code for unnecessary structural complexity — duplication, avoidable abstractions,
  dead logic paths, flag-heavy APIs, deep nesting, and mixed concerns. Recommends the
  simplest shape that preserves intended behavior.

  Use when: reviewing new code for over-engineering, reducing complexity after prototyping,
  enforcing reuse over addition, or simplifying before a refactor.
---

# Simple Hunter

Audit code for **structural complexity** — places where logic is duplicated, abstractions don't earn their keep, control
flow is deeper than it needs to be, or concerns are mixed. The goal: **the simplest code that preserves intended
behavior.**

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

4. **Flags are complexity multipliers.** Each boolean parameter doubles the logic paths. Prefer one linear flow; if a
   flag is unavoidable, require sharp naming and a removal plan.

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

**Action:** Choose one canonical implementation; delete the rest; extract shared logic only if it serves 2+ genuine
consumers.

### 2. Unnecessary Abstractions

Wrappers, managers, registries, or factories that serve a single call site or add no logic.

**Signals:**

- A class/function that delegates to one other function with no transformation
- A "manager" that wraps a single resource
- A factory that returns only one type
- An interface with a single implementation and no plan for more

**Action:** Inline the abstraction. If it exists for testability, note that and keep if justified.

### 3. Dead Code Paths

Unreachable branches, unused internal helpers, stale feature flags, and leftover alternate implementations.

**Signals:**

- `if` branches that can never be true given the input types or call sites
- Internal helper functions with zero call sites (exported dead symbols are boundary-hunter territory)
- Feature flags that are always on/off
- Commented-out alternate implementations

**Action:** Delete. If uncertain, flag with evidence of zero usage.

### 4. Over-Parameterized APIs

Functions with many optional parameters, boolean flags, or configuration objects that create a combinatorial explosion.

**Signals:**

- 4+ parameters, especially booleans
- Functions with `if (opts.X)` branches for most parameters
- Configuration objects where most fields are optional and defaulted

**Action:** Split into focused functions per use case, or reduce to the parameters actually used by callers.

### 5. Mixed Concerns

Single functions or classes that handle multiple unrelated responsibilities.

**Signals:**

- A function that fetches data AND transforms it AND renders output
- A class with methods spanning different abstraction levels
- Long functions (50+ lines) with distinct logical sections separated by blank lines or comments

**Action:** Extract each concern into a named helper. The parent function becomes a coordinator.

### 6. Complex Control Flow

Deep nesting, nested ternaries, long `if/else if` chains, and convoluted loops.

**Signals:**

- 3+ levels of nesting
- Nested ternaries (`a ? b ? c : d : e`)
- `if/else if` chains with 4+ branches
- Loop bodies with embedded conditionals

**Action:** Flatten with guard clauses and early returns. Replace nested ternaries with explicit conditionals. Extract
loop bodies into named functions when complex.

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
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/**'

# Deep nesting (4+ indentation levels, 2-space indent)
rg '^\s{8,}\S' --type ts $EXCLUDE

# Boolean parameters
rg --pcre2 '\w+\s*[?:]?\s*:\s*boolean' --type ts $EXCLUDE

# Functions with many parameters (long param lists)
rg --pcre2 'function\s+\w+\s*\([^)]{80,}\)' --type ts $EXCLUDE

# Nested ternaries
rg --pcre2 '\?[^:]+\?' --type ts $EXCLUDE
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

Save as `Y-m-d-simplicity-hunter-audit.md` in the project's docs folder.

```md
# Simple Hunter Audit — {date}

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
| 1 | file:line | `legacyHandler()` | 0 internal call sites | Delete |

### Over-Parameterized APIs

| # | Location | Function | Params | Action |
| - | -------- | -------- | ------ | ------ |
| 1 | file:line | `render(a, b, c, d, e)` | 5 (3 booleans) | Split by use case |

### Mixed Concerns

| # | Location | Function | Concerns | Action |
| - | -------- | -------- | -------- | ------ |
| 1 | file:line | `processOrder()` | fetch + transform + log | Extract into 3 helpers |

### Complex Control Flow

| # | Location | Pattern | Depth | Action |
| - | -------- | ------- | ----- | ------ |
| 1 | file:line | Nested ternary | 3 | Replace with conditional |

## Recommendations (Priority Order)

1. **Must-fix**: {high-impact duplication, dead code with confidence}
2. **Should-fix**: {unnecessary abstractions, over-parameterized APIs}
3. **Consider**: {control flow improvements, concern separation}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: structural complexity only.** Do not flag type invariants (→ invariant-hunter), type design
  (→ type-hunter), module boundary issues (→ boundary-hunter), class/interface design (→ solid-hunter), missing
  documentation (→ doc-hunter), security (→ security-hunter), test quality (→ test-hunter), or cosmetic style
  (→ slop-hunter). If a finding doesn't answer "is this simpler than it could be?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact code.
- **Reuse over addition.** When recommending a fix, prefer existing helpers or deletion over new code.
- **Preserve behavior.** Never recommend changes that alter what the code does, only how it's structured.
- **Pragmatism.** Not every abstraction is wrong. Flag, assess, and acknowledge intentional complexity. If a
  simplification breaks public APIs or backwards compatibility, call it out and default to follow-up.
