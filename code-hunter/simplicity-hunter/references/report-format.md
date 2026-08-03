# Simplicity Hunter — report format

Read at Phase 6. Severity and Impact definitions live in SKILL.md; this file is the template and the per-category
table schemas.

Omit any category heading with zero findings — no empty tables, no placeholder subsections, no "none found" lines.
The Scope section's status lines are the exception and always appear.

Language-only categories appended by a language reference (today: Interface Pollution, Channel & Goroutine Overuse)
use the table schemas supplied in that reference.

```md
# Simplicity Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker}
- References loaded: {go, python, typescript as present}
- {no reference for .<ext> — language-specific categories skipped — when applicable}
- {Deleted in diff: {list} — only for diff scope with deletions}
- {Coexisting generations: skipped — requires codebase or path scope — only for diff scope}
- Audit completed: {N} findings

## Findings

### Duplication

| # | Locations | Description | Severity | Impact | Action |
| - | --------- | ----------- | -------- | ------ | ------ |
| 1 | a:10, b:20 | Near-identical validation | Medium | High | Eliminate via existing schema |

### Reinvented Primitives

| # | Location | Hand-rolled | Primitive | Toolchain | Severity | Impact | Action |
| - | -------- | ----------- | --------- | --------- | -------- | ------ | ------ |
| 1 | file:line | loop contains | `slices.Contains` | go 1.21 | Low | Medium | Replace |

### Unnecessary Abstractions

| # | Location | Abstraction | Consumers | Severity | Impact | Action |
| - | -------- | ----------- | --------- | -------- | ------ | ------ |
| 1 | file:line | `ConfigManager` | 1 | Medium | Medium | Inline |

### Dead Code Paths

| # | Location | Code | Evidence | Severity | Impact | Action |
| - | -------- | ---- | -------- | -------- | ------ | ------ |
| 1 | file:line | `legacyHandler()` | 0 call sites; not in registry | Low | High | Delete |

### Over-Parameterized APIs

| # | Location | Function | Params | Severity | Impact | Action |
| - | -------- | -------- | ------ | -------- | ------ | ------ |
| 1 | file:line | `render(...)` | 5 (3 bools) | Medium | Medium | Split by use case |

### Mixed Concerns

| # | Location | Function | Concerns | Severity | Impact | Action |
| - | -------- | -------- | -------- | -------- | ------ | ------ |
| 1 | file:line | `processOrder()` | fetch + transform + log | Medium | Medium | Extract 3 helpers |

### Complex Control Flow

| # | Location | Pattern | Depth | Severity | Impact | Action |
| - | -------- | ------- | ----- | -------- | ------ | ------ |
| 1 | file:line | Nested if/else | 4 | Low | Low | Flatten with guards |

### Coexisting Generations

| # | Concern | Strata | Live evidence | Survivor (capability/intent) | Severity | Impact | Action |
| - | ------- | ------ | ------------- | ---------------------------- | -------- | ------ | ------ |
| 1 | HTTP | a:12 (axios), b:8 (fetch) | migration names axios; 14 vs 3 | axios — intent | Medium | High | Move 3; drop fetch |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).
```
