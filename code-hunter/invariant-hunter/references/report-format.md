# Invariant Hunter — report format

Read at Phase 6. Severity and Impact *definitions* live in SKILL.md; this file is the template and the per-category
table schemas.

Omit any category heading with zero findings — no empty tables, no placeholder subsections, no "none found" lines.
Every line of the Scope block below is filled in on every run; it is not a category and this rule does not reach it.

Go-only categories (Unchecked Errors, Nil Pointer Risks, Zero-Value Traps, Error Chain Correctness, Context Misuse,
Panic/Recover Misuse, Race Conditions) use the table schemas supplied in `invariant-go.md`.

**Column ceiling.** No table carries more than eight columns beyond the `#` index, and Severity and Impact are two
of them. When a category needs more detail, trim an existing column rather than appending.

**Toolchain lines.** One per tool per language, in the form `<tool>: ran — <command>, <version>, <coverage>,
<options that change what it sees>` / `skipped — not configured` / `skipped — configured, not installed` /
`errored — <message>`, followed by the strictness flags read from the applicable config. A tool that ran with
`errcheck -blank` off says so; it is not coverage of `_ = f()`.

**Policy line.** Present only when repository instructions withdrew a pattern; quotes the instruction and names the
category and sites it withdrew.

**Evidence cells.** Guard (Unguarded Type Assertions) names the check present: `none`, `isinstance on sibling`,
`zod parse`, and when present, whether it reaches the asserted property. Evidence (Loose Optionality) is the
construction-and-mutation argument in one cell: every producer and every later write read. When the type is
constructible outside the repository — a library's public type — and its contract permits omission, the finding is
withdrawn and recorded as a Scope limitation, not reported at lower confidence. Guaranteed By (Defensive Access) names
the upstream site that always sets the value. Defect (Leaky Discriminated Unions) is one of `parallel flag`,
`no exhaustiveness arm`, `leaking field`, `cast past discriminant`. Justification (Type-System Bypasses) is `none`,
`bare`, or the quoted reason.

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
- Toolchain: {per language — `go vet ./...: ran — go1.26, ./..., default analyzers` / `errcheck: skipped — not configured` / `tsc --noEmit: ran — 5.9, tsconfig.json; strict on, exactOptionalPropertyTypes off` / `mypy: errored — <message>`}
- {Policy: "{quoted instruction}" — withdraws {category} at {sites}}
- {Limitation: {library public type} permits omission of {field}; Loose Optionality withdrawn}
- Audit completed: {N} findings

## Findings

### Unguarded Type Assertions

| # | Location | Assertion | Guard | Severity | Impact | Action |
| - | -------- | --------- | ----- | -------- | ------ | ------ |
| 1 | api/users.ts:42 | `(await res.json()) as User` | none | High | High | Parse with `UserSchema` |
| 2 | store/load.go:88 | `v.(*Config)` | none | High | Medium | `c, ok := v.(*Config)` |

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
| 1 | shapes.ts:30 | `Shape` | `kind` | no exhaustiveness arm | Medium | Medium | `default: assertNever(s)` |

### Runtime Checks Promotable to Types

| # | Location | Invariant | Current | Proposed | Complexity | Severity | Impact | Action |
| - | -------- | --------- | ------- | -------- | ---------- | -------- | ------ | ------ |
| 1 | mail/send.py:21 | address validated | `validate_email()` re-run per call | `Email` produced only by `parse_email()` | low | Medium | Medium | Promote |

### Type-System Bypasses

| # | Location | Pattern | Justification | Severity | Impact | Action |
| - | -------- | ------- | ------------- | -------- | ------ | ------ |
| 1 | core/merge.ts:9 | `as any` | none | Medium | Medium | Type the merge result |
| 2 | io/ffi.py:14 | `# type: ignore` | bare | Low | Low | Add the error code and reason |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).
Cascading effects — removing a fallback trips `noUnusedParameters`; requiring a field breaks a fixture — are named in
the Action column.
```
