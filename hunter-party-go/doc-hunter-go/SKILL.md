---
name: doc-hunter-go
description: |
  Audit Go code for missing documentation where the "why" is not obvious — obscure
  calculations, non-trivial business rules, surprising behavior, implicit constraints,
  workarounds, and missing godoc on exported symbols. Finds where a comment would save
  the next reader significant time.

  Use when: reviewing Go code for long-term maintainability, onboarding new team members,
  auditing undocumented business logic, or preparing code for handoff.
disable-model-invocation: true
---

# Doc Hunter

Audit code for **missing "why" documentation** — places where the intent, constraints, or reasoning behind the code
are not obvious from the code itself. The goal: **every non-obvious decision has a concise inline explanation, every
exported symbol has a godoc comment, and no comment restates what the code already says.**

## When to Use

- Reviewing code for long-term maintainability
- Onboarding new team members onto an undocumented codebase
- Auditing business logic that lives only in developers' heads
- Preparing code for handoff to another team
- After a complex feature lands, before the author's context fades

## Core Principles

1. **Document the why, never the what.** A comment should answer "why is this here?" or "why this approach?" — never
   "what does this line do?". If the code needs a "what" comment, the code itself should be rewritten for clarity
   (simplicity-hunter territory, not doc-hunter).

2. **Exported symbols require godoc (secondary concern).** Go's tooling convention: every exported function, type,
   method, constant, and variable should have a comment starting with the symbol's name. This is a real convention —
   `go doc` and pkg.go.dev render these comments as the package's public documentation. However, godoc completeness
   is secondary to this skill's primary focus on missing "why" documentation. Flag missing godoc, but prioritize
   undocumented business rules, workarounds, and non-obvious algorithms over mechanical godoc coverage.

3. **Package comments set the stage.** Every package should have a package-level comment (in `doc.go` or atop any file)
   that explains the package's purpose. The comment starts with "Package X ...".

4. **Concise over comprehensive.** The best inline comment is one sentence that captures the key insight. If a
   paragraph is needed, the logic may need extraction into a named function instead.

5. **Context decays.** The reason behind a workaround, a magic number, or a non-obvious branch is obvious to the author
   today and a mystery to everyone (including the author) in six months.

6. **Not every line needs a comment.** Straightforward code — standard patterns, clear naming, obvious control flow —
   should stand on its own. Only flag missing documentation where a competent Go developer would genuinely pause and
   ask "why?".

**Comment ownership rule** (stated identically in doc-hunter, slop-hunter, and smell-hunter):
- Comment absent and the "why" non-obvious → doc-hunter (add the missing "why" comment).
- Comment present and the code trivial → slop-hunter (delete the redundant comment).
- Comment present and the code non-trivial → smell-hunter (extract/refactor; the comment is deodorant).

## What to Hunt

### 1. Missing Godoc on Exported Symbols

Exported functions, types, methods, constants, and variables without documentation comments.

**Signals:**

- Exported function without a `// FuncName ...` comment on the line above
- Exported type without a `// TypeName ...` comment
- Exported method without a `// MethodName ...` comment
- Exported constant or variable group without a comment
- Package without a `// Package name ...` comment

**Action:** Add godoc comment starting with the symbol's name. For packages, add a `doc.go` file or top-level comment.
Comments should describe *what the symbol does* for godoc, and *why it exists* for inline context.

### 2. Unexplained Business Rules

Conditionals, thresholds, or branching logic that encode domain rules not evident from the code alone.

**Signals:**

- `if age >= 26` — why 26? Legal requirement? Business policy?
- `discount := 0.1` if `total > 500` — what drives the 500 threshold?
- Complex eligibility checks with multiple conditions and no explanation of the rule
- Branching on enum/const values where the reason one variant is handled differently is non-obvious

**Action:** Flag for a comment explaining the business rule, its source (regulation, product spec, stakeholder
decision), and when it might change.

### 3. Magic Numbers and Constants

Literal values embedded in logic whose meaning or origin is unclear.

**Signals:**

- Numeric literals in calculations: `timeout = retries * 1.5 + 3`
- String literals used as keys or identifiers without explanation
- Array/slice indices that encode positional meaning: `parts[2]`
- Bit masks, status codes, or protocol values used without context
- Buffer sizes, retry counts, or timeout durations without rationale

**Action:** Flag for either a named constant with a descriptive name, or an inline comment explaining the value's
origin and meaning.

### 4. Non-Obvious Algorithms and Calculations

Mathematical formulas, coordinate transforms, bit manipulation, or multi-step data transformations where the approach
is not self-evident.

**Signals:**

- Arithmetic involving domain-specific formulas (finance, geometry, physics, statistics)
- Bitwise operations (`<<`, `>>`, `&`, `|`, `^`) outside obvious flag-checking contexts
- Multi-step slice/map transformations where the intermediate goal is unclear
- Sorting comparators with non-trivial logic
- Regular expressions beyond simple patterns

**Action:** Flag for a comment explaining what the calculation achieves, what the inputs/outputs represent, and (for
formulas) a reference to the source (spec, paper, algorithm name).

### 5. Workarounds and Compensations

Code that exists to work around a bug, library limitation, OS quirk, or upstream constraint.

**Signals:**

- Code that looks unnecessarily complex for what it achieves
- Patterns that contradict the project's normal style in a localized way
- Defensive code that handles a case the types say shouldn't happen
- Timeouts, retries, or delays without explanation of what they're compensating for
- `//go:build` constraints for platform-specific workarounds without explanation

**Action:** Flag for a comment explaining what is being worked around, ideally with a link to the issue/bug tracker,
and under what conditions the workaround can be removed.

### 6. Implicit Ordering and Timing Dependencies

Ordering constraints that are *staying* — enforced by neither the type system nor control flow — and are
undocumented. The coupling itself is smell-hunter's finding (temporal coupling, with a redesign recommendation);
doc-hunter's role is the fallback when the constraint will remain (redesign rejected or out of scope): make it
visible.

**Signals:**

- Functions that must be called in a specific sequence (init before use, A before B)
- Goroutine launch order that matters
- Channel operations that assume a specific communication sequence
- `sync.Once` usage where the initialization dependency isn't obvious
- Deferred function calls where the order of defers matters for correctness

**Action:** Flag for a comment explaining the ordering constraint and what breaks if violated. Cross-reference
smell-hunter's temporal-coupling finding when the API could instead be redesigned to make the order implicit.

### 7. Surprising Behavior and Edge Cases

Code whose behavior differs from what a reasonable reader would expect.

**Signals:**

- A function that mutates its input when the name suggests a pure operation
- Return values with non-obvious semantics (nil error with nil result means "not found")
- Side effects not indicated by the function name or signature
- Intentionally empty error handling (why is ignoring the error correct here?)
- `context.Context` values carrying non-obvious data that callers depend on

**Action:** Flag for a comment explaining the surprising behavior and why it is intentional.

### 8. Non-Obvious Exported API Contracts

Exported functions or methods whose usage constraints are not captured by the type signature.

**Signals:**

- Parameters with valid ranges not expressed in the type (`percent float64` — is 0-1 or 0-100?)
- Functions that panic on certain inputs without the godoc indicating it
- Methods with preconditions (must call Init first, must hold lock)
- Return values with ownership semantics (caller must Close, must not retain reference)
- Goroutine safety constraints not evident from the signature

**Action:** Flag for godoc documenting the contract. For exported API, godoc is required; for internal functions, a
brief inline comment suffices.

### 9. Missing Example Functions

Exported API that would benefit from executable examples for documentation and testing.

**Signals:**

- Complex public API with no `Example*` functions in test files
- Functions whose usage is non-obvious from the signature alone
- Package with rich API but no examples in `*_test.go` files
- Functions frequently misused (based on issues or code review history)

**Action:** Flag for `Example*` test functions that serve as both documentation and regression tests.

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
   (file:line) there. Related files may still be *read* as **context**: judging whether a "why" is recoverable
   often requires reading the surrounding package, even outside the scope.
2. Understand the project's domain — what business rules, algorithms, or protocols does it implement?
3. Note existing documentation patterns (godoc style, inline comment conventions, README structure).

### Phase 2: Scan for Documentation Gaps

**Godoc coverage — delegate before scanning.** grep cannot enumerate exported Go symbols reliably (exported
*methods* and grouped `const (...)`/`var (...)` declarations — the dominant forms — don't match line-anchored
patterns). Prefer a configured documentation linter: golangci-lint's `godoclint`, or `revive` with its `exported`
rule (the golint successor for missing comments on exported symbols). Use its output when the project has one
configured, and otherwise recommend enabling it *in the report* — never install or reconfigure tools for the audit.
Absent a linter, enumerate procedurally when a Go toolchain is available: list packages with `go list ./...` and
fail if discovery fails; inspect each with `go doc -all -cmd <pkg>` (`-cmd` because `package main`'s exported
symbols are otherwise hidden; if scripting through xargs, guard empty input — GNU xargs runs the command once on
empty input without `-r`). Treat `go doc` output as strong evidence for missing documentation, not ground truth.
If no toolchain: state the blind spots and review the exported surface manually.

Run every scan against the target scope (`SCOPE=.` in codebase mode):

```bash
# Design/doc-scan exclusions: vendor, testdata, tests, and generated code (authoritative marker:
# a "// Code generated .* DO NOT EDIT." line before the first non-comment text; globs approximate).
# Generated files are exactly where godoc findings would flood the report — the fix is "regenerate", never hand-editing.
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Package comments
rg '^// Package\s+\w+' --type go $EXCLUDE -- $SCOPE

# Magic numbers — incomplete discovery aid, not a detector. Where golangci-lint's mnd is configured,
# use it (AST-aware). This regex matches numbers inside comments/strings and misses scientific notation;
# it deliberately ignores single-digit values as noise control — flagging every digit would drown the report.
rg --pcre2 '([^0-9.]|^)\d{2,}([^0-9.]|$)|0x[0-9a-f]{2,}|\d+\.\d+' --type go $EXCLUDE -- $SCOPE

# Regex literals
rg 'regexp\.(Compile|MustCompile)\(' --type go $EXCLUDE -- $SCOPE

# Bitwise operations (shifts and xor only — a bare '&' pattern matches Go's ubiquitous address-of;
# note &^ is bit-clear, not a typo, when triaging xor matches)
rg --pcre2 '<<|>>|\^' --type go $EXCLUDE -- $SCOPE

# Timeouts and delays
rg 'time\.Sleep|time\.After|time\.NewTicker|Timeout|timeout' --type go $EXCLUDE -- $SCOPE

# Workaround signals
rg -i 'hack|workaround|fixme|todo|XXX' --type go $EXCLUDE -- $SCOPE

# Example functions
rg '^func Example' --type go --glob '*_test.go' -- $SCOPE

# Build constraints
rg '//go:build|// \+build' --type go $EXCLUDE -- $SCOPE
```

These are heuristic starting points — candidate generators with stated blind spots, not detectors. The primary
method is **reading the code and identifying where a competent reader would ask "why?"** — no grep pattern can
substitute for that judgment.

### Phase 3: Evaluate Each Gap

For each candidate, determine:

- Would a competent Go developer genuinely pause here?
- Is the "why" recoverable from context (nearby code, naming, types), or is it truly missing?
- Is a comment the right fix, or should the code be restructured for clarity instead?

Classify each as:

- **Add comment**: the why is missing and a comment is the right fix
- **Add godoc**: exported symbol missing required documentation
- **Rename/extract**: the code would be self-documenting with better naming or extraction
- **Skip**: the code is clear enough to a domain-literate reader

### Phase 4: Produce Report

## Output Format

Save as `YYYY-MM-DD-doc-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies an
output path or return mode (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

```md
# Doc Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Audit completed: {N} findings

## Findings

### Missing Godoc

| # | Symbol | Location | Type | Action |
| - | ------ | -------- | ---- | ------ |
| 1 | `ProcessOrder` | file:line | Exported func | Add `// ProcessOrder ...` godoc |
| 2 | `payment` package | pkg/payment/ | Package | Add `// Package payment ...` in doc.go |

### Unexplained Business Rules

| # | Location | Code | Missing Context | Suggested Comment |
| - | -------- | ---- | --------------- | ----------------- |
| 1 | file:line | `if age >= 26` | Why 26? | `// Minimum age for policy X per regulation Y` |

### Magic Numbers

| # | Location | Value | Context | Action |
| - | -------- | ----- | ------- | ------ |
| 1 | file:line | `1.5` in retry calc | Backoff multiplier — origin unclear | Name as constant or comment source |

### Non-Obvious Algorithms

| # | Location | Code | Missing Context | Action |
| - | -------- | ---- | --------------- | ------ |
| 1 | file:line | Haversine formula | No reference to formula name | Add `// Haversine distance — see <ref>` |

### Workarounds

| # | Location | Code | Missing Context | Action |
| - | -------- | ---- | --------------- | ------ |
| 1 | file:line | 200ms sleep before retry | Why the delay? | Comment with root cause and removal condition |

### Ordering Dependencies

| # | Location | Code | Missing Context | Action |
| - | -------- | ---- | --------------- | ------ |
| 1 | file:line | `Init()` must precede `Start()` | No indication of required ordering | Add comment or enforce via state |

### Surprising Behavior

| # | Location | Code | What's Surprising | Action |
| - | -------- | ---- | ----------------- | ------ |
| 1 | file:line | `Process()` mutates input slice | Name implies pure function | Comment or rename to `ProcessInPlace()` |

### API Contracts

| # | Location | Signature | Missing Contract | Action |
| - | -------- | --------- | ---------------- | ------ |
| 1 | file:line | `SetOpacity(value float64)` | Valid range? 0-1 or 0-100? | Add godoc with range |

### Missing Examples

| # | Package | Symbol | Action |
| - | ------- | ------ | ------ |
| 1 | auth | `Authenticate()` | Add ExampleAuthenticate in auth_test.go |

## Recommendations (Priority Order)

1. **High**: {undocumented business rules, workarounds without context, missing godoc on heavily used public API}
2. **Medium**: {non-obvious algorithms, surprising behavior, API contracts, magic numbers in core logic}
3. **Low**: {ordering dependencies, example functions, minor magic numbers in non-critical paths}
```

(Missing documentation is rarely Critical on its own; use Critical only when the missing "why" conceals an active
production hazard.)

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: missing "why" documentation only.** If a finding doesn't answer "would a reader pause here and ask
  why?", it belongs to another hunter — do not flag it here. Apply the comment ownership rule above for the
  doc/slop/smell split; temporal coupling with a viable redesign belongs to smell-hunter (§6 here keeps only
  constraints that are staying).
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code.
- **Godoc conventions matter.** Go has specific documentation conventions: comments start with the symbol name, package
  comments start with "Package X", examples are executable test functions. Follow these conventions in recommendations.
- **Judgment over pattern-matching.** Grep can find magic numbers and regex literals, but only reading the code reveals
  whether the "why" is truly missing.
- **Suggest, don't prescribe.** The "Suggested Comment" column is a starting point. The author knows the actual "why" —
  the audit identifies where it's missing, not what it should say.
- **Respect domain expertise.** Code that looks obscure to a generalist may be obvious to a domain expert. When
  uncertain, flag as Low rather than High.
