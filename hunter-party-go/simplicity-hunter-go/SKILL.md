---
name: simplicity-hunter-go
description: |
  Audit Go code for unnecessary structural complexity — duplication, reinvented
  primitives, avoidable abstractions, dead logic paths, over-parameterized APIs,
  deep nesting, interface pollution, channel misuse, mixed concerns, and
  coexisting abstraction generations left behind by unfinished migrations.
  Recommends the simplest shape that preserves intended behavior.

  Use when: reviewing Go code for over-engineering, reducing complexity after
  prototyping, enforcing reuse over addition, simplifying before a refactor, or
  auditing a codebase after a library or framework migration.
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
- Auditing a codebase after a library or framework migration for unfinished strata

## Core Principles

1. **Default to delete.** The best simplification is removal. If code can be deleted without changing behavior, delete
   it. If it can be replaced by an existing function, replace it.

2. **One canonical path.** When two implementations do the same thing, pick one and remove the other. Avoid "shared
   helper + keep both paths" unless required by genuinely different consumers. When the two paths are *near-identical*,
   the remedy is deletion; when they are *different designs that are both in use*, the finding is the unfinished
   migration itself, and the remedy is a retirement plan naming the stratum that survives.

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

## Not a finding on these grounds alone

Do not recommend removing or centralizing safety or operational behavior unless every call site retains an equivalent
guarantee. Distinguish a duplicated **mechanism** (often a finding) from required duplicated **enforcement** (not a
finding).

Entries below are conditionals, not category exemptions — each states what does **not** justify a finding and, where a
corresponding structural finding exists, what would:

- **Trust-boundary input validation repeated across sibling handlers** — repetition alone is not the finding; each
  boundary may need independent enforcement. *Is* a finding when the validation logic itself is duplicated and could be
  a single shared schema still invoked at every boundary.
- **Error handling** — do not recommend altering the propagation strategy or collapsing distinct error paths. Structural
  duplication *within* error handling remains reportable. Complements the "Respect Go idioms" constraint: idiomatic
  `if err != nil` repetition is not complexity; duplicated non-trivial error construction or wrapping logic can be.
- **Logging, telemetry, metrics, retries, timeouts, circuit breakers** — presence is operational intent, not
  boilerplate; do not recommend removal. Duplicated configuration, competing policies at different layers, obsolete
  wrapper layers, and dead policy branches *are* findings.
- **Duplication documented as intentional for performance** — not a finding while the rationale holds; reportable only
  if the documented reason is demonstrably stale.
- **Abstractions serving as test seams or DI boundaries** — not indirection while a test double or injector actually uses
  them. A seam with **no** consumer *is* a finding.
- **Over-simplification guard** — do not recommend inlining that erases a name carrying domain meaning, or merging
  distinct responsibilities into one unit.

## What to Hunt

### 1. Duplication

Repeated logic across functions or packages. (Duplication *within test code* — copied setup, repeated assertion
blocks — is test-hunter-go's finding; do not flag it here.)

**Eliminate before extracting.** If the duplication can be derived from an existing source of truth — a constant, an
existing map, a generated value — that is the finding. A new shared helper is the fallback, not the first move.

Where elimination does not apply, a consolidation finding must show the shared unit **reduces total code and total
concepts** and represents **one stable behavior**, not two behaviors that merely look alike today.

**Occurrence count is supporting evidence, not a gate.** Report it; do not decide on it. There is no numeric threshold
for raising a finding.

**Signals:**

- Two functions with near-identical bodies differing only in a value or branch
- Multiple implementations of the same algorithm
- Identical non-trivial error-handling or validation *logic* repeated across handlers (see Not-a-finding conditionals)

**Action:** Prefer elimination from an existing source of truth; otherwise choose one canonical implementation, delete
the rest, and extract shared logic only when consolidation reduces total concepts and serves genuine consumers.

### 2. Reinvented Primitives

Project code that reimplements a stdlib (or already-present dependency) primitive with equivalent semantics, when the
toolchain already supports that primitive.

**Gates — all must hold before a finding is raised:**

1. **Toolchain support, cited exactly** — per primitive, not a blanket language-version gate. State the requirement and
   show the project meets it (from `go.mod` `go` directive or documented toolchain):
   - `errors.Join` → Go 1.20+
   - `slices` / `maps` stdlib packages → Go 1.21+
2. **Dependency policy** — replacement is stdlib or an already-present dependency. Never propose adding one.
3. **Exact semantic parity**, including designed-in differences of the primitive.
4. **Edge-case parity** — empty input, nil/zero default, no-match path, ordering, error path.
5. **Mutability and ownership parity** — must not change who may mutate what.
6. **Demonstrable net reduction in concepts**, not merely in lines.

A version that differs on any of the above is not a simplification.

**Signals:**

- Loops that replicate `slices` / `maps` helpers (e.g. contains, clone, delete-func, keyed collect) where those
  packages are available
- Re-implemented `errors.Is` / `errors.As` walks, or hand-rolled multi-error aggregation where `errors.Join` applies

`strings.Builder` is deliberately **excluded**: it is a performance transformation, usually increases source-level
complexity, and carries a do-not-copy-a-non-zero-Builder constraint.

**Action:** Replace the project implementation with the equivalent primitive. Do not wrap further.

### 3. Unnecessary Abstractions

Wrappers, managers, registries, or factories that serve a single call site or add no logic.

**Signals:**

- An interface with a single implementation and no test doubles
- A function that delegates to one other function with no transformation
- A "manager" struct that wraps a single resource
- A factory function that returns only one type
- A package with one exported function that just calls another package

**Action:** Inline the abstraction. If it exists for testability, note that and keep if justified.

### 4. Dead Code Paths

Unreachable branches, unused internal functions, stale feature flags, and leftover alternate implementations.

**Liveness is mandatory.** Before reporting dead code, check runtime reachability beyond call sites — reflection, DI
registration, registries, entrypoint configuration, and Go build tags (`//go:build`, `// +build`). Exported dead
symbols remain boundary-hunter territory.

**History is conditional.** Consult git history when the code looks deliberate, unusual, or externally reachable.
Chesterton's Fence applies where there is a fence to explain; history can be shallow, absent, or misleading, so it is
not a universal requirement.

**Evidence:** cite the channels *relevant to this symbol* and what they showed. Do not recite the full checklist — a
recited list is boilerplate, not evidence.

**Signals:**

- `if` branches that can never be true given the input types or call sites
- Unexported functions with zero call sites after liveness checks (exported dead symbols are boundary-hunter territory)
- Feature flags that are always on/off
- `default` cases in type switches that can never trigger (all types handled)

(Commented-out code blocks are slop-hunter's finding — this skill keeps unreachable *logic*, not dead text.)

**Action:** Delete. If uncertain, flag with evidence of zero usage via the channels checked for that symbol.

### 5. Over-Parameterized APIs

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

### 6. Interface Pollution

Interfaces created for theoretical extensibility rather than actual need.

**Signals:**

- Interface with one implementation and no test double
- Interface defined in the same package as its only implementation
- Interface that mirrors a concrete struct's full method set
- "Just in case" interfaces that have existed for months without a second implementation

**Action:** Remove the interface and use the concrete type. Introduce the interface when a second implementation or
test double is actually needed.

### 7. Mixed Concerns

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

### 8. Complex Control Flow

Deep nesting, nested conditionals, and convoluted loops.

**Signals:**

- 3+ levels of nesting
- `if/else if` chains with 4+ branches (consider a switch or map lookup)
- Loop bodies with embedded conditionals
- Error handling that creates pyramid-shaped code (but note: `if err != nil { return }` guard clauses are idiomatic
  Go, not a nesting problem — flag only when error handling creates genuinely deep indentation)

**Action:** Flatten with guard clauses and early returns. Replace nested conditionals with switch statements or map
lookups. Extract loop bodies into named functions when complex.

### 9. Channel and Goroutine Overuse

Concurrency patterns more complex than the problem requires.

**Signals:**

- Channel used where a mutex-protected variable would suffice
- Goroutine launched for a single synchronous operation
- Worker pool pattern for a bounded, predictable workload
- Channel of channels (metachannel)
- `select` with a single case and no timeout

**Action:** Use the simplest concurrency primitive that works. Mutex for state, channel for communication, goroutine
for actual parallelism.

### 10. Coexisting Generations (Lava Layers)

Two or more **live**, structurally different solutions to the same concern, left behind by a migration that was
started and never finished. Each generation hardens where it stopped: new code picks whichever stratum its author
happened to know about, and every reader has to learn all of them.

**The test that makes this a finding: every stratum must be live.** If the older stratum has no call sites, it is
dead code (§4) — delete it. If the two bodies are near-identical, it is duplication (§1) — pick one and delete the
rest. This category covers only the case where the designs genuinely differ *and* all of them are in use, because
that is the only case whose remedy is a migration rather than a deletion.

**Evidence required.** Names and dependency coexistence *nominate candidates only*. A finding needs: identical
responsibility rather than an overlapping domain; evidence of intended replacement (a migration, a deprecation naming
a successor, a changelog or commit trail); overlapping supported use cases; and a credible survivor chosen on
**capability and project intent**. Git recency and which stratum newer call sites choose may nominate; they do not
decide suitability, feature completeness, or operational equivalence.

**Signals:**

- Overlapping `go.mod` dependencies solving one concern (two routers, two loggers, two HTTP client stacks)
- `// Deprecated:` markers on symbols that still have live importers
- `legacy/` / `old/` package directories whose older path still has importers
- Two or more role types for the same concept, all still constructed somewhere
- Environment- or config-selected parallel implementations where both branches are reachable (a flag that is always
  on or always off is a stale flag — §4)

**/vN carve-out.** Exempt only when the governing `go.mod` — root or nested — declares a `module` path whose final
element is the matching `/vN` (Go's major-version module rule from v2 onward). Neither a directory *named* `v2` nor
the mere presence of a nested `go.mod` proves a major-version module.

**Action:** Report the strata, name the survivor on capability and project intent, and recommend a retirement plan for
the rest: which call sites move, and which stratum gets deleted once empty. Never recommend a rewrite; the surviving
generation is already written.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, and untracked
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project (the default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot, treat `scope.txt` as a **file manifest only**
   (one path per line). Read run metadata (base SHA, surface kind, counts) from `scope-meta.txt` when present. Use the
   manifest verbatim and do not re-resolve. The resolution below applies to standalone runs only.

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

   **Scope preflight (deterministic exclusions only).** From the resolved surface, exclude only:
   - vendored trees (`vendor/`)
   - lockfiles
   - documentation / Markdown-only inputs
   - generated files identified by an authoritative in-file marker: a `// Code generated … DO NOT EDIT.` line before
     the first non-comment text — **never** by filename guessing. Scan globs such as `*.pb.go` / `*_gen.go` /
     `*_generated.go` are approximations for scanning convenience; eligibility for reporting uses the marker.

   Record eligible versus excluded files in the Scope section. If **nothing** eligible remains: write
   `Audit completed: 0 findings — no eligible source in scope` and stop before scanning.

   On a **mixed scope**, do **not** redefine the snapshot. Audit the eligible files; silently narrowing would break
   the party guarantee that all hunters audit the same immutable surface. Mechanical-churn detection (formatting,
   lint autofix, mass rename) requires diff content, not a file list — **optional inspection, never a gate**.

   **Whitespace in paths is unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell expansion word-splits
   on spaces; paths containing whitespace are a declared limitation.

   **Two surfaces.** Findings are reported only against the **target scope** (`$SCOPE`) — every finding anchors
   (file:line) there. Related files may still be *read* as **context**: confirming that a helper is single-use or
   an interface single-implementation requires checking call sites outside the scope.
2. Understand the project's existing helpers, utilities, conventions, and `go` toolchain version from `go.mod`.
3. Note any stated design decisions (e.g., intentional duplication for performance).

### Phase 2: Scan for Complexity Signals

Run every scan against the target scope (`SCOPE=.` in codebase mode):

```bash
# Generated-code globs approximate the authoritative "// Code generated .* DO NOT EDIT." marker
# (eligibility uses the marker — see Scope preflight). Non-test scans deliberately include test files —
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

# Reinvented-primitive candidates (confirm toolchain + semantic parity before reporting)
rg 'errors\.Is|errors\.As|errors\.Join' --type go $EXCLUDE -- $SCOPE
rg 'slices\.|maps\.' --type go $EXCLUDE -- $SCOPE
```

### Phase 3: Scan for Duplication

1. Identify repeated patterns across files using targeted searches.
2. Look for multiple implementations of the same logic with minor variations.
   (Copied setup/assertion blocks in test files belong to test-hunter-go — do not flag them here.)
3. Prefer elimination from an existing source of truth over proposing a new shared helper.

### Phase 4: Scan for Coexisting Generations — codebase and path scope only

**Scope gate.** This phase needs a view of the whole repository:

- **Codebase scope** — run it fully.
- **Path scope** — run it. Findings anchor inside the target path; the rest of the repository is read as *context* to
  establish what the competing generations are.
- **Diff scope** — **skip it.** Coexisting strata are invisible through a changed-file window: the scan would either
  find nothing or anchor a whole-stratum claim to an arbitrary changed line. Record the skip in the report's Scope
  section — do not omit it silently, and do not substitute a narrower diff-only heuristic.

The scans below read the whole tree regardless of path/codebase target window; Phase 2's `$EXCLUDE` profile does not
apply here. Pass an explicit path to every `rg` invocation so the search surface is controlled and deterministic.

1. **Read `go.mod` files** (root and nested) and list dependencies that solve the same concern (routers, loggers, HTTP
   clients). Apply the `/vN` carve-out only when a governing `module` path's final element matches `/vN`.

2. **Find generation-named paths and symbols:**

   ```bash
   rg -l --type go 'Legacy|Deprecated|Old' --glob '!**/vendor/**' .
   find . -type d \( -name legacy -o -name old \) \
     -not -path '*/vendor/*' -not -path '*/.git/*'
   ```

3. **Find deprecation markers:**

   ```bash
   rg -n --type go '// Deprecated:' --glob '!**/vendor/**' .
   ```

4. **Confirm liveness for every candidate stratum.** Search the whole project for its import and construction sites.
   A stratum with zero sites is a §4 finding, not a §10 one — reclassify it and move on.

5. **Nominate a survivor** where evidence allows: capability, feature completeness, and project intent. Use
   `git log -1 --format=%as -- <path>` and recent call-site choice only as nomination signals — they do not decide.

These scans nominate candidates only. A directory named `v2` or a symbol containing `Legacy` proves nothing on its
own; the finding is the pair of live strata with intended replacement, not the label.

### Phase 5: Evaluate Each Finding

**Reporting gate.** Report only when the proposed change demonstrably reduces total concepts, duplicated behavior, or
control-flow burden by enough to outweigh the new indirection and behavioral risk it introduces.

For each complexity signal, determine:

- Is this genuinely unnecessary, or does it serve a purpose? Apply the Not-a-finding conditionals first.
- Does the proposed change clear the reporting gate above?
- What is the simplest change that eliminates it?
- Does the simplification break any exported API? If so, flag but default to follow-up.
- For a coexisting-generations candidate: are *all* strata live, and do the designs actually differ? If only one is
  live, reclassify to §4; if the bodies are near-identical, reclassify to §1. Choose the survivor on capability and
  intent, not recency alone.
- For reinvented-primitives candidates: do all six gates hold with a cited toolchain requirement?

**Platform-guarantee rule (flag only with evidence).** When recommending removal of logic because "the platform /
framework / middleware already guarantees it," name the layer that owns the guarantee, show that removal preserves
every output, error, side effect and ordering, and cite the test or direct comparison proving it. Without that
evidence, do not raise the finding — this class over-fires.

**Impact (contextual, independent of severity).** Rate every finding on defect exposure reduced, cognitive burden
reduced, and affected surface — never by nesting depth, occurrence count, or refactoring pattern alone:

- **High** — substantially reduces defect exposure or cognitive burden on code that is read or changed often.
- **Medium** — a clear improvement on a moderately reached surface.
- **Low** — clears the reporting gate above but affects a small, rarely touched surface.

Severity is the orchestrator-requested risk scale; Impact is how much the change is worth. Both are kept. Nothing is
held back; `Audit completed: N findings` counts every reported finding.

### Phase 6: Produce Report

## Output Format

Save as `YYYY-MM-DD-simplicity-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies
an output path or return mode (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

Within each severity group in Recommendations, order findings by Impact (High → Medium → Low).

```md
# Simplicity Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Eligible: {count or list}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker}
- {Deleted in diff: {list} — only for diff scope with deletions}
- {Coexisting generations: skipped — requires codebase or path scope — only for diff scope}
- Audit completed: {N} findings

## Findings

### Duplication

| # | Locations | Description | Impact | Action |
| - | --------- | ----------- | ------ | ------ |
| 1 | file:line, file:line | Near-identical validation logic | Medium | Eliminate via existing schema; invoke at each boundary |

### Reinvented Primitives

| # | Location | Hand-rolled | Primitive | Toolchain | Impact | Action |
| - | -------- | ----------- | --------- | --------- | ------ | ------ |
| 1 | file:line | loop contains | `slices.Contains` | go 1.21 | Low | Replace |

### Unnecessary Abstractions

| # | Location | Abstraction | Consumers | Impact | Action |
| - | -------- | ----------- | --------- | ------ | ------ |
| 1 | file:line | `ConfigManager` struct | 1 | Medium | Inline |

### Dead Code Paths

| # | Location | Code | Evidence | Impact | Action |
| - | -------- | ---- | -------- | ------ | ------ |
| 1 | file:line | `legacyHandler()` | 0 call sites; not in any registry; no build-tag variant | High | Delete |

### Over-Parameterized APIs

| # | Location | Function | Params | Impact | Action |
| - | -------- | -------- | ------ | ------ | ------ |
| 1 | file:line | `Render(a, b, c, d, e bool)` | 5 booleans | Medium | Split by use case |

### Interface Pollution

| # | Location | Interface | Implementations | Impact | Action |
| - | -------- | --------- | --------------- | ------ | ------ |
| 1 | file:line | `Processor` | 1 (no test doubles) | Medium | Remove, use concrete type |

### Mixed Concerns

| # | Location | Function | Concerns | Impact | Action |
| - | -------- | -------- | -------- | ------ | ------ |
| 1 | file:line | `ProcessOrder()` | fetch + transform + log | Medium | Extract into 3 functions |

### Complex Control Flow

| # | Location | Pattern | Depth | Impact | Action |
| - | -------- | ------- | ----- | ------ | ------ |
| 1 | file:line | Nested if/else | 4 | Low | Flatten with guard clauses |

### Channel/Goroutine Overuse

| # | Location | Pattern | Simpler Alternative | Impact | Action |
| - | -------- | ------- | ------------------- | ------ | ------ |
| 1 | file:line | Channel for shared counter | `sync/atomic` | Medium | Replace |

### Coexisting Generations

| # | Concern | Strata | Live evidence | Survivor (capability/intent) | Impact | Action |
| - | ------- | ------ | ------------- | ---------------------------- | ------ | ------ |
| 1 | HTTP router | `pkg/httpx` (chi), `internal/legacy/mux` (stdlib) | 12 vs 2 importers; deprecation names chi | chi — fuller middleware story, project intent | High | Move 2 sites; delete legacy mux |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).

1. **Critical** / **High**: {…}
2. **Medium**: {…}
3. **Low**: {…}
```

(Structural complexity is rarely Critical on its own; use Critical only when a duplicated or dead path is actively
producing wrong behavior in production. Coexisting generations are **Medium** by default; raise to **High** when the
strata *behave* differently — two routers with different middleware contracts, two loggers with different fields —
because that is a live behavioral divergence, not only maintenance debt.)

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line, and the coexisting-generations skip line when the scope is a diff, are always present in the Scope section even at zero findings.
- **Scope: structural complexity only.** If a finding doesn't answer "is this simpler than it could be?", it belongs
  to another hunter — do not flag it here. Named boundaries: interface *segregation and contract* design belongs to
  solid-hunter-go, while interface *existence/pollution* stays here (§6) — solid-hunter's Pragmatic Boundaries
  defers single-implementation speculative interfaces to this skill; boolean parameters are owned here (§5);
  duplication within test code belongs to test-hunter-go; commented-out code belongs to slop-hunter-go.
- **Reinvented primitives ownership.** This skill owns replacing a project implementation with an equivalent existing
  primitive (stdlib or already-present dependency) when all gates hold. Broader non-idiomatic design patterns belong
  to smell-hunter-go.
- **Coexisting generations: adjacent categories.** Shotgun surgery — one logical change spreading across many
  packages — is smell-hunter's; §10 is the inverse, many generations stacked on one concern. An external dependency
  with no wrapper at all is boundary-hunter's Missing Abstraction Over Externals; two wrappers of different vintage
  are §10. A feature flag that is always on or off is a stale flag (§4); a flag whose branches are both live with no
  removal plan is §10.
- **Retire, don't rewrite.** A coexisting-generations finding moves call sites onto a stratum that already exists and
  deletes the others. Never recommend a third generation.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code. A coexisting-generations
  finding cites file:line for *every* stratum, plus a live import or call site for each — a stratum whose liveness
  is not shown is not part of the finding. Dead-code evidence cites only the channels relevant to that symbol.
- **Reuse over addition.** When recommending a fix, prefer existing functions or deletion over new code.
- **Preserve behavior.** Never recommend changes that alter what the code does, only how it's structured.
- **Pragmatism.** Not every abstraction is wrong. Flag, assess, and acknowledge intentional complexity. If a
  simplification breaks exported APIs or backwards compatibility, call it out and default to follow-up.
- **Respect Go idioms.** Go's explicit error handling creates visual repetition that is idiomatic, not duplication.
  Don't flag `if err != nil { return err }` as complexity — flag it only when the error handling is genuinely doing
  different things that could be unified.
