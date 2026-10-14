# Slop Hunter — report format

The report is, in order: `## Scope`; `## Findings` with one `###` section per category that has at least one finding;
`## Recommendations (Priority Order)`. Unbraced Scope lines appear on every run that reaches scanning; a `{braced}`
line appears only when its condition holds. A run that stops early (empty scope, no eligible source) writes the Scope
lines resolved so far and its `Audit completed` line, nothing else. A category with no findings gets no heading,
table, or "none found" line; a thin report is a valid result.

Language-only categories appended by a language reference (Go: Unnecessary Error Wrapping) use the table
schema supplied in that reference.

**Consolidated rows** (SKILL.md Style Drift → Consolidation): Occurrences is `N`, or `≥ N` for a partial scan; every
other row has `Occurrences: 1`. `Audit completed` counts every reported finding, a consolidated row once.

**Convention cell.** Names the baseline source used — config file, repository instruction, nearby code, or style
guide. For a formatter finding in diff mode it also carries the touched-line rule: `gofmt, touched line`.

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
- Formatter: {per language — ran <tool> / skipped — <reason> / errored — <message>}
- {baseline uncertain: <concern> — one line per concern, when any}
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

| # | Location | Pattern | Convention | Occurrences | Severity | Impact | Action |
| - | -------- | ------- | ---------- | ----------- | -------- | ------ | ------ |
| 1 | svc/user.py:12 | `userName` | `snake_case` — `ruff.toml` N815, nearby code | 1 | Low | Medium | Rename |
| 2 | cmd/run.go:7 | import grouping | `gofmt, touched line` | 1 | Low | Low | Run `gofmt -w` |
| 3 | web/view.tsx:3 | unformatted file | Prettier — `package.json` `format` script | 14 | Low | Medium | Run `prettier --write` |

### Trivially Dead Code

| # | Location | Code | Severity | Impact | Action |
| - | -------- | ---- | -------- | ------ | ------ |
| 1 | util/parse.py:3 | `import re` — last use removed in this change (used at merge base `a1b2c3d`) | Low | Low | Delete |
| 2 | handler.go:55 | `//nolint:errcheck` with no reason | Medium | Medium | State the reason; dropped error → invariant-hunter Unchecked Errors |

### Hedging and Narration

| # | Location | Pattern | Severity | Impact | Action |
| - | -------- | ------- | -------- | ------ | ------ |
| 1 | worker.ts:88 | `console.log('entering process')` | Low | Low | Delete |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).
```
