---
name: golang-review
description: |
  Act as a senior Go engineer performing a critical design and testing review.
  Evaluates architecture, patterns, idiomaticity, over-engineering, testing strategy,
  and proposes concrete improvements — all grounded in the codebase.

  Use when: reviewing a Go codebase for design soundness, testing robustness,
  or overall code quality before merging or after prototyping.
---

# Go Code Review

Perform a **senior-level design and testing review** of a Go codebase. Evaluate architecture, patterns,
idiomaticity, over-engineering, and testing strategy. Produce a report with concrete, codebase-grounded
improvements.

## Core Principles

1. **Idiomatic Go first.** Architecture and patterns must follow Go conventions — explicit error handling, small
   interfaces, flat package layout, composition over inheritance. If a pattern fights the language, replace it.

2. **Simplicity is robustness.** The simplest design that meets real requirements wins. Reject abstractions, layers,
   and indirections that aren't backed by actual use cases.

3. **Test at the right level.** Unit tests for logic, integration tests for boundaries, end-to-end for critical paths.
   Don't over-mock; don't under-test. The strategy must be practical to implement and maintain.

4. **Every conclusion grounded in code.** No hand-waving. Every finding must cite specific files, functions, and lines
   from the codebase as evidence.

5. **Improvements must earn their place.** Every suggested change must explain why it is better (simplicity,
   robustness, maintainability) and acknowledge trade-offs.

## What to Review

### 1. Design & Architecture

Evaluate whether the architecture and patterns are idiomatic, simple, and robust.

**Signals to check:**

- Is the package layout flat and responsibility-aligned, or deeply nested without reason?
- Are interfaces small and consumer-defined, or bloated and producer-defined?
- Does error handling follow Go idioms, or is it wrapped in non-standard patterns?
- Are dependencies explicit, or hidden behind global state and init functions?
- Is composition used over inheritance-style embedding?

**Action:** Flag non-idiomatic patterns with the idiomatic alternative. Flag unclear responsibilities or missing
boundaries that could cause implementation or maintenance issues.

### 2. Over-Engineering

Detect abstractions, layers, or extensibility that aren't backed by real requirements.

**Signals to check:**

- Unnecessary wrappers, managers, registries, or factories with a single consumer
- Premature generalization — generic solutions for problems that have one concrete case
- Indirection layers that add no logic (pass-through functions, trivial delegation)
- Configuration or plugin systems for behavior that will never vary

**Action:** Recommend removal or inlining. If the abstraction exists for a stated future need, note it and assess
whether the cost is justified.

### 3. Testing Strategy

Assess whether the testing approach is aligned with the architecture and covers the right cases.

**Signals to check:**

- Are critical paths and edge cases covered by tests?
- Is the test level appropriate? (unit for logic, integration for boundaries, e2e for flows)
- Are mock boundaries clean, or is the test tightly coupled to internal implementation?
- Are there overly complex or brittle test patterns (excessive setup, fragile assertions)?
- Is there a testing guide (e.g., `docs/testing_guide.md`)? If so, does the code follow it?

**Action:** If the strategy is misaligned or has gaps, propose a rebalanced approach — what to test, where, and how.

### 4. Concrete Improvements

Synthesize findings into actionable changes.

**For each improvement:**

- State the specific change (simplification, alternative pattern, rebalanced test)
- Explain why it is better (simplicity, robustness, maintainability)
- Note any trade-offs

## Review Workflow

### Phase 1: Gain Context

1. **Resolve review surface.** The prompt may specify the scope as:
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project
   If unspecified, default to **codebase**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent analysis to the resolved surface.
2. Read project documentation: `AGENTS.md`, `README.md`, `docs/testing_guide.md` (if they exist).
3. Identify the main components, responsibilities, and data flows.

### Phase 2: Design & Architecture Scan

1. Review package layout and dependency structure — assess if it follows Go conventions.
2. Check interfaces, error handling, and composition patterns for idiomaticity.
3. Identify unclear responsibilities, missing boundaries, or hidden dependencies.
4. Evaluate whether patterns fight the language or embrace it.

### Phase 3: Over-Engineering Scan

1. Identify interfaces and assess whether they have multiple implementations or justify their abstraction.
2. Look for factory patterns, managers, and registries — evaluate if they serve multiple consumers.
3. Find pass-through wrappers and delegation functions that add no logic.
4. Assess whether abstractions are backed by real requirements or are premature optimization.

### Phase 4: Testing Strategy Scan

1. Analyze test file distribution across packages — identify gaps in coverage.
2. Evaluate test helpers and mocks — check for clean boundaries vs. tight coupling.
3. Assess test patterns (table-driven, subtests) for appropriateness and maintainability.
4. Review test level alignment — ensure unit tests focus on logic, integration tests on boundaries.

### Phase 5: Produce Report

## Output Format

Save as `YYYY-MM-DD-code-review-{$LLM-name}.md` in the project's docs folder (or project root if no docs folder
exists).

```md
# Go Code Review — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Design & Architecture Assessment

| # | Location | Finding | Impact | Recommendation |
| - | -------- | ------- | ------ | -------------- |
| 1 | file:line | Non-idiomatic error wrapping pattern | Readability, consistency | Use `fmt.Errorf` with `%w` |

## Over-Engineering

| # | Location | Abstraction | Consumers | Recommendation |
| - | -------- | ----------- | --------- | -------------- |
| 1 | file:line | `ConfigManager` struct | 1 | Inline |

## Testing Strategy Assessment

| # | Location | Finding | Gap / Issue | Recommendation |
| - | -------- | ------- | ----------- | -------------- |
| 1 | pkg/auth/ | No integration tests | Auth boundary untested | Add integration test for token flow |

## Proposed Improvements (Priority Order)

1. **Must-fix**: {critical design issues, missing critical test coverage}
2. **Should-fix**: {over-engineering, misaligned test levels, non-idiomatic patterns}
3. **Consider**: {minor simplifications, test ergonomics, documentation gaps}
```

## Operating Constraints

- **No code edits.** This skill produces a review report only. Implementation is a separate step.
- **Scope: design, idiomaticity, and testing.** This is a holistic review. For deep-dive audits on specific concerns
  (simplicity, boundaries, types, security, etc.), use the dedicated hunter-party-go skills.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code.
- **Tone: professional, direct, and technical.** Be strict and honest — do not hesitate to call out weaknesses or
  unnecessary complexity.
- **Improvements must explain trade-offs.** Every recommendation must state why it is better and what, if anything,
  it costs.
- **Respect Go idioms.** Go's explicit error handling, lack of generics in older code, and verbose patterns are
  idiomatic, not flaws. Flag deviations from idiom, not the idiom itself.
