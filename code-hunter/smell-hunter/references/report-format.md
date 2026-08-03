# Smell Hunter — report format

Read at Phase 6. Severity and Impact *definitions* live in SKILL.md; this file is the template and the per-category
table schemas.

Omit any category heading with zero findings — no empty tables, no placeholder subsections, no "none found" lines.
Every line of the Scope block below is filled in on every run; it is not a category and this rule does not reach it.

Language-only categories appended by a language reference (today: `init()` Abuse and Stuttering Names for Go, Mutable
Default Arguments for Python) use the table schemas supplied in that reference.

**Column ceiling.** No canonical table carries more than eight columns beyond the `#` index, and Severity and Impact
are two of them. When a category needs more detail, trim an existing column rather than appending — Feature Envy's
`Own/Foreign` ratio replaces the former separate "Own Data Used" and "Foreign Data Used" columns for exactly this
reason. **Areas** is the neutral term for the unit of code organization: a Go package is not a module, and a Python
module is not a package.

```md
# Smell Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker}
- References loaded: {go, python, typescript as present}
- {excluded — no reference for .<ext>: {count} files — when applicable, naming each extension}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Audit completed: {N} findings

## Findings

### Feature Envy

| # | Location | Function | Envied Type | Own/Foreign | Evidence | Severity | Impact | Action |
| - | -------- | -------- | ----------- | ----------- | -------- | -------- | ------ | ------ |
| 1 | orders/format.go:42 | `FormatOrder()` | `billing.Invoice` | 0/5 | `inv.Total + inv.Tax…` | Medium | Medium | Move to `billing` |

### Data Clumps

| # | Locations | Parameters/Fields | Evidence | Suggested Type | Severity | Impact | Action |
| - | --------- | ----------------- | -------- | -------------- | -------- | ------ | ------ |
| 1 | a:10, b:22, c:31 | `host, port, scheme` | 3 signatures | `Endpoint` | Low | High | Extract type |

### Shotgun Surgery

| # | Location | Concept | Areas Touched | Commits | Severity | Impact | Action |
| - | -------- | ------- | ------------- | ------- | -------- | ------ | ------ |
| 1 | pay/dispatch.go:60 | "Add a payment method" | 5 (`pay`, `api`, `db`, `ui`, `cfg`) | `a1b2c3d`, `e4f5g6h` | Medium | High | Registry dispatch |

The `Location` column is mandatory: the in-scope site that must be edited per variant. Commits support it; they
never replace it.

### Temporal Coupling

| # | Location | Unit | Required Order | Severity | Impact | Action |
| - | -------- | ---- | -------------- | -------- | ------ | ------ |
| 1 | server.ts:18 | `Server` | `init()` → `start()` | Medium | Medium | Require deps at construction |

### Comments as Deodorant

| # | Location | Comment | Severity | Impact | Action |
| - | -------- | ------- | -------- | ------ | ------ |
| 1 | intake.py:77 | `# Parse and validate the user input` | Low | Medium | Extract `parse_and_validate_input()` |

### Temporary Field

| # | Location | Type | Field | Used In | Severity | Impact | Action |
| - | -------- | ---- | ----- | ------- | -------- | ------ | ------ |
| 1 | proc.go:14 | `Processor` | `lastResult` | `Process()` only | Low | Low | Method-local var or return value |

### Primitive Obsession

| # | Location | Parameter/Field | Current Type | Evidence | Suggested Type | Severity | Impact | Action |
| - | -------- | --------------- | ------------ | -------- | -------------- | -------- | ------ | ------ |
| 1 | xfer.ts:30 | `userId` | `string` | swappable with `orderId` | `UserId` (branded) | High | High | Define branded type |

### God Module

| # | Location | Module | Lines | Responsibilities | Severity | Impact | Action |
| - | -------- | ------ | ----- | ---------------- | -------- | ------ | ------ |
| 1 | utils.py | `utils.py` | 800 | string ops + date ops + I/O | Medium | High | Split by domain |

### Mutable Global State

| # | Location | Symbol | Mutated By | Severity | Impact | Action |
| - | -------- | ------ | ---------- | -------- | ------ | ------ |
| 1 | client.go:9 | `var defaultClient` | `SetClient()` | Medium | Medium | Inject via struct field |

### Anemic Domain Model

| # | Location | Entity | Misplaced Transition | Owning Service | Evidence | Severity | Impact | Action |
| - | -------- | ------ | -------------------- | -------------- | -------- | -------- | ------ | ------ |
| 1 | order.py:12 | `Order` | ship / cancel | `OrderService` | `order.status = "shipped"` at svc.py:88 | Medium | Medium | Move to `order.ship()` |

### Class Abuse

| # | Location | Class | Methods | State | Severity | Impact | Action |
| - | -------- | ----- | ------- | ----- | -------- | ------ | ------ |
| 1 | user.ts:5 | `UserService` | 1 public | none | Low | Low | Replace with exported function |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).
```
