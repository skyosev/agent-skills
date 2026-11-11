# Invariant Hunter — report format

The report is, in order: `## Scope`; `## Findings` with one `###` section per category that has at least one finding;
`## Recommendations (Priority Order)`. Unbraced Scope lines appear on every run that reaches scanning; a `{braced}`
line appears only when its condition holds. A run that stops early (empty scope, no eligible source) writes the Scope
lines resolved so far and its `Audit completed` line, nothing else. A category with no findings gets no heading,
table, or "none found" line; a thin report is a valid result.

Go-only categories (Nil Pointer Risks, Zero-Value Traps, Context Misuse, Race Conditions) use the table schemas
supplied in `invariant-go.md`.

**Policy line.** Present only when repository instructions withdrew a pattern; quotes the instruction and names the
category and sites it withdrew.

**Evidence cells** follow each category's evidence bar in SKILL.md. Defect (Leaky Discriminated Unions) is one of
`parallel flag`, `no exhaustiveness arm`, `leaking field`, `cast past discriminant`. Complexity (Runtime Checks
Promotable to Types) is `low` / `medium` / `high` on a Promote row; on a Keep-as-runtime row it is the reason — `trust boundary`, `serialization`, or `type complexity: <what>`.

```md
# Invariant Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Commit: {short SHA}{, dirty working tree — line numbers match no commit; re-locate findings by symbol name}
- {Base: {ref} → merge base {short SHA} — diff scope only}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker / test paths}
- References loaded: {go, python, typescript as present}
- {excluded — no reference for .<ext>: {count} files — when applicable, naming each extension}
- {Deleted in diff: {list} — only for diff scope with deletions}
- {Policy: "{quoted instruction}" — withdraws {category} at {sites}}
- {Limitation: {type} in open unit {unit} permits omission of {field}; Loose Optionality withdrawn}
- {not read: {n} files — context budget}
- {Read split: {n} agents by {unit} — merged by this session}
- Audit completed: {N} findings

## Findings

### Unguarded Type Assertions

| # | Location | Assertion | Guard | Severity | Impact | Action |
| - | -------- | --------- | ----- | -------- | ------ | ------ |
| 1 | api/users.py:42 | `cast(User, payload)` | none | High | High | Parse `payload` with `User.model_validate` |
| 2 | render/node.go:31 | `switch n := v.(type)` over `Node` (open) with no `default` | none; the zero `Box` is returned | High | Medium | `default: return Box{}, fmt.Errorf("unknown node %T", v)` |

### Loose Optionality

| # | Location | Field | Evidence | Proposed | Severity | Impact | Action |
| - | -------- | ----- | -------- | -------- | -------- | ------ | ------ |
| 1 | model/node.ts:12 | `Node.parent?: Node` | set by `createRoot`, `createChild`, `fromJSON`; no later write or `delete` found in repo | `parent: Node` | Medium | High | Require at construction; drop four `??` sites |

### Defensive Access in Non-Boundary Code

| # | Location | Expression | Guaranteed By | Severity | Impact | Action |
| - | -------- | ---------- | ------------- | -------- | ------ | ------ |
| 1 | svc/render.py:56 | `user.name or ""` | `load_user()` sets `name` on every path | Medium | Medium | Make `name: str`; delete the `or` |

### Leaky Discriminated Unions

| # | Location | Union | Discriminant | Defect | Severity | Impact | Action |
| - | -------- | ----- | ------------ | ------ | -------- | ------ | ------ |
| 1 | shapes.py:30 | `Shape` | `kind` | no exhaustiveness arm | Medium | Medium | `else: assert_never(s)` |

### Runtime Checks Promotable to Types

| # | Location | Invariant | Current | Proposed | Complexity | Severity | Impact | Action |
| - | -------- | --------- | ------- | -------- | ---------- | -------- | ------ | ------ |
| 1 | mail/send.py:21 | address validated | `validate_email()` re-run per call | `Email` produced only by `parse_email()` | low | Medium | Medium | Promote |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).
Cascading effects — removing a fallback trips `noUnusedParameters`; requiring a field breaks a fixture — are named in
the Action column.
```
