# Slop Hunter — report format

Read at Phase 6. Severity and Impact *definitions* live in SKILL.md; this file is the template and the per-category
table schemas.

Omit any category heading with zero findings — no empty tables, no placeholder subsections, no "none found" lines.
Every line of the Scope block below is filled in on every run; it is not a category and this rule does not reach it.

Language-only categories appended by a language reference (today: Unnecessary Error Wrapping for Go) use the table
schema supplied in that reference.

**Column ceiling.** No table carries more than eight columns beyond the `#` index, and Severity and Impact are two
of them. When a category needs more detail, trim an existing column rather than appending.

**Consolidated rows.** A Style Drift row may stand for N occurrences of one rule-enforceable pattern. Location is the
representative site; Occurrences is `N` (enumerated) or `≥ N` (partial scan); the Action fits the enforcement state
(run the fixer / enable the rule and fix / fix the N sites). Every other row has `Occurrences: 1`. A consolidated row
counts once in `Audit completed`.

**Convention cell.** Names the baseline source used — config file, repository instruction, nearby code, or style
guide. For a formatter finding in diff mode it also carries the touched-line rule: `gofmt, touched line`.

```md
# Slop Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Commit: {short SHA}{, dirty working tree — line numbers match no commit; re-locate findings by symbol name}
- {Base: {ref} → merge base {short SHA} — diff scope only}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker}
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
| 2 | handler.go:55 | `//nolint:errcheck` with no reason | Medium | Medium | State the reason or handle the error |

### Hedging and Narration

| # | Location | Pattern | Severity | Impact | Action |
| - | -------- | ------- | -------- | ------ | ------ |
| 1 | worker.ts:88 | `console.log('entering process')` | Low | Low | Delete |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).
```
