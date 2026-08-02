---
name: simplicity-hunter-py
description: |
  Audit Python code for unnecessary structural complexity — duplication, reinvented
  primitives, avoidable abstractions, dead logic paths, flag-heavy APIs, deep nesting,
  mixed concerns, and coexisting abstraction generations left behind by unfinished
  migrations. Recommends the simplest shape that preserves intended behavior.

  Use when: reviewing Python code for over-engineering, reducing complexity after
  prototyping, enforcing reuse over addition, simplifying before a refactor, or auditing
  a codebase after a framework or library migration.
  Reports omit empty sections — no placeholder headings, empty tables, or negative statements like "no issues found".
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
- Deduplicating logic across production modules
- Auditing a codebase after a framework or library migration

## Core Principles

1. **Default to delete.** The best simplification is removal. If code can be deleted without changing behavior, delete
   it. If it can be replaced by an existing helper, replace it.

2. **One canonical path.** When two implementations do the same thing, pick one and remove the other. Avoid "shared
   helper + keep both paths" unless required by genuinely different consumers. When the two paths are *near-identical*,
   the remedy is deletion; when they are *different designs that are both in use*, the finding is the unfinished
   migration itself, and the remedy is a retirement plan naming the stratum that survives.

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

## Not a finding on these grounds alone

Do not recommend removing or centralizing safety or operational behavior unless every call site retains an equivalent
guarantee. Distinguish a duplicated **mechanism** (often a finding) from required duplicated **enforcement** (not a
finding).

These are conditionals, not category exemptions — each states what does not justify a finding and, where a corresponding
structural finding exists, what would:

- **Trust-boundary input validation repeated across sibling handlers** — repetition alone is not the finding; each
  boundary may need independent enforcement. *Is* a finding when the validation logic itself is duplicated and could be
  a single shared schema still invoked at every boundary.
- **Error handling** — do not recommend altering the propagation strategy or collapsing distinct error paths.
  Structural duplication *within* error handling remains reportable.
- **Logging, telemetry, metrics, retries, timeouts, circuit breakers** — presence is operational intent, not
  boilerplate; do not recommend removal. Duplicated configuration, competing policies at different layers, obsolete
  wrapper layers, and dead policy branches *are* findings.
- **Duplication documented as intentional for performance** — not a finding while the rationale holds; reportable
  only if the documented reason is demonstrably stale.
- **Abstractions serving as test seams or DI boundaries** — not indirection while a test double or injector actually
  uses them. A seam with **no** consumer *is* a finding.
- **Over-simplification guard** — do not recommend inlining that erases a name carrying domain meaning, or merging
  distinct responsibilities into one unit.

## What to Hunt

### 1. Duplication

Repeated logic across production functions and modules. (Duplication *within test code* — copied setup, repeated
assertion blocks — is test-hunter-py's finding; do not flag it here.)

**Signals:**

- Two functions with near-identical bodies differing only in a value or branch
- Multiple implementations of the same algorithm
- Copy-pasted list/dict comprehensions with minor variations

**Action — elimination first, evidence over counting:**

1. **Eliminate before extracting.** If the duplication can be derived from an existing source of truth — a constant,
   an existing map, a generated value — that is the finding. A new shared helper is the fallback, not the first move.
2. Where elimination does not apply, a consolidation finding must show the shared unit **reduces total code and total
   concepts** and represents **one stable behavior**, not two behaviors that merely look alike today.
3. **Occurrence count is supporting evidence, not a gate.** Report it; do not decide on it.

### 2. Reinvented Primitives

Hand-rolled logic that is an exact substitute for a standard-library or already-present dependency primitive.

**Signals:**

- Loops replicating `itertools`, `collections.Counter`, `collections.defaultdict`, or `pathlib`
- Manual context management that `contextlib` already covers (`contextmanager`, `ExitStack`, `closing`,
  `suppress`, `nullcontext`)
- Re-rolled memoization that is an exact substitute for `functools.lru_cache` / `functools.cache`

**Gates — all must hold before a finding is raised:**

1. **Toolchain support, cited exactly** — per primitive, not a blanket language-version gate. State the requirement
   (e.g. `functools.cache` needs Python 3.9+) and show the project meets it (`requires-python`, CI matrix, runtime).
2. **Dependency policy** — replacement is stdlib or an already-present dependency. Never propose adding one.
3. **Exact semantic parity**, including designed-in differences: `functools.lru_cache` imposes hashability and carries
   concurrency, eviction, and repeated-concurrent-call semantics.
4. **Edge-case parity** — empty input, `None`/zero default, no-match path, ordering, error path.
5. **Mutability and ownership parity** — must not change who may mutate what.
6. **Demonstrable net reduction in concepts**, not merely in lines.

A version that differs on any of the above is not a simplification.

**Ownership:** Simplicity owns replacing a project implementation with an equivalent existing primitive. Smell owns
broader non-idiomatic design patterns (see Operating Constraints).

**Action:** Replace with the cited primitive; delete the hand-rolled path.

### 3. Unnecessary Abstractions

Wrappers, managers, registries, or factories that serve a single call site or add no logic.

**Signals:**

- A class/function that delegates to one other function with no transformation
- A "manager" that wraps a single resource
- A factory that returns only one type
- An ABC/Protocol with a single implementation and no plan for more — *unless* the Protocol exists to enable
  test doubles, define a dependency injection boundary, or stabilize a real architectural seam
- A decorator that does nothing beyond calling the wrapped function

**Action:** Inline the abstraction. If it exists for testability, note that and keep if justified.

### 4. Dead Code Paths

Unreachable branches, unused internal helpers, stale feature flags, and leftover alternate implementations.

**Signals:**

- `if` branches that can never be true given the input types or call sites
- Internal helper functions with zero call sites (exported dead symbols are boundary-hunter territory)
- Feature flags that are always on/off
- Commented-out alternate implementations
- `elif`/`else` branches that handle cases already ruled out by prior conditions

**Liveness (mandatory):** beyond call sites, check runtime reachability channels relevant to this symbol —
reflection/`getattr`, DI registration, registries, entry-point configuration, `__all__`, and packaging entry points
(`pyproject.toml` / `setup.cfg` `console_scripts` / `entry_points`). Cite the channels *relevant to this symbol* and
what they showed — do not recite the full list.

**History (conditional):** consult history when the code looks deliberate, unusual, or externally reachable.
Chesterton's Fence applies where there is a fence to explain; history can be shallow, absent, or misleading, so it
is not a universal requirement.

**Action:** Delete. If uncertain, flag with evidence of zero usage across the relevant channels.

### 5. Over-Parameterized APIs

Functions with many optional parameters, boolean flags, or configuration dicts that create a combinatorial explosion.

**Signals:**

- 4+ parameters, especially booleans
- Functions with `if opts.get('X')` branches for most parameters
- `**kwargs` used as a catch-all configuration pass-through
- Configuration dicts where most fields are optional and defaulted

**Action:** Split into focused functions per use case, or reduce to the parameters actually used by callers.

### 6. Mixed Concerns

Single functions or classes that handle multiple unrelated responsibilities.

**Signals:**

- A function that fetches data AND transforms it AND renders output
- A class with methods spanning different abstraction levels
- Long functions (50+ lines) with distinct logical sections separated by blank lines or comments
- A single function doing I/O, business logic, and formatting

**Action:** Extract each concern into a named helper. The parent function becomes a coordinator.

### 7. Complex Control Flow

Deep nesting, nested ternaries, long `if/elif` chains, and convoluted loops.

**Signals:**

- 3+ levels of nesting
- Nested conditional expressions (`a if b else (c if d else e)`)
- `if/elif` chains with 4+ branches
- Loop bodies with embedded conditionals
- Complex comprehensions with multiple `if` clauses and nested loops

**Action:** Flatten with guard clauses and early returns. Replace nested conditional expressions with explicit
conditionals. Extract loop bodies into named functions when complex.

### 8. Coexisting Generations (Lava Layers)

Two or more **live**, structurally different solutions to the same concern, left behind by a migration that was
started and never finished. Each generation hardens where it stopped: new code picks whichever stratum its author
happened to know about, and every reader has to learn all of them.

**The test that makes this a finding: every stratum must be live.** If the older stratum has no call sites, it is
dead code (§4) — delete it. If the two bodies are near-identical, it is duplication (§1) — pick one and delete the
rest. This category covers only the case where the designs genuinely differ *and* all of them are in use, because
that is the only case whose remedy is a migration rather than a deletion.

**Evidence required** — names and dependency coexistence *nominate candidates only*. A finding also needs:

- Identical responsibility rather than an overlapping domain
- Evidence of intended replacement (a migration, a deprecation naming a successor, a changelog or commit trail)
- Overlapping supported use cases
- A credible survivor chosen on **capability and project intent** — not git recency or recent-call-site choice.
  Recency may nominate; capability and intent decide.

**Signals:**

- Overlapping HTTP or serialization dependencies in `pyproject.toml` / `requirements*.txt`
- `warnings.warn(..., DeprecationWarning)` or `@deprecated` on symbols with live importers
- `legacy/` / `old/` packages whose older path still has importers
- Duplicate role classes all still constructed somewhere: `UserRepository` + `UserStore` + `UserDao`
- Environment- or config-selected parallel implementations where both branches are reachable (a flag that is always
  on or always off is a stale flag — §4)

**Excluded as false positives:**

- `unittest` + `pytest` — `unittest` is standard library, and pytest officially runs `unittest` suites to support
  incremental adoption
- `pydantic` v1 + v2 — `pydantic.v1` is an officially supported migration namespace within V2

Multiple HTTP packages may legitimately differ by ownership, protocol, sync/async role, or transitive origin —
coexistence alone is a candidate, never a finding.

**Action:** Report the strata, name the survivor on capability and project intent, and recommend a retirement plan
for the rest: which call sites move, and which stratum gets deleted once empty. Never recommend a rewrite; the
surviving generation is already written.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, and untracked
   - **Path**: specific files, folders, or layers
   - **Codebase**: the entire project (the default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot — `scope.txt` (file manifest only) and optionally
   `scope-meta.txt` (metadata) — use the file list in `scope.txt` verbatim and do not re-resolve. The resolution
   below applies to standalone runs only.

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

   **Scope preflight — deterministic exclusions only.** Before scanning, drop only vendored, lockfile, and
   documentation/Markdown-only inputs, plus generated files identified by an authoritative in-file marker where
   Python defines one — never by filename guessing. If nothing eligible remains: write
   `Audit completed: 0 findings — no eligible source in scope` and stop before scanning. On a mixed scope, **do not
   redefine the snapshot**. Record eligible versus excluded files in the Scope section and audit the eligible ones.
   Silently narrowing would break the party guarantee that all hunters audit the same immutable surface.
   Mechanical-churn detection (formatting, lint autofix, mass rename) requires diff content, not a file list — it is
   optional inspection, never a gate.

   **Filenames containing whitespace are unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell
   expansion word-splits on spaces. Paths with spaces will mis-scope scans; do not attempt a partial workaround.

   **Two surfaces.** Findings are reported only against the **target scope** (`$SCOPE`) — every finding anchors
   (file:line) there. Related files may still be *read* as **context**: when judging duplication, search the whole
   project for the canonical implementation and existing helpers.
2. Understand the project's existing helpers, utilities, and conventions.
3. Note any stated design decisions (e.g., intentional duplication for performance).

### Phase 2: Scan for Complexity Signals

Run every scan against the target scope (`SCOPE=.` in codebase mode). Pass an explicit path (`-- $SCOPE` or `.`) to
**every** `rg` invocation — without a path argument, `rg`'s search surface is uncontrolled and non-deterministic
(working directory, piped stdin, or empty results depending on how stdin is attached).

```bash
EXCLUDE='--glob !**/venv/** --glob !**/.venv/** --glob !**/dist/** --glob !**/__pycache__/** --glob !**/*.egg-info/**'

# Deep nesting (4+ indentation levels, 4-space indent)
rg '^\s{16,}\S' --type py $EXCLUDE -- $SCOPE

# Boolean parameters
rg --pcre2 '\w+\s*:\s*bool\b' --type py $EXCLUDE -- $SCOPE

# Functions with many parameters
rg --pcre2 'def\s+\w+\s*\([^)]{80,}\)' --type py $EXCLUDE -- $SCOPE

# **kwargs catch-all
rg '\*\*kwargs' --type py $EXCLUDE -- $SCOPE

# Nested conditional expressions
rg --pcre2 'if\s+.*\s+else\s+.*\s+if\s+' --type py $EXCLUDE -- $SCOPE

# Long functions (files with significant line spans between def statements)
rg 'def\s+\w+' --type py $EXCLUDE -n -- $SCOPE

# Reinvented-primitive candidates (manual Counter / defaultdict / lru_cache stand-ins)
rg --pcre2 'for\s+\w+\s+in\s+.+:\s*$' --type py $EXCLUDE -- $SCOPE
rg 'functools\.lru_cache|@lru_cache|@cache\b' --type py $EXCLUDE -- $SCOPE
```

### Phase 3: Scan for Duplication

1. Identify repeated patterns across files using targeted searches.
2. Look for multiple implementations of the same logic with minor variations.
   (Copied setup/assertion blocks in test files belong to test-hunter-py — do not flag them here.)

### Phase 4: Scan for Coexisting Generations — codebase and path scope only

**Scope gate.** This phase needs a view of the whole repository:

- **Codebase scope** — run it fully.
- **Path scope** — run it. Findings anchor inside the target path; the rest of the repository is read as *context* to
  establish what the competing generations are.
- **Diff scope** — **skip it.** Coexisting strata are invisible through a changed-file window: the scan would either
  find nothing or anchor a whole-stratum claim to an arbitrary changed line. Record the skip in the report's Scope
  section — do not omit it silently, and do not substitute a narrower diff-only heuristic.

The scans below read the whole tree regardless of scope, and the dependency check reads `pyproject.toml` /
`requirements*.txt`, so Phase 2's `$EXCLUDE` profile does not apply here. Pass an explicit path to every `rg`
invocation.

1. **Read `pyproject.toml` and `requirements*.txt`** and list dependencies that solve the same concern (HTTP,
   serialization). Two HTTP clients or two serializers *nominate* a candidate; coexistence alone is never a finding
   (see §8 exclusions).

2. **Find generation-named symbols and paths:**

   ```bash
   rg -l --type py 'Legacy|Deprecated|V1|V2|_v1|_v2' --glob '!**/venv/**' --glob '!**/.venv/**' --glob '!**/dist/**' .
   find . -type d \( -name 'v[0-9]*' -o -name legacy -o -name old -o -name new \) \
     -not -path '*/venv/*' -not -path '*/.venv/*' -not -path './dist/*'
   ```

3. **Find deprecation markers:**

   ```bash
   rg -n --type py 'DeprecationWarning|@deprecated|warnings\.warn' --glob '!**/venv/**' --glob '!**/.venv/**' --glob '!**/dist/**' .
   ```

4. **Confirm liveness for every candidate stratum.** Search the whole project for its import and construction sites.
   A stratum with zero sites is a §4 finding, not a §8 one — reclassify it and move on.

5. **Establish which generation should survive** where the evidence allows: capability and project intent decide.
   `git log -1 --format=%as -- <path>` and recent call-site choice may *nominate* only — they do not settle the
   survivor.

These scans nominate candidates only. A name containing `V2` proves nothing on its own; the finding is the pair of
live strata with identical responsibility and intended replacement, not the label.

### Phase 5: Evaluate Each Finding

For each complexity signal, determine:

- Is this genuinely unnecessary, or does it serve a purpose?
- What is the simplest change that eliminates it?
- Does the simplification break any public API? If so, flag but default to follow-up.
- For a reinvented-primitives candidate: do all six gates hold with a cited toolchain requirement and semantic
  parity? If any gate fails, drop it.
- For a coexisting-generations candidate: are *all* strata live, do the designs actually differ, and is there
  evidence of intended replacement with a capability/intent-chosen survivor? If only one is live, reclassify to §4;
  if the bodies are near-identical, reclassify to §1; if coexistence alone (e.g. multiple HTTP packages without
  identical responsibility) — not a finding.

**Reporting gate.** Report only when the proposed change demonstrably reduces total concepts, duplicated behavior,
or control-flow burden by enough to outweigh the new indirection and behavioral risk it introduces.

**Platform-guarantee redundancy.** Do not treat "the platform / framework / runtime already guarantees this" as a
non-finding by default. Flag only with evidence: name the layer that owns the guarantee, show that removal preserves
every output, error, side effect and ordering, and cite the test or direct comparison proving it. This class
over-fires; the evidence bar is the point.

**Impact** — assessed contextually for every reported finding; never assigned by refactoring pattern. Nesting depth,
occurrence count, and "this is a wrapper deletion" do not by themselves set a rating. Rate on:

- **Defect exposure reduced** — does the current shape make a class of mistakes likely, and how reachable is the code?
- **Cognitive burden reduced** — how much does a reader actually have to hold, and how often is this read?
- **Affected surface** — how much of the codebase, and how many future changes, the shape touches.

Bands: **High** — substantially reduces defect exposure or cognitive burden on code that is read or changed often.
**Medium** — a clear improvement on a moderately reached surface. **Low** — clears the reporting gate but affects a
small, rarely touched surface.

Impact and severity are independent and both are kept: severity is the orchestrator-requested risk scale; impact is
how much the change is worth. Every reported finding carries an Impact rating and stays in its table. Nothing is held
back; `Audit completed: N findings` counts everything reported. Recommendations order by Impact within each severity
group.

### Phase 6: Produce Report

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
- Eligible: {count or list}
- Exclusions: {list — deterministic only; eligible vs excluded recorded on mixed scope}
- {Deleted in diff: {list} — only for diff scope with deletions}
- {Coexisting generations: skipped — requires codebase or path scope — only for diff scope}
- Audit completed: {N} findings

## Findings

### Duplication

| # | Locations | Description | Impact | Action |
| - | --------- | ----------- | ------ | ------ |
| 1 | file:line, file:line | Near-identical validation logic | High | Deduplicate into shared helper |

### Reinvented Primitives

| # | Location | Hand-rolled | Primitive | Toolchain | Impact | Action |
| - | -------- | ----------- | --------- | --------- | ------ | ------ |
| 1 | file:line | manual tally loop | `collections.Counter` | stdlib | Medium | Replace; delete loop |

### Unnecessary Abstractions

| # | Location | Abstraction | Consumers | Impact | Action |
| - | -------- | ----------- | --------- | ------ | ------ |
| 1 | file:line | `ConfigManager` class | 1 | Medium | Inline |

### Dead Code Paths

| # | Location | Code | Evidence | Impact | Action |
| - | -------- | ---- | -------- | ------ | ------ |
| 1 | file:line | `legacy_handler()` | 0 internal call sites; not in `__all__` / entry points | High | Delete |

### Over-Parameterized APIs

| # | Location | Function | Params | Impact | Action |
| - | -------- | -------- | ------ | ------ | ------ |
| 1 | file:line | `render(a, b, c, d, e)` | 5 (3 booleans) | Medium | Split by use case |

### Mixed Concerns

| # | Location | Function | Concerns | Impact | Action |
| - | -------- | -------- | -------- | ------ | ------ |
| 1 | file:line | `process_order()` | fetch + transform + log | Medium | Extract into 3 helpers |

### Complex Control Flow

| # | Location | Pattern | Depth | Impact | Action |
| - | -------- | ------- | ----- | ------ | ------ |
| 1 | file:line | Nested conditional expression | 3 | Low | Replace with if/elif |

### Coexisting Generations

| # | Concern | Strata | Live evidence | Survivor (capability/intent) | Impact | Action |
| - | ------- | ------ | ------------- | ---------------------------- | ------ | ------ |
| 1 | HTTP client | `app/http.py:12` (httpx), `app/legacy_fetch.py:8` (requests) | migration doc names httpx; 14 vs 3 import sites | httpx — async + project intent | Medium | Move the 3 sites; drop requests |

## Recommendations (Priority Order)

Order by Impact within each severity group:

1. **Critical**: {only when a duplicated or dead path is actively producing wrong behavior in production}
2. **High**: {high-impact duplication, dead code with confidence, generations whose behavior diverges}
3. **Medium**: {unnecessary abstractions, reinvented primitives, over-parameterized APIs, generations with equivalent behavior}
4. **Low**: {control flow improvements, concern separation}
```

(Structural complexity is rarely Critical on its own; use Critical only when a duplicated or dead path is actively
producing wrong behavior in production. Coexisting generations are **Medium** by default; raise to **High** when the
strata *behave* differently — two HTTP clients with different retry and timeout policies, two serializers enforcing
different rules — because that is a live behavioral divergence, not only maintenance debt.)

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when
  it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like
  "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings"
  line, and the coexisting-generations skip line when the scope is a diff, are always present in the Scope section
  even at zero findings.
- **Scope: structural complexity only.** Do not flag type invariants (→ invariant-hunter-py), type design
  (→ type-hunter-py), module boundary issues (→ boundary-hunter-py), class/interface design (→ solid-hunter-py),
  missing documentation (→ doc-hunter-py), security (→ security-hunter-py), test quality or test-code duplication
  (→ test-hunter-py), or cosmetic style (→ slop-hunter-py). If a finding doesn't answer "is this simpler than it
  could be?", it doesn't belong here.
- **Reinvented primitives ownership.** Simplicity owns replacing a project implementation with an equivalent
  existing primitive (§2). Smell-hunter-py owns broader non-idiomatic design patterns. Do not expand §2 into a
  general idioms review.
- **Coexisting generations: adjacent categories.** Shotgun surgery — one logical change spreading across many
  modules — is smell-hunter's; §8 is the inverse, many generations stacked on one concern. An external dependency
  with no wrapper at all is boundary-hunter's Missing Abstraction Over Externals; two wrappers of different vintage
  are §8. A feature flag that is always on or off is a stale flag (§4); a flag whose branches are both live with no
  removal plan is §8.
- **Retire, don't rewrite.** A coexisting-generations finding moves call sites onto a stratum that already exists and
  deletes the others. Never recommend a third generation.
- **Evidence required.** Every finding must cite `file/path.py:line` with the exact code. A coexisting-generations
  finding cites file:line for *every* stratum, plus a live import or call site for each — a stratum whose liveness
  is not shown is not part of the finding. A reinvented-primitives finding cites the primitive, the toolchain
  requirement, and parity evidence for the gates that could fail.
- **Reuse over addition.** When recommending a fix, prefer existing helpers or deletion over new code.
- **Preserve behavior.** Never recommend changes that alter what the code does, only how it's structured.
- **Pragmatism.** Not every abstraction is wrong. Flag, assess, and acknowledge intentional complexity. If a
  simplification breaks public APIs or backwards compatibility, call it out and default to follow-up.
