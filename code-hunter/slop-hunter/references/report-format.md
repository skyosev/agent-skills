# Slop Hunter — report format

The report is, in order: `## Scope`; `## Findings` with one `###` section per category that has at least one finding;
`## Recommendations (Priority Order)`. Unbraced Scope lines appear on every run that reaches scanning; a `{braced}`
line appears only when its condition holds. A run that stops early (empty scope, no eligible source) writes the Scope
lines resolved so far and its `Audit completed` line, nothing else. A category with no findings gets no heading,
table, or "none found" line; a thin report is a valid result.

Language-only categories appended by a language reference (Go: Unnecessary Error Wrapping) use the table
schema supplied in that reference.

**Convention cell.** Names the baseline source used — config file, repository instruction, nearby code, or style
guide.

```md
# Slop Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Commit: {short SHA}{, dirty working tree — line numbers match no commit; re-locate findings by symbol name — when dirty}
- {Base: {ref} → merge base {short SHA} — diff scope only}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists}
- {Exclusions: {list — vendored / lockfile / md-only / generated-by-marker} — when any file was dropped}
- References loaded: {go, python, typescript as present}
- {excluded — no reference for .<ext>: {count} files — when applicable, naming each extension}
- {Deleted in diff: {list} — only for diff scope with deletions}
- {baseline uncertain: <concern> — one line per concern, when any}
- {not read: {n} files — context budget}
- {Read split: {n} agents by {unit} — merged by this session}
- Audit completed: {N} findings

## Findings

### Redundant Comments

| # | Location | Comment | Severity | Impact | Action |
| - | -------- | ------- | -------- | ------ | ------ |
| 1 | store/items.go:42 | `// Initialize the slice` | Low | Low | Delete |

### Verbose Documentation

| # | Location | Symbol | Redundant Part | Severity | Impact | Action |
| - | -------- | ------ | -------------- | -------- | ------ | ------ |
| 1 | api/users.ts:18 | `createUser()` | `@param name - the name`, `@returns the user` | Low | Medium | Strip the tags |

### Style Drift

| # | Location | Pattern | Convention | Severity | Impact | Action |
| - | -------- | ------- | ---------- | -------- | ------ | ------ |
| 1 | store/order.go:12 | `func CreateOrder(…)` | `New*` constructors — nearby code (`store/user.go`, `store/item.go`) | Low | Medium | Rename to `NewOrder` |

### Trivially Dead Code

| # | Location | Code | Severity | Impact | Action |
| - | -------- | ---- | -------- | ------ | ------ |
| 1 | util/parse.py:3 | `# TODO: fix this` — no owner, ticket, or condition | Low | Low | Delete, or name the owner |
| 2 | handler.go:55 | `//nolint:errcheck` with no reason | Medium | Medium | State the reason |

### Hedging and Narration

| # | Location | Pattern | Severity | Impact | Action |
| - | -------- | ------- | -------- | ------ | ------ |
| 1 | worker.ts:88 | `logger.debug('entering process')` | Low | Low | Delete |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).
```
