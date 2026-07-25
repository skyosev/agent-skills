---
name: simplicity-hunter-go
description: |
  Audit Go code for unnecessary structural complexity — duplication, avoidable abstractions,
  dead logic paths, over-parameterized APIs, deep nesting, interface pollution, channel
  misuse, and mixed concerns. Recommends the simplest shape that preserves intended behavior.

  Use when: reviewing Go code for over-engineering, reducing complexity after prototyping,
  enforcing reuse over addition, or simplifying before a refactor.
disable-model-invocation: true
---

# Simplicity Hunter

Audit Go code for **structural complexity** — places where logic is duplicated, abstractions don't earn their keep,
control flow is deeper than it needs to be, or concerns are mixed. The goal: **the simplest code that preserves
intended behavior.**

## When to Use

- Reviewing new code for over-engineering or unnecessary indirection
- Reducing complexity after initial prototyping
- Enforcing reuse over addition before merging
- Preparing code for long-term maintainability
- Deduplicating logic across packages (duplication *within test code* belongs to test-hunter-go)

## Core Principles

1. **Default to delete.** The best simplification is removal. If code can be deleted without changing behavior, delete
   it. If it can be replaced by an existing function, replace it.

2. **One canonical path.** When two implementations do the same thing, pick one and remove the other. Avoid "shared
   helper + keep both paths" unless required by genuinely different consumers.

3. **Abstractions must earn their place.** Reject new wrappers, managers, and factories unless they reduce total
   complexity through reuse. An interface that serves one call site and has one implementation is indirection, not
   simplification.

4. **Flags are complexity multipliers.** Each boolean parameter doubles the logic paths. Prefer one linear flow; if a
   flag is unavoidable, require sharp naming and a removal plan.

5. **Inline the trivial.** Pass-through wrappers, single-use helpers, and indirection layers that add no logic should be
   inlined. Measure value by what the wrapper adds, not by what it hides.

6. **Separate concerns, don't mix them.** A function that fetches data AND transforms it AND logs errors has three
   reasons to change. Split into focused functions with intent-revealing names.

7. **Flatten, don't nest.** Deep nesting (3+ levels) signals mixed concerns or missing early returns. Use guard clauses
   and early returns to keep the main path at low indentation.

8. **Channels are not always the answer.** A mutex protecting a map is simpler than a channel-based worker pattern for
   simple state. Use channels for communication, mutexes for state protection.

## What to Hunt

### 1. Duplication

Repeated logic across functions, packages, or tests.

**Signals:**

- Two functions with near-identical bodies differing only in a value or branch
- Multiple implementations of the same algorithm
- Identical error handling patterns repeated across handlers

(Duplicated setup/assertion blocks in test files are test-hunter-go's finding — do not flag test duplication here.)

**Action:** Choose one canonical implementation; delete the rest; extract shared logic only if it serves 2+ genuine
consumers.

### 2. Unnecessary Abstractions

Wrappers, managers, registries, or factories that serve a single call site or add no logic.

**Signals:**

- An interface with a single implementation and no test doubles
- A function that delegates to one other function with no transformation
- A "manager" struct that wraps a single resource
- A factory function that returns only one type
- A package with one exported function that just calls another package

**Action:** Inline the abstraction. If it exists for testability, note that and keep if justified.

### 3. Dead Code Paths

Unreachable branches, unused internal functions, stale feature flags, and leftover alternate implementations.

**Signals:**

- `if` branches that can never be true given the input types or call sites
- Unexported functions with zero call sites (exported dead symbols are boundary-hunter territory)
- Feature flags that are always on/off
- `default` cases in type switches that can never trigger (all types handled)

(Commented-out code blocks are slop-hunter's finding — this skill keeps unreachable *logic*, not dead text.)

**Action:** Delete. If uncertain, flag with evidence of zero usage.

### 4. Over-Parameterized APIs

Functions with many parameters, boolean flags, or option structs that create a combinatorial explosion.
**Ownership:** boolean-parameter findings are owned here (this section carries the calibrated do-not-flag rule).
solid-hunter claims only booleans that select between behaviors that will grow variants (an OCP setup);
smell-hunter does not flag them at all.

**Signals:**

- 5+ parameters, especially booleans
- Functions with `if opts.X` branches for most fields
- Option structs where most fields are zero-valued in all call sites
- Functional options pattern (`With*` functions) applied to functions with 1-2 options

**Do not flag:**

- 3 or fewer boolean parameters with well-descriptive names and ≤3 callers. The cure (a struct type + constructor) is
  heavier than the disease. Flag only when the boolean count causes real confusion or the caller count is high enough
  to justify the abstraction cost.

**Action:** Split into focused functions per use case, or reduce to the parameters actually used by callers. Reserve
functional options for truly variadic configuration.

### 5. Interface Pollution

Interfaces created for theoretical extensibility rather than actual need.

**Signals:**

- Interface with one implementation and no test double
- Interface defined in the same package as its only implementation
- Interface that mirrors a concrete struct's full method set
- "Just in case" interfaces that have existed for months without a second implementation

**Action:** Remove the interface and use the concrete type. Introduce the interface when a second implementation or
test double is actually needed.

### 6. Mixed Concerns

Single functions or types that handle multiple unrelated responsibilities.

**Signals:**

- A function that makes HTTP calls AND parses responses AND updates the database
- A handler that validates input AND applies business logic AND formats output
- Long functions (50+ lines) with distinct logical sections
- A struct with methods spanning different abstraction levels

**Do not flag:**

- **Dispatcher/coordinator functions** whose sole job is to route to the right handler based on a discriminant. A
  function that switches on a type and delegates each case to a separate function is a coordinator — that IS its
  single responsibility. Flag only when the dispatch function also contains substantial inline business logic in
  each case arm.

**Action:** Extract each concern into a named function. The parent function becomes a coordinator.

### 7. Complex Control Flow

Deep nesting, nested conditionals, and convoluted loops.

**Signals:**

- 3+ levels of nesting
- `if/else if` chains with 4+ branches (consider a switch or map lookup)
- Loop bodies with embedded conditionals
- Error handling that creates pyramid-shaped code (but note: `if err != nil { return }` guard clauses are idiomatic
  Go, not a nesting problem — flag only when error handling creates genuinely deep indentation)

**Action:** Flatten with guard clauses and early returns. Replace nested conditionals with switch statements or map
lookups. Extract loop bodies into named functions when complex.

### 8. Channel and Goroutine Overuse

Concurrency patterns more complex than the problem requires.

**Signals:**

- Channel used where a mutex-protected variable would suffice
- Goroutine launched for a single synchronous operation
- Worker pool pattern for a bounded, predictable workload
- Channel of channels (metachannel)
- `select` with a single case and no timeout

**Action:** Use the simplest concurrency primitive that works. Mutex for state, channel for communication, goroutine
for actual parallelism.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, and untracked
   - **Path**: specific files, folders, or packages
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
   (file:line) there. Related files may still be *read* as **context**: confirming that a helper is single-use or
   an interface single-implementation requires checking call sites outside the scope.
2. Understand the project's existing helpers, utilities, and conventions.
3. Note any stated design decisions (e.g., intentional duplication for performance).

### Phase 2: Scan for Complexity Signals

Run every scan against the target scope (`SCOPE=.` in codebase mode):

```bash
# Generated code excluded (authoritative marker: a "// Code generated .* DO NOT EDIT." line before
# the first non-comment text; globs approximate). Non-test scans deliberately include test files —
# complexity in tests is in scope here; *duplication* in tests is not (test-hunter-go owns it).
EXCLUDE='--glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Deep nesting (4+ indentation levels, tab-indented)
rg '^\t{4,}\S' --type go $EXCLUDE -- $SCOPE

# Boolean parameters
rg --pcre2 '\w+\s+bool[,)]' --type go $EXCLUDE --glob '!**/*_test.go' -- $SCOPE

# Functions with many parameters
rg --pcre2 'func\s+(\(\w+\s+\*?\w+\)\s+)?\w+\([^)]{80,}\)' --type go $EXCLUDE -- $SCOPE

# Interfaces with single implementation
rg 'type\s+\w+\s+interface' --type go $EXCLUDE -- $SCOPE

# Unused unexported functions (candidates)
rg 'func\s+[a-z]\w+\(' --type go $EXCLUDE --glob '!**/*_test.go' -- $SCOPE

# Channel complexity
rg 'chan\s+chan|<-\s*<-' --type go $EXCLUDE -- $SCOPE

# Goroutine launches
rg 'go\s+func|go\s+\w+\(' --type go $EXCLUDE -- $SCOPE
```

### Phase 3: Scan for Duplication

1. Identify repeated patterns across files using targeted searches.
2. Look for multiple implementations of the same logic with minor variations.
   (Copied setup/assertion blocks in test files belong to test-hunter-go — do not flag them here.)

### Phase 4: Evaluate Each Finding

For each complexity signal, determine:

- Is this genuinely unnecessary, or does it serve a purpose?
- What is the simplest change that eliminates it?
- Does the simplification break any exported API? If so, flag but default to follow-up.

### Phase 5: Produce Report

## Output Format

Save as `YYYY-MM-DD-simplicity-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies
an output path or return mode (e.g. the party-hunter orchestrator), it overrides this default.

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
| 1 | file:line, file:line | Near-identical validation logic | Deduplicate into shared function |

### Unnecessary Abstractions

| # | Location | Abstraction | Consumers | Action |
| - | -------- | ----------- | --------- | ------ |
| 1 | file:line | `ConfigManager` struct | 1 | Inline |

### Dead Code Paths

| # | Location | Code | Evidence | Action |
| - | -------- | ---- | -------- | ------ |
| 1 | file:line | `legacyHandler()` | 0 internal call sites | Delete |

### Over-Parameterized APIs

| # | Location | Function | Params | Action |
| - | -------- | -------- | ------ | ------ |
| 1 | file:line | `Render(a, b, c, d, e bool)` | 5 booleans | Split by use case |

### Interface Pollution

| # | Location | Interface | Implementations | Action |
| - | -------- | --------- | --------------- | ------ |
| 1 | file:line | `Processor` | 1 (no test doubles) | Remove, use concrete type |

### Mixed Concerns

| # | Location | Function | Concerns | Action |
| - | -------- | -------- | -------- | ------ |
| 1 | file:line | `ProcessOrder()` | fetch + transform + log | Extract into 3 functions |

### Complex Control Flow

| # | Location | Pattern | Depth | Action |
| - | -------- | ------- | ----- | ------ |
| 1 | file:line | Nested if/else | 4 | Flatten with guard clauses |

### Channel/Goroutine Overuse

| # | Location | Pattern | Simpler Alternative | Action |
| - | -------- | ------- | ------------------- | ------ |
| 1 | file:line | Channel for shared counter | `sync/atomic` | Replace |

## Recommendations (Priority Order)

1. **High**: {high-impact duplication, dead code with confidence}
2. **Medium**: {unnecessary abstractions, over-parameterized APIs, interface pollution}
3. **Low**: {control flow improvements, concern separation, channel simplification}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: structural complexity only.** If a finding doesn't answer "is this simpler than it could be?", it belongs
  to another hunter — do not flag it here. Named boundaries: interface *segregation and contract* design belongs to
  solid-hunter-go, while interface *existence/pollution* stays here (§5) — solid-hunter's Pragmatic Boundaries
  defers single-implementation speculative interfaces to this skill; boolean parameters are owned here (§4);
  duplication within test code belongs to test-hunter-go; commented-out code belongs to slop-hunter-go.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code.
- **Reuse over addition.** When recommending a fix, prefer existing functions or deletion over new code.
- **Preserve behavior.** Never recommend changes that alter what the code does, only how it's structured.
- **Pragmatism.** Not every abstraction is wrong. Flag, assess, and acknowledge intentional complexity. If a
  simplification breaks exported APIs or backwards compatibility, call it out and default to follow-up.
- **Respect Go idioms.** Go's explicit error handling creates visual repetition that is idiomatic, not duplication.
  Don't flag `if err != nil { return err }` as complexity — flag it only when the error handling is genuinely doing
  different things that could be unified.
