# SOLID Hunter — report format

Read at Phase 5. Severity and Impact *definitions* live in SKILL.md; this file is the template and the per-category
table schemas.

Omit any category heading with zero findings — no empty tables, no placeholder subsections, no "none found" lines.
Every line of the Scope block below is filled in on every run; it is not a category and this rule does not reach it.

**Column ceiling.** No table carries more than eight columns beyond the `#` index, and Severity and Impact are two of
them. When a category needs more detail, trim an existing column rather than appending.

**No Toolchain lines.** No supported language has a SOLID analyzer a project would configure; the Scope block carries
none.

**Architecture style line.** Always present: `struct-based` / `class-based` / `mixed` / `functional (limited
findings)`. In a functional codebase the struct/class categories fire only where structs, classes and interfaces
exist; Go package-level Responsibility Sprawl fires regardless.

**Policy line.** Present only when repository instructions withdrew a pattern; quotes the instruction and names the
category and sites it withdrew.

**Enumeration line.** Present whenever implementors were found by reading consumers rather than by scan — structural
typing (TypeScript, Python `Protocol`) hides implementors from regex. States what was searched (`implements`,
subclassing, consumers read) and names the gap: implementors outside the searched consumers, external packages
included, are not found. Findings claim the enumerated set only.

**Evidence cells.**

- **Actors** (Responsibility Sprawl) names each actor; **Members per actor** lists the members belonging to each, and
  the Action carries the change scenario that crosses them.
- **Dispatch sites** (Rigid Extension Points) is the project-wide list, not a count, and the **Shared responsibility**
  cell is `yes` or `heterogeneous`. Openness evidence — the commit or the diff hunk that added a variant and touched
  these sites — belongs in the Action cell alongside the remedy.
- **Violation** (Broken Substitution) is one of `throws not-implemented`, `silent no-op`, `narrowed input`,
  `widened errors`, `compensating branch`, and names the promised behavior it breaks and how the abstraction is
  reached.
- **Evidence** (Fat Interfaces) names each affected consumer and the subset it calls first; a stubbing implementor or
  fake follows as support. This cell replaces the old "Avg Used by Consumers" column — an average hides which
  consumer proves the split.
- **Form** (Concrete Dependency Chains) is `self-instantiation` or `global read`, and the Action states what the
  caller cannot control today.

When Broken Substitution and Fat Interfaces both cleared their bars at one site, the reported finding's Evidence cell
names the other reading in one clause.

```md
# SOLID Hunter Audit — {date}

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
- Architecture style: {struct-based / class-based / mixed / functional (limited findings)}
- Composition roots: {list}
- {Enumeration: searched `implements` + explicit subclassing + consumers of {interface}; structural implementors outside those consumers, external packages included, not found}
- {Policy: "{quoted instruction}" — withdraws {category} at {sites}}
- Audit completed: {N} findings

## Findings

### Responsibility Sprawl (SRP)

| # | Location | Unit | Actors | Members per actor | Severity | Impact | Action |
| - | -------- | ---- | ------ | ----------------- | -------- | ------ | ------ |
| 1 | svc/order.py:18 | `OrderService` (class) | orders team; billing; notifications | CRUD: `create`, `update`, `cancel` / invoicing: `render_invoice`, `pdf` / mail: `send_confirmation` | Medium | High | Extract `Invoicer` and `Notifier`; a template change would edit the file every order change touches |

### Rigid Extension Points (OCP)

| # | Location | Discriminant | Dispatch sites | Shared responsibility | Severity | Impact | Action |
| - | -------- | ------------ | -------------- | --------------------- | -------- | ------ | ------ |
| 1 | send/dispatch.ts:24 | `kind: 'email' \| 'sms' \| 'push'` | `send/dispatch.ts:24`, `queue/retry.ts:61`, `report/usage.ts:33`, `admin/preview.ts:12` | yes — every arm picks a provider client | Medium | High | `Record<Kind, Sender>` built once; arms select a value only. Openness: `a1b2c3d` added `'push'` and edited all four sites. Adds one table, removes four per-variant edits |

### Broken Substitution (LSP)

| # | Location | Implementor | Abstraction | Violation | Severity | Impact | Action |
| - | -------- | ----------- | ----------- | --------- | -------- | ------ | ------ |
| 1 | store/readonly.go:41 | `ReadOnlyStore` | `Store` (`Save` documented "persists and returns the assigned ID") | throws not-implemented; registered as `Store` in `cmd/api/main.go:52`, reached by `POST /orders` | High | High | Implement `Reader` only; `Store` stops being claimed. (Fat Interfaces also clears here; Broken Substitution chosen — a consumer holds it as `Store`) |

### Fat Interfaces (ISP)

| # | Location | Interface | Members | Evidence | Severity | Impact | Action |
| - | -------- | --------- | ------- | -------- | -------- | ------ | ------ |
| 1 | store/store.go:12 | `DataStore` | 12 | `ReportService` (svc/report.go:20) calls `Get`, `List`; `ImportJob` (job/import.go:14) calls `Put`, `Delete`; seam live via fx provider `app/module.go:31`; `InMemoryStore` stubs 7 (support) | Medium | Medium | Consumer-defined `Reader` and `Writer`; `DataStore` stays for the admin consumer that uses all 12 |

### Concrete Dependency Chains (DIP)

| # | Location | Unit | Dependency | Form | Severity | Impact | Action |
| - | -------- | ---- | ---------- | ---- | -------- | ------ | ------ |
| 1 | svc/user.py:22 | `UserService` | `SmtpMailer()` in `__init__` (SMTP connection) | self-instantiation | Medium | Medium | Accept `SmtpMailer` as a parameter; the host and timeout are chosen inside today. `tests/test_user.py:9` patches the module to construct the service |
| 2 | svc/sync.go:38 | `Svc` | package-level `var db *sql.DB` read in `Do` | global read | Medium | High | Inject `*sql.DB`; the caller cannot choose the pool. `SetDB` at `db/init.go:14` is smell-hunter's Mutable Global State — cross-referenced, not scored here |

## Recommendations (Priority Order)

Group by Severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low). Each
recommendation names what the change adds as well as what it removes; a remedy whose net benefit cannot be argued is
not recommended, and the finding names the cost instead.
```
