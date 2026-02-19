---
name: doc-hunter
description: |
  Audit TypeScript code for missing inline documentation where the "why" is not obvious —
  obscure calculations, non-trivial business rules, surprising behavior, implicit constraints,
  and workarounds. Finds where a comment would save the next reader significant time.

  Use when: reviewing TypeScript code for long-term maintainability, onboarding new team members,
  auditing undocumented business logic, or preparing code for handoff.
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

Code where the execution order matters but isn't enforced by the type system or control flow.

**Signals:**

- Functions that must be called in a specific sequence (init before use, A before B)
- State mutations that depend on prior mutations having occurred
- Event handler registration that assumes a particular lifecycle order
- Async operations that depend on a prior operation having completed (without explicit await)
- Array operations that assume sorted input without asserting it

**Action:** Flag for a comment explaining the ordering constraint and what breaks if violated.

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
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or layers
   - **Codebase**: the entire project
   If unspecified, default to **codebase**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent scans to the resolved surface.
2. Understand the project's domain — what business rules, algorithms, or protocols does it implement?
3. Note existing documentation patterns (JSDoc style, inline comment conventions, README structure).

### Phase 2: Scan for Documentation Gaps

```bash
EXCLUDE='--glob !**/*.test.* --glob !**/*.spec.* --glob !**/node_modules/** --glob !**/dist/**'

# Magic numbers in logic (numeric literals in non-trivial expressions)
rg --pcre2 '[^0-9][2-9]\d{1,}[^0-9]|0x[0-9a-f]{2,}|\d+\.\d+' --type ts $EXCLUDE

# Regex literals (often need explanation)
rg --pcre2 '/[^/]{15,}/' --type ts $EXCLUDE

# Bitwise operations
rg --pcre2 '<<|>>|[^&]&[^&]|[^|]\|[^|]|\^' --type ts $EXCLUDE

# setTimeout / setInterval with non-obvious delays
rg 'setTimeout|setInterval|delay|sleep' --type ts $EXCLUDE

# Workaround signals in code (but missing actual comments)
rg -i 'hack|workaround|fixme|todo' --type ts $EXCLUDE
```

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

Save as `YYYY-MM-DD-doc-hunter-audit.md` in the project's docs folder (or project root if no docs folder exists).

```md
# Doc Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

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

1. **Must-fix**: {undocumented business rules, workarounds without context, magic numbers in core logic}
2. **Should-fix**: {non-obvious algorithms, surprising behavior, API contracts}
3. **Consider**: {ordering dependencies, minor magic numbers in non-critical paths}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: missing "why" documentation only.** Do not flag redundant or verbose comments (→ slop-hunter), structural
  complexity (→ simplicity-hunter), type invariants (→ invariant-hunter), type design (→ type-hunter), module boundary
  issues (→ boundary-hunter), class/interface design (→ solid-hunter), security (→ security-hunter), or test quality
  (→ test-hunter). If a finding doesn't answer "would a reader pause here and ask why?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact code.
- **Judgment over pattern-matching.** Grep can find magic numbers and regex literals, but only reading the code reveals
  whether the "why" is truly missing. Prioritize manual review of complex logic over mechanical scanning.
- **Suggest, don't prescribe.** The "Suggested Comment" column is a starting point. The author knows the actual "why" —
  the audit identifies where it's missing, not what it should say.
- **Respect domain expertise.** Code that looks obscure to a generalist may be obvious to a domain expert. When
  uncertain, flag as "Consider" rather than "Must-fix".
