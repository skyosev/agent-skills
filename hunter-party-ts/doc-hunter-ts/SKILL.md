---
name: doc-hunter-ts
description: |
  Audit TypeScript code for missing inline documentation where the "why" is not obvious —
  obscure calculations, non-trivial business rules, surprising behavior, implicit constraints,
  and workarounds. Finds where a comment would save the next reader significant time.

  Use when: reviewing TypeScript code for long-term maintainability, onboarding new team members,
  auditing undocumented business logic, or preparing code for handoff.
disable-model-invocation: true
---

# Doc Hunter

Audit code for **missing "why" documentation** — places where the intent, constraints, or reasoning behind the code
are not obvious from the code itself. The goal: **every non-obvious decision has a concise inline explanation, and no
comment restates what the code already says.**

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

2. **Absence is the signal.** Doc-hunter looks for places where documentation is *missing*, not where it exists and is
   wrong. A complex calculation with no comment is a finding. A redundant comment is slop-hunter territory.

3. **Concise over comprehensive.** The best inline comment is one sentence that captures the key insight. If a
   paragraph is needed, the logic may need extraction into a named function instead.

4. **Context decays.** The reason behind a workaround, a magic number, or a non-obvious branch is obvious to the author
   today and a mystery to everyone (including the author) in six months. The audit identifies where that decay will
   hurt most.

5. **Not every line needs a comment.** Straightforward code — standard patterns, clear naming, obvious control flow —
   should stand on its own. Only flag missing documentation where a competent reader of the language and domain would
   genuinely pause and ask "why?".

**Comment ownership rule** (stated identically in doc-hunter, slop-hunter, and smell-hunter):
- Comment absent and the "why" non-obvious → doc-hunter (add the missing "why" comment).
- Comment present and the code trivial → slop-hunter (delete the redundant comment).
- Comment present and the code non-trivial → smell-hunter (extract/refactor; the comment is deodorant).

## What to Hunt

### 1. Unexplained Business Rules

Conditionals, thresholds, or branching logic that encode domain rules not evident from the code alone.

**Signals:**

- `if (age >= 26)` — why 26? Legal requirement? Business policy?
- `discount = total > 500 ? 0.1 : 0` — what drives the 500 threshold?
- Complex eligibility checks with multiple conditions and no explanation of the rule
- Branching on enum values where the reason one variant is handled differently is non-obvious

**Action:** Flag for a comment explaining the business rule, its source (regulation, product spec, stakeholder
decision), and when it might change.

### 2. Magic Numbers and Constants

Literal values embedded in logic whose meaning or origin is unclear.

**Signals:**

- Numeric literals in calculations: `timeout = retries * 1.5 + 3`
- String literals used as keys or identifiers without explanation
- Array indices that encode positional meaning: `parts[2]`
- Bit masks, status codes, or protocol values used without context

**Action:** Flag for either a named constant with a descriptive name, or an inline comment explaining the value's
origin and meaning.

### 3. Non-Obvious Algorithms and Calculations

Mathematical formulas, coordinate transforms, bit manipulation, or multi-step data transformations where the approach
is not self-evident.

**Signals:**

- Arithmetic involving domain-specific formulas (finance, geometry, physics, statistics)
- Bitwise operations (`<<`, `>>`, `&`, `|`, `^`) outside obvious flag-checking contexts
- Multi-step array/object transformations where the intermediate goal is unclear
- Sorting comparators with non-trivial logic
- Regular expressions beyond simple patterns

**Action:** Flag for a comment explaining what the calculation achieves, what the inputs/outputs represent, and (for
formulas) a reference to the source (spec, paper, algorithm name).

### 4. Workarounds and Compensations

Code that exists to work around a bug, library limitation, browser quirk, or upstream constraint.

**Signals:**

- Code that looks unnecessarily complex for what it achieves
- Patterns that contradict the project's normal style in a localized way
- Defensive code that handles a case the types say shouldn't happen
- Timeouts, retries, or delays without explanation of what they're compensating for
- Conditional logic that checks for specific platform/version/environment

**Action:** Flag for a comment explaining what is being worked around, ideally with a link to the issue/bug tracker,
and under what conditions the workaround can be removed.

### 5. Implicit Ordering and Timing Dependencies

Ordering constraints that are *staying* — enforced by neither the type system nor control flow — and are
undocumented. The coupling itself is smell-hunter's finding (temporal coupling, with a redesign recommendation);
doc-hunter's role is the fallback when the constraint will remain: make it visible.

**Signals:**

- Functions that must be called in a specific sequence (init before use, A before B)
- State mutations that depend on prior mutations having occurred
- Event handler registration that assumes a particular lifecycle order
- Async operations that depend on a prior operation having completed (without explicit await)
- Array operations that assume sorted input without asserting it

**Action:** Flag for a comment explaining the ordering constraint and what breaks if violated. Cross-reference
smell-hunter's temporal-coupling finding when the API could instead be redesigned to make the order implicit.

### 6. Surprising Behavior and Edge Cases

Code whose behavior differs from what a reasonable reader would expect.

**Signals:**

- A function that mutates its input when the name suggests a pure operation
- Return values with non-obvious semantics (null means "not found" vs "not applicable" vs "error")
- Side effects not indicated by the function name or signature
- Intentionally empty catch/finally blocks (why is ignoring the error correct here?)
- Boundary conditions handled differently (first/last element, empty input, zero, negative values)

**Action:** Flag for a comment explaining the surprising behavior and why it is intentional.

### 7. Non-Obvious Public API Contracts

Exported functions or methods whose usage constraints are not captured by the type signature.

**Signals:**

- Parameters with valid ranges not expressed in the type (`percent: number` — is 0-1 or 0-100?)
- Functions that throw on certain inputs without the signature indicating it
- Methods with preconditions (must call X first, object must be in state Y)
- Return values with ownership semantics (caller must dispose, must not mutate)
- Thread/async safety constraints not evident from the signature

**Action:** Flag for JSDoc or inline comment documenting the contract. For public API, JSDoc is preferred; for
internal functions, a brief inline comment suffices.

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
   (file:line) there. Related files may still be *read* as **context**: judging whether a "why" is recoverable
   often requires reading the surrounding module, even outside the scope.
2. Understand the project's domain — what business rules, algorithms, or protocols does it implement?
3. Note existing documentation patterns (JSDoc style, inline comment conventions, README structure).

### Phase 2: Scan for Documentation Gaps

Run every scan against the target scope (`SCOPE=.` in codebase mode).

```bash
# Production-scan exclusions: dependencies, build output, generated code, tests
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

# setTimeout / setInterval with non-obvious delays
rg 'setTimeout|setInterval|delay|sleep' --type ts $EXCLUDE -- $SCOPE

# Workaround signals in code (but missing actual comments)
rg -i 'hack|workaround|fixme|todo' --type ts $EXCLUDE -- $SCOPE
```

There is deliberately **no grep for magic numbers, bitwise operations, or regex literals**: in TypeScript, `|`, `>>`,
and `<` are regex-indistinguishable from union types and generics, and any digit pattern either misses common
constants or matches every file — verified noise, not signal. Magic numbers have a durable detector in
`@typescript-eslint/no-magic-numbers` (the extension rule; the base `no-magic-numbers` must be disabled alongside
it): use its output if the project has it configured, and otherwise recommend enabling it *in the report* — do not
install packages or reconfigure ESLint to run this audit.

These are heuristic starting points. The primary method is **reading the code and identifying where a competent reader
would ask "why?"** — no grep pattern can substitute for that judgment.

### Phase 3: Evaluate Each Gap

For each candidate, determine:

- Would a competent reader of this language and domain genuinely pause here?
- Is the "why" recoverable from context (nearby code, naming, types), or is it truly missing?
- Is a comment the right fix, or should the code be restructured for clarity instead?

Classify each as:

- **Add comment**: the why is missing and a comment is the right fix
- **Rename/extract**: the code would be self-documenting with better naming or extraction
- **Skip**: the code is clear enough to a domain-literate reader

### Phase 4: Produce Report

## Output Format

Save as `YYYY-MM-DD-doc-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies an
output path (e.g. the party-hunter orchestrator), it overrides this default.

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

### Unexplained Business Rules

| # | Location | Code | Missing Context | Suggested Comment |
| - | -------- | ---- | --------------- | ----------------- |
| 1 | file:line | `if (age >= 26)` | Why 26? | `// Minimum age for policy X per regulation Y` |

### Magic Numbers

| # | Location | Value | Context | Action |
| - | -------- | ----- | ------- | ------ |
| 1 | file:line | `1.5` in retry calc | Backoff multiplier — origin unclear | Name as constant or comment source |

### Non-Obvious Algorithms

| # | Location | Code | Missing Context | Action |
| - | -------- | ---- | --------------- | ------ |
| 1 | file:line | Haversine formula | No reference to formula name or source | Add `// Haversine distance — see <ref>` |

### Workarounds

| # | Location | Code | Missing Context | Action |
| - | -------- | ---- | --------------- | ------ |
| 1 | file:line | 200ms delay before DOM read | Why the delay? What's it compensating for? | Comment with root cause and removal condition |

### Ordering Dependencies

| # | Location | Code | Missing Context | Action |
| - | -------- | ---- | --------------- | ------ |
| 1 | file:line | `init()` must precede `start()` | No indication of required ordering | Add comment or assert precondition |

### Surprising Behavior

| # | Location | Code | What's Surprising | Action |
| - | -------- | ---- | ----------------- | ------ |
| 1 | file:line | `process()` mutates input array | Name implies pure function | Comment or rename to `processInPlace()` |

### API Contracts

| # | Location | Signature | Missing Contract | Action |
| - | -------- | --------- | ---------------- | ------ |
| 1 | file:line | `setOpacity(value: number)` | Valid range? 0-1 or 0-100? | Add JSDoc with `@param` range |

## Recommendations (Priority Order)

1. **High**: {undocumented business rules, workarounds without context, magic numbers in core logic}
2. **Medium**: {non-obvious algorithms, surprising behavior, API contracts}
3. **Low**: {ordering dependencies, minor magic numbers in non-critical paths}
```

(Missing documentation is rarely Critical on its own; use Critical only when the missing "why" conceals an active
production hazard.)

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: missing "why" documentation only.** If a finding doesn't answer "would a reader pause here and ask
  why?", it belongs to another hunter — do not flag it here. Apply the comment ownership rule above for the
  doc/slop/smell split.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact code.
- **Judgment over pattern-matching.** Grep can find magic numbers and regex literals, but only reading the code reveals
  whether the "why" is truly missing. Prioritize manual review of complex logic over mechanical scanning.
- **Suggest, don't prescribe.** The "Suggested Comment" column is a starting point. The author knows the actual "why" —
  the audit identifies where it's missing, not what it should say.
- **Respect domain expertise.** Code that looks obscure to a generalist may be obvious to a domain expert. When
  uncertain, flag as "Consider" rather than "Must-fix".
