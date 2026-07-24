---
name: simplicity-hunter-ts
description: |
  Audit TypeScript code for unnecessary structural complexity — duplication, avoidable
  abstractions, dead logic paths, flag-heavy APIs, deep nesting, and mixed concerns.
  Recommends the simplest shape that preserves intended behavior.

  Use when: reviewing TypeScript code for over-engineering, reducing complexity after
  prototyping, enforcing reuse over addition, or simplifying before a refactor.
disable-model-invocation: true
---

# Simplicity Hunter

Audit TypeScript code for **structural complexity** — places where logic is duplicated, abstractions don't earn their keep, control
flow is deeper than it needs to be, or concerns are mixed. The goal: **the simplest code that preserves intended
behavior.**

## When to Use

- Reviewing new code for over-engineering or unnecessary indirection
- Reducing complexity after initial prototyping
- Enforcing reuse over addition before merging
- Preparing code for long-term maintainability
- Deduplicating logic across production modules

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

Repeated logic across production functions and modules. (Duplication *within test code* — copied setup, repeated
assertion blocks — is test-hunter's finding; do not flag it here.)

**Signals:**

- Two functions with near-identical bodies differing only in a value or branch
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
- A function or module body that mixes abstraction levels (raw I/O plumbing interleaved with domain decisions)
- Long functions (50+ lines) with distinct logical sections separated by blank lines or comments

(Responsibility analysis of *classes* — methods spanning concerns, multiple reasons to change — is solid-hunter's
SRP territory; keep this signal at function/module level.)

**Action:** Extract each concern into a named helper. The parent function becomes a coordinator.

### 6. Complex Control Flow

Deep nesting, nested ternaries, long `if/else if` chains, convoluted loops, and unflattened async control flow.

**Signals:**

- 3+ levels of nesting
- Nested ternaries (`a ? b ? c : d : e`)
- `if/else if` chains with 4+ branches
- Loop bodies with embedded conditionals
- 3+ levels of nested callbacks (Node.js-style `(err, result) => { ... }`)
- `.then().then().then()` chains longer than 3 steps, or nested `.then()` "promise pyramids"
- Mixing callbacks and promises in the same function
- Error handling scattered across multiple `.catch()` blocks where a single `try`/`catch` would do

**Action:** Flatten with guard clauses and early returns. Replace nested ternaries with explicit conditionals. Extract
loop bodies into named functions when complex. Convert callback pyramids and long `.then()` chains to `async`/`await`
with `try`/`catch`; use `Promise.all()`/`Promise.allSettled()` for genuinely parallel work.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, and untracked
   - **Path**: specific files, folders, or layers
   - **Codebase**: the entire project (the default when unspecified; set `SCOPE=.`)

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
   (file:line) there. Related files may still be *read* as **context**: when judging duplication, search the whole
   project for the canonical implementation and existing helpers.
2. Understand the project's existing helpers, utilities, and conventions.
3. Note any stated design decisions (e.g., intentional duplication for performance).

### Phase 2: Scan for Complexity Signals

Run every scan against the target scope (`SCOPE=.` in codebase mode).

```bash
# Production-scan exclusions: dependencies, build output, generated code, tests
# (test-code complexity and duplication belong to test-hunter)
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

# Deep nesting (4+ indentation levels, 2-space indent)
rg '^\s{8,}\S' --type ts $EXCLUDE -- $SCOPE

# Boolean parameters
rg --pcre2 '\w+\s*[?:]?\s*:\s*boolean' --type ts $EXCLUDE -- $SCOPE

# Functions with many parameters (declarations, arrow functions, methods)
rg --pcre2 'function\s+\w+\s*\([^)]{80,}\)' --type ts $EXCLUDE -- $SCOPE
rg --pcre2 '(?:const|let)\s+\w+\s*=\s*(?:async\s+)?\([^)]{80,}\)\s*(?:=>|:)' --type ts $EXCLUDE -- $SCOPE
rg --pcre2 '^\s+\w+\s*\([^)]{80,}\)\s*[:{]' --type ts $EXCLUDE -- $SCOPE

# Nested ternaries
rg --pcre2 '\?[^:]+\?' --type ts $EXCLUDE -- $SCOPE

# Callback pyramids and long .then() chains
rg --pcre2 '\.then\([^)]*\)\s*\.then\([^)]*\)\s*\.then' --type ts $EXCLUDE -- $SCOPE
```

### Phase 3: Scan for Duplication

1. Identify repeated patterns across files using targeted searches.
2. Look for multiple implementations of the same logic with minor variations.

### Phase 4: Evaluate Each Finding

For each complexity signal, determine:

- Is this genuinely unnecessary, or does it serve a purpose?
- What is the simplest change that eliminates it?
- Does the simplification break any public API? If so, flag but default to follow-up.

### Phase 5: Produce Report

## Output Format

Save as `YYYY-MM-DD-simplicity-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies
an output path (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

```md
# Simplicity Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Audit completed: {N} findings

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

1. **High**: {high-impact duplication, dead code with confidence}
2. **Medium**: {unnecessary abstractions, over-parameterized APIs}
3. **Low**: {control flow improvements, concern separation}
```

(Structural complexity is rarely Critical on its own; use Critical only when a duplicated or dead path is actively
producing wrong behavior in production.)

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: structural complexity in production code only.** If a finding doesn't answer "is this simpler than it
  could be?", it belongs to another hunter — do not flag it here. Test-code duplication and setup bloat belong to
  test-hunter; class-level responsibility analysis belongs to solid-hunter.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact code.
- **Reuse over addition.** When recommending a fix, prefer existing helpers or deletion over new code.
- **Preserve behavior.** Never recommend changes that alter what the code does, only how it's structured.
- **Pragmatism.** Not every abstraction is wrong. Flag, assess, and acknowledge intentional complexity. If a
  simplification breaks public APIs or backwards compatibility, call it out and default to follow-up.
