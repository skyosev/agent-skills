# Doc Hunter — report format

The report is, in order: `## Scope`; `## Findings` with one `###` section per category that has at least one finding;
`## Recommendations (Priority Order)`. Unbraced Scope lines appear on every run that reaches scanning; a `{braced}`
line appears only when its condition holds. A run that stops early (empty scope, no eligible source) writes the Scope
lines resolved so far and its `Audit completed` line, nothing else. A category with no findings gets no heading,
table, or "none found" line; a thin report is a valid result.

A deletions-only run's Scope holds the lines of Phase 1 steps 1 to 3, `References loaded`, `Deleted in diff`, and
`Audit completed`. Findings and Recommendations follow as on any other run.

**Doc style line.** Per language: `go: godoc`; `python: google (ruff pydocstyle convention)` or `python: numpy
(dominant in nearby docstrings)`; `typescript: TSDoc` or `JSDoc`.

**Detectors line.** One entry per delegated detector the language reference names, in one of the states of SKILL.md
Phase 2.

**Library units line.** Only for units with a Missing Public Docs or Undocumented Contracts candidate:
`{unit} library|closed — {evidence}`. A TypeScript entry that maps to no source file is the evidence of a closed unit:
`packages/sdk closed — exports "./dist/index.js" maps to no source file`.

**Evidence cells.** Each category's Evidence bar in SKILL.md says what a cell holds; this list gives only the form.

- **Location** is `file:line`. A finding for stale references outside the scope anchors at the removal site:
  `file:line (removed: <name>)`, or `<path> (deleted)` for a deleted file.
- **Why-Search** has one entry per step, in step order, under the step's label: `names`, `comment`, `link`,
  `repo docs`, `history` (Magic Numbers: the first three). The history entry is a quoted reason with its hash, or one
  of `history: <n> commits, no reason`, `history: 20 commits, no reason (cap)`, `history: shallow, …`,
  `history: skipped — line not committed`, `history: errored — <message>`, `history: unavailable`.
- **Open Question** is `answered: <hash>` when only history answered it.
- **Missing** (Unexplained Workarounds) is `cause` or `removal condition`.
- **Contract Clause** for kind `enforceable` starts with `enforceable:` and quotes the comment.
- **Symbols** (Missing Public Docs) is `<n> symbols: <names>`. **Gate** is `library: <evidence>` or
  `rule: <linter> <rule>`.

When the within-skill routing chose one category over another at a site, the reported finding's evidence names the
other reading in one clause.

```md
# Doc Hunter Audit — {date}

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
- Doc style: {per language — `go: godoc` / `python: google (ruff pydocstyle convention)` / `typescript: TSDoc`}
- Detectors: {per detector — `golangci-lint (godoclint, revive): ran — golangci-lint run --enable-only=godoclint,revive …` / `ruff: ran — ruff check --no-fix --output-format=concise …` / `ESLint: skipped — configured, not installed` / `TypeDoc: skipped — not configured`}
- {Library units: {unit} library|closed — {evidence}}
- History: {full / shallow / unavailable}
- {not read: {n} files — context budget}
- Audit completed: {N} findings

## Findings

### Unexplained Business Rules

| # | Location | Code | Open Question | Why-Search | Severity | Impact | Action |
| - | -------- | ---- | ------------- | ---------- | -------- | ------ | ------ |
| 1 | laytime/weather.go:88 | `if hours > 6` | Which clause or policy sets 6 h? | names: none; comment: none; link: none; repo docs: none; history: 2 commits ("fix weather"), no reason | Medium | Medium | State the source of the 6-hour threshold; none found in code, docs, or history |
| 2 | laytime/notice.go:31 | `if hours > 6 // contractual minimum` | answered: 3f2a1c | names: none; comment: names no clause; link: none; repo docs: none; history: 3f2a1c "SUPPLYTIME cl. 12: 6 h minimum" | Medium | Medium | `const minWeatherHours = 6 // SUPPLYTIME cl. 12 (from 3f2a1c)` |

### Magic Numbers

| # | Location | Value | Role | Why-Search | Severity | Impact | Action |
| - | -------- | ----- | ---- | ---------- | -------- | ------ | ------ |
| 1 | client/retry.go:22 | `1.5` in `retries * 1.5` | backoff multiplier | names: none; comment: none; link: none | Low | Low | `const retryBackoff = 1.5`; add its origin if it was tuned or copied |

### Non-Obvious Algorithms

| # | Location | Code | Technique | Why-Search | Severity | Impact | Action |
| - | -------- | ---- | --------- | ---------- | -------- | ------ | ------ |
| 1 | geo/distance.py:14 | `2 * R * asin(sqrt(a))` | haversine | names: `dist`; comment: none; link: none; repo docs: none; history: 1 commit ("add distance"), no reason | Medium | Medium | Rename `dist` to `haversine_nm`; its literals are part of this row |
| 2 | wire/pack.go:40 | `v<<7 \| b&0x7f` loop | unidentified | names: `pack`; comment: none; link: none; repo docs: none; history: 20 commits, no reason (cap) | Low | Low | Which encoding is this? Name it in the function once the author confirms |

### Unexplained Workarounds

| # | Location | Code | Kind | Missing | Why-Search | Severity | Impact | Action |
| - | -------- | ---- | ---- | ------- | ---------- | -------- | ------ | ------ |
| 1 | feed/sync.go:57 | `time.Sleep(200 * time.Millisecond)` before `client.Read` | timing | cause | names: none; comment: none; link: none; repo docs: none; history: skipped — line not committed | Medium | Medium | State why the read waits 200 ms; ask the author, who holds the uncommitted edit |
| 2 | ui/keys.ts:12 | `// XXX: Safari drops the first keydown after focus` over the user-agent branch | defect | removal condition | names: none; comment: names the defect, no removal condition; link: none; repo docs: none; history: 4 commits, no reason | Low | Medium | State when the branch can go ("Remove when Safari fixes the dropped keydown") |

### Undocumented Contracts

| # | Location | Symbol | Contract Clause | Established At | Caller Evidence | Severity | Impact | Action |
| - | -------- | ------ | --------------- | -------------- | --------------- | -------- | ------ | ------ |
| 1 | order/apply.go:18 | `order.Apply` | mutates `order.Items` (removes rejected lines) | order/apply.go:31 | billing/invoice.go:52 reuses the order after `Apply` and bills the removed lines | High | High | Doc comment: "Apply removes rejected lines from o.Items." |
| 2 | report/batch.go:9 | `report.Batch` | enforceable: "// ids is never empty" | report/batch.go:8 | report/run.go:40 passes a filtered list that can be empty | Low | Low | Reject an empty list in `Batch`; keep the comment until the check lands |

### Misleading Comments and Names

| # | Location | Kind | Claim | Contradicted At | Severity | Impact | Action |
| - | -------- | ---- | ----- | --------------- | -------- | ------ | ------ |
| 1 | store/user.go:40 | false | "returns ErrNotFound" | store/user.go:47 `return nil, nil`; api/user.go:22 checks `errors.Is(err, ErrNotFound)` | High | High | Code or text is wrong; the author decides. api/user.go:22 relies on the text |
| 2 | rates/get.go:12 | name | `GetRate` | rates/get.go:30 inserts a row when none exists | Medium | Medium | Rename to `GetOrCreateRate` at all call sites |
| 3 | db/pq.go:88 | expired | "workaround for lib/pq#1234, remove after v1.10.10" | go.mod:14 `github.com/lib/pq v1.11.0` | Low | Low | Confirm the defect is gone, then remove the workaround and its comment |
| 4 | handlers/legacy.go:30 (removed: handleLegacy) | stale | `[handleLegacy]` | router.go:12 | Low | Low | Update router.go:12 to name the replacement handler |

### Missing Public Docs

| # | Location | Unit | Symbols | Gate | Severity | Impact | Action |
| - | -------- | ---- | ------- | ---- | -------- | ------ | ------ |
| 1 | parse/parse.go:1 | `example.com/lib/parse` | 12 symbols: Parse, Format, Scan, Token, Pos, Error, Mode, Option, Reader, Writer, Node, Visit | library: module with no `main` package, dotted module path, not under `internal/` | Low | Medium | Add doc comments, the package comment first |

## Recommendations (Priority Order)

Group by Severity (High → Medium → Low). Within each group, order by Impact (High → Medium → Low). Each
recommendation names the text to add, correct, or delete, or the name to change, and quotes only what the Why-search
found.
```
