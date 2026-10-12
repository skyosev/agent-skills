---
name: enriching-plans
description: Enrich a reviewed lean plan in place with seams, test outlines, open decisions and small critical-code blocks.
disable-model-invocation: true
---

# Enriching Plans

A lean plan records the decisions: files, signatures, task order. Enrichment adds the **shape** of each piece: the seams between components, what a file is responsible for, which tests it holds and what each one proves, and the decisions the spec forces. The implementer writes the code. An enriched plan that holds it has become a **transcript** of the program. Code appears only where The Line Between Shape and Code allows.

## Before You Start

1. Read the plan, its spec, and the code the plan touches.
2. The plan has been reviewed. Its paths, names, task boundaries and step order are fixed, including names that look like typos. If you think one is wrong, add it to `## Questions for Reviewer` and keep using it as written.
3. Signatures may grow only through a seam (see Seams). Never rename or remove anything.
4. Write everything in the plan's own language (TS, Go, Python, …), test framework and naming conventions. Read them from the existing code and tests.
5. Edit the plan file in place. Keep every original line, and add the enrichment beneath the step it serves.

## Seams: Required on Every Task

A seam is an abstraction that lets one side of a boundary change without editing the other: a dependency injected through a constructor or parameter, or a contract between tasks. Write it in the project language's own form, for example a TS `interface` or function type, a Python `Protocol`, a Go `interface` declared in the consuming package, a Rust `trait` etc.

Under each task's **Interfaces** block, add a `> **Seams:**` block. It holds two kinds of entry.

**Contracts with other tasks.** List the exact declaration of every type and signature this task consumes from, or provides to, another task. They are declared, not injected: a task calls another task's pure function directly.

**Injected dependencies.** For each one, give:
- the **exact declaration**, copied verbatim or written by you;
- **who implements it** in production, and **who consumes it**;
- **what the tests substitute** for it.

A dependency is **effectful** when it touches time, network, filesystem, database, randomness, environment or a process, directly or through another module that does. The task's code has an effectful dependency and the plan declares no seam for it? Then **add the seam**:
1. Declare it in the Seams block.
2. Extend the produced signature to receive it, so that every call written against the plan's signature still compiles. Use default parameters in TS or Python. Go has no defaults, so keep the planned function and add functional options (`NewX(opts ...Option)`) or an unexported variant that takes the dependency (`deliverWith(ctx, e, client)`).
3. Log it in `## Enrichment Decisions`.

Pure, deterministic code is called directly, never injected. A task with no cross-task contracts and no effectful dependencies gets `> **Seams:** none — pure` and the reason.

## What an Enrichment Block Contains

A step gets a block when its implementer could write more than one reasonable thing from it. Pick the recipe that matches the step. Each item is a short line of prose or an exact value.

| Step kind | Enrichment contains |
|---|---|
| **Test file / test step** | A test outline in the project's own convention: groups, then test names. For example, `describe`/`it` (JS), a pytest class with `test_` functions, Go `TestXxx` with `t.Run` subtests, or JUnit methods. Each test name states the behavior ("draws the shared edge heavy when either neighbour is focused"). Under each name, one line: *given* (the input, using the spec's exact values) → *expect* (the exact result). Name any shared fixture helper and say what it builds, in one line. |
| **New source file** | Its responsibility in one sentence. The exported signatures, copied exactly from the Interfaces block, plus any seam parameters from the Seams block. What it depends on and what depends on it. Invariants it must hold (purity, no mutation, bounds). |
| **Implement step** | Only the **decisions** the signature and the test outline leave open, each with its reason (e.g. "two passes, so that pane order can't change the output"). Behavior the tests already pin is referenced ("pinned by Step 1"), not restated. No open decisions means no block. |
| **Modify existing file** | Where the change goes (symbol name), what behavior changes, and what must stay as it is. |
| **Run / verify step** | A block only when the lean step lacks the command or the expected result. Then add just that. |
| **Commit step** | No block. |

## Two Sections You Add to the Plan

- `## Enrichment Decisions`: anything the spec does not settle that you had to choose (a glyph set the spec didn't list, how truncation is counted, what happens on overlap). One line each: the decision, its reason, and which tests pin it. Global Constraints holds only what the spec says.
- `## Questions for Reviewer`: names you think are wrong, contradictions between the plan and the spec, and gaps you couldn't settle.

## The Line Between Shape and Code

The test: could this line be pasted into a source file and compile? If so, it belongs in the plan only when it is an exported signature, a seam or type declaration, an exact value from the spec, or part of a critical-code block. Anything else is transcript.

| Shape (belongs in plan) | Code (implementer writes) |
|---|---|
| Test name "truncates a long title with … and keeps the corner". given width 8, title `terminal` → top row `┌─ te… ┐` | The test body, assertion calls, fixture literals |
| "Accumulate edges per cell, then map them to glyphs. Junctions fall out of the merge, with no adjacency detection." | The accumulator's type, key format, loop bounds, helper names |
| "`glyphFor` is total: an empty set gives `' '`" | The lookup table, bit encoding, `if` chains |

## Critical-Code Blocks

Some code is critical: the signature and the test outline do not determine it, and a reasonable implementer could get it subtly wrong. Examples: a non-obvious algorithm or formula, an ordering or concurrency sequence, a security check, a regex, a wire format, a migration statement. For that code, add a block under the implement step:

````markdown
  > **Critical code** (why: <the specific way an implementer would get it wrong>):
  > ```<language>
  > <the critical part of the code>
  > ```
````

The `why` names a concrete failure, for example "`raise_for_status` treats 3xx as success; the spec says non-2xx fails". The block holds only the lines where that failure would happen. Elide everything around them with `…`. A block that would contain a whole function body is not critical code. Write its decisions as one-liners instead. Code a competent implementer would write correctly from the tests also gets a one-line decision instead.

## Example

The example is TypeScript with vitest.

The lean task produces `class TokenBucket { take(): boolean }`, and its Step 1 reads `Create test/limits/tokenBucket.test.ts`. The enriched version:

```markdown
**Interfaces:**
- Produces: `class TokenBucket { take(): boolean }`

> **Seams:**
> - `export interface Clock { now(): number }` (ms). Production: `systemClock` (wraps `Date.now`). Consumer: `TokenBucket`. Tests: a `FakeClock` whose time they set.
> - Signature grows to `new TokenBucket(capacity: number, refillPerSec: number, clock: Clock = systemClock)`. Logged in Enrichment Decisions.

- [ ] **Step 1: Create `test/limits/tokenBucket.test.ts`**

  > **Enrichment:** helper `bucket(capacity, refillPerSec)` returns the bucket and its `FakeClock`.
  > `describe("TokenBucket.take")`
  > - `it("allows bursts up to capacity")`: capacity 3 → three `take()` calls return true, the fourth returns false
  > - `it("refills at the configured rate")`: drain, advance the clock 500 ms at 2/s → exactly one `take()` succeeds
  > - `it("never refills above capacity")`: advance the clock 10 s idle → still only 3 succeed
  > - `it("rejects a non-positive capacity")`: `bucket(0, 1)` throws `RangeError`
```

## Self-Check Before Saving

- Every call written against the plan's signatures still compiles.
- Every task has a Seams block.
- Every dependency a test fakes, stubs or mocks reaches the code through a declared seam.
- Every test step lists its test names, each with given → expect.
- Code appears only as signatures, declarations, spec values, or critical-code blocks, each with a concrete `why` and holding only the lines where that failure would happen.
- Run, verify and commit steps that already named their command carry no block.

