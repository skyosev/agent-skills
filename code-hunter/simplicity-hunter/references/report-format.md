# Simplicity Hunter — report format

The report is, in order: `## Scope`; `## Findings` with one `###` section per category that has at least one finding;
`## Recommendations (Priority Order)`. Unbraced Scope lines appear on every run that reaches scanning; a `{braced}`
line appears only when its condition holds. A run that stops early (empty scope, no eligible source) writes the Scope
lines resolved so far and its `Audit completed` line, nothing else. A category with no findings gets no heading,
table, or "none found" line; a thin report is a valid result.

Language-only categories appended by a language reference (Go: Interface Pollution, Channel & Goroutine Overuse) use
the table schemas supplied in that reference.

```md
# Simplicity Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Commit: {short SHA}{, dirty working tree — line numbers match no commit; re-locate findings by symbol name}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker}
- References loaded: {go, python, typescript as present}
- {excluded — no reference for .<ext>: {count} files — one line per unsupported extension in the manifest}
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
