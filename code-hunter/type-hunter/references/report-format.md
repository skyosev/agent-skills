# Type Hunter — report format

Read at Phase 5. Severity and Impact *definitions* live in SKILL.md; this file is the template and the per-category
table schemas.

Omit any category heading with zero findings — no empty tables, no placeholder subsections, no "none found" lines.
Every line of the Scope block below is filled in on every run; it is not a category and this rule does not reach it.

**Column ceiling.** No table carries more than eight columns beyond the `#` index, and Severity and Impact are two of
them. When a category needs more detail, trim an existing column rather than appending.

**No Toolchain lines.** No checker reports these categories; the Scope block carries none, and no type-checker
configuration is recorded (that is invariant-hunter's toolchain concern).

**Enumeration line.** Present whenever instantiations or duplicates were found by reading rather than by scan —
inference (TypeScript, Python, Go call sites) hides type arguments from regex; structural shapes hide duplicates.
States what was searched (explicit type arguments, call sites read, declaration census) and how the set was closed.
Findings claim the enumerated set only.

**Limitation lines.** One per withdrawn exported symbol whose consumer set could not be closed inside the tree, and
one per candidate withdrawn because a consolidation path or instantiation set could not be verified:
`Limitation: {symbol} published from {entry point}; consumer set not closed` or `Limitation: {symbol} — {what could
not be verified}`. A withdrawal is never a Low finding.

**Policy line.** Present only when repository instructions withdrew a pattern; quotes the instruction and names the
category and sites it withdrew.

**Evidence cells.**

- **Source** (Duplicated Type Declarations) is one of `sibling`, `runtime value`, `schema` — never a generated or
  external type. **Overlap** is `mapped/total`: members of the derived declaration that map onto the source over the
  derived declaration's member count. **Path** is the derive expression or `delete X`; for a schema derive the
  Evidence names the role (accepted input, decoded output, serialized data). For a repeated inline expression, Types
  lists the sites and Path is the alias.
- **Instantiations** (Generics That Never Vary) is the project-wide list, `(test)` marked, never a summary such as
  "always `User`" — a summary hides the test instantiation the Action must address. A long list is an accepted wide
  cell.
- **Body requires** (Loose Type Parameter Constraints) names the operation or the bridge; **Declared** is the current
  constraint. For the TypeScript `const` form, Body requires names the re-narrowing consumer.
- **Simpler form** (Over-Powered Type Constructs) is the replacement, and the Evidence states that it holds equal
  precision on every enumerated use.
- **Defect** (Enum Construct Mechanics) names the mechanical defect *and the paying consumer* (`file:line`).
- **Mixing site** (Alias vs Named Type Mechanics) is the Python call site where one alias meets the other; for Go it
  is `—` and Declaration carries the alias.
- **Promoted surface** (Embedding Antipatterns) is `promoted / used` with the used subset named.
- **TS version** (Reinvented Utility Types) is the lockfile version, shown to satisfy gate 1.

When within-skill precedence chose one category over another at a site, the reported finding's Evidence cell names the
other reading in one clause.

```md
# Type Hunter Audit — {date}

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
- {Enumeration: searched explicit type arguments + call sites of {symbol}; declaration census of {kinds}; set closed by {how}}
- {Limitation: {symbol} published from {entry point}; consumer set not closed}
- {Policy: "{quoted instruction}" — withdraws {category} at {sites}}
- Audit completed: {N} findings

## Findings

### Duplicated Type Declarations

| # | Location | Types | Source | Overlap | Path | Severity | Impact | Action |
| - | -------- | ----- | ------ | ------- | ---- | -------- | ------ | ------ |
| 1 | api/user.ts:12 | `UserSummary` ← `User` (domain/user.ts:4) | sibling | 2/2 | `Pick<User, 'id' \| 'name'>` | Medium | High | Replace the hand-listed interface with the derive; every handler imports `UserSummary` |
| 2 | model/role.ts:3 | `Role` ← `roles` (model/role.ts:1) | runtime value | 2/2 | `(typeof roles)[number]` | Medium | Medium | Add `as const` to `roles` and derive the union from it |
| 3 | store/row.go:9 | `UserRow` ← `User` (store/user.go:5) | sibling | 8/8 | `delete UserRow` | Medium | Medium | Every site of `UserRow` (store/scan.go:41, store/list.go:17) accepts `User`; delete the copy |
| 4 | api/schemas.py:22 | `Literal["red", "green"]` ← `Color` (model/color.py:4) | sibling | 2/2 | `delete the Literal` | Low | Low | Use `Color` at api/schemas.py:22; cross-referenced from Enum Construct Mechanics |

### Generics That Never Vary

| # | Location | Symbol | Parameter | Instantiations | Severity | Impact | Action |
| - | -------- | ------ | --------- | -------------- | -------- | ------ | ------ |
| 1 | cache/cache.go:8 | `Cache[T]` | `T any` | `Cache[User]` svc/user.go:31, svc/session.go:12; `Cache[fakeOrder]` cache/cache_test.go:19 (test) | Medium | Medium | Remove `T`; `Cache` holds `User`. The test's `fakeOrder` becomes a `User` fake |

### Loose Type Parameter Constraints

| # | Location | Symbol | Declared | Body requires | Severity | Impact | Action |
| - | -------- | ------ | -------- | ------------- | -------- | ------ | ------ |
| 1 | util/max.go:5 | `Max[T]` | `T any` | `>` — bridged by `any(a).(int)` at util/max.go:6 | Medium | Medium | `T cmp.Ordered` (Go 1.21+ per `go.mod`) replacing both assertions |
| 2 | util/get.ts:3 | `get<T>` | `T` (none) | index by string key — bridged by `(o as any)[k]` at util/get.ts:4 | Low | Low | `T extends Record<string, unknown>`; the `as any` is cited here, not scored by invariant-hunter |

### Over-Powered Type Constructs

| # | Location | Type | Construct | Simpler form | Severity | Impact | Action |
| - | -------- | ---- | --------- | ------------ | -------- | ------ | ------ |
| 1 | types/merge.ts:7 | `DeepMerge<A, B>` | 4-level conditional + recursion | `A & B` — every instantiation (cfg/load.ts:22, cfg/env.ts:9) is two flat objects with disjoint keys | Medium | Low | Replace; reintroduce the recursive form with the first nested or conflicting use |

### Enum Construct Mechanics

| # | Location | Group | Construct | Defect | Severity | Impact | Action |
| - | -------- | ----- | --------- | ------ | -------- | ------ | ------ |
| 1 | order/status.go:5 | `Active`, `Inactive`, `Suspended` | untyped `iota` block | untyped constants accepted where an `int` is — `SetStatus(3)` at api/order.go:44 compiles | Medium | Medium | `type Status int`; the constants take the type |
| 2 | order/status.ts:1 | `enum Status` | string `enum` | members only compared and serialized — api/order.ts:20, db/order.ts:33; value imports across 6 modules | Medium | Medium | `type Status = 'active' \| 'inactive'`; serialized as the same strings; `erasableSyntaxOnly` is set in tsconfig.json |

### Alias vs Named Type Mechanics

| # | Location | Declaration | Mixing site | Severity | Impact | Action |
| - | -------- | ----------- | ----------- | -------- | ------ | ------ |
| 1 | ids.py:3 | `UserId: TypeAlias = str`, `OrderId: TypeAlias = str` (ids.py:4) | `link(order_id, user_id)` at svc/link.py:28 against `link(user: UserId, order: OrderId)` | Medium | Medium | `NewType("UserId", str)`, `NewType("OrderId", str)`; the swap becomes a checker error |
| 2 | domain/id.go:6 | `type UserID = string` | — | Low | Low | `type UserID string`, or delete the alias; no migration comment, no second live name |

### Embedding Antipatterns

| # | Location | Struct | Embedded | Promoted surface | Severity | Impact | Action |
| - | -------- | ------ | -------- | ---------------- | -------- | ------ | ------ |
| 1 | server/server.go:14 | `Server` (exported) | `sync.Mutex` | `Lock`, `Unlock` / 0 used outside the package | High | Medium | `mu sync.Mutex` field |
| 2 | client/client.go:9 | `Client` | `*http.Client` | 6 / 1 — consumers call `Do` only (svc/fetch.go:22, svc/push.go:40) | Medium | Medium | Unexported field; `Do` delegated explicitly |

### Reinvented Utility Types

| # | Location | Type | Built-in | TS version | Severity | Impact | Action |
| - | -------- | ---- | -------- | ---------- | -------- | ------ | ------ |
| 1 | types/util.ts:3 | `MakeOptional<T>` | `Partial<T>` | 5.4 | Low | Low | Replace; homomorphic, modifiers preserved identically |

## Recommendations (Priority Order)

Group by Severity (High → Medium → Low). Within each group, order by Impact (High → Medium → Low). Each
recommendation names the consolidation path or replacement and what it removes; an Action that changes serialization
or a published surface names the risk.
```
