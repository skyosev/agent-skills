# Simplicity Hunter — TypeScript reference

Language-specific rules for TypeScript.

## Generated-code eligibility

A file is generated (ineligible for reporting) only when identified by an authoritative in-file marker — **never** by
filename guessing. No TypeScript-wide generated-code marker is defined here; when a project documents one, apply it.
Scan globs such as `*.generated.*` / `__generated__/**` / `*.g.ts` / `generated/**` are approximations for scanning
convenience; eligibility uses the marker rule when one exists.

Vendored trees (`node_modules/`, `dist/`), lockfiles, and Markdown-only inputs are also ineligible.

## Reinvented Primitives

**Version sources:** `package.json` (TypeScript / runtime engines) and `tsconfig` `compilerOptions.lib` /
`compilerOptions.target`.

| Primitive | Toolchain gate |
| --------- | -------------- |
| `Object.groupBy` | Compatible **runtime** *or* a project-provided polyfill (compiler declarations alone do not make the method executable); **and** TypeScript **5.4+ with `esnext`**, *or* TypeScript **5.7+ with `es2024`** (5.4 shipped the declarations; stable `--lib es2024` arrived in 5.7) |
| Hand-rolled `uniq` / `chunk` / deep-equal | Already-present dependency or language/runtime primitive with exact semantic parity |
| Manual `Promise` wrappers around already-promisified APIs | Existing promisified surface |
| Ad-hoc date arithmetic | Date library already present as a dependency |

**Signals:** hand-rolled `groupBy` / `uniq` / `chunk` / deep-equal; manual `Promise` wrappers around already-promisified
APIs; ad-hoc date arithmetic where a date library is already a dependency.

Exact semantic parity includes designed-in differences (e.g. `Object.groupBy` returns a null-prototype object and
coerces non-symbol keys).

## Dead-code liveness channels

Beyond call sites: reflection, DI registration, registries, entrypoint configuration, and `package.json` `exports` /
`bin`. Cite channels relevant to *this* symbol.

## Mixed Concerns — TypeScript note

Responsibility analysis of *classes* — methods spanning concerns, multiple reasons to change — is solid-hunter's SRP
territory; keep this signal at function/module level.

## Complex Control Flow — TypeScript signals

In addition to the shared signals (unflattened async control flow):

- 3+ levels of nested callbacks (Node.js-style `(err, result) => { ... }`)
- `.then().then().then()` chains longer than 3 steps, or nested `.then()` "promise pyramids"
- Mixing callbacks and promises in the same function
- Error handling scattered across multiple `.catch()` blocks where a single `try`/`catch` would do

**Action addendum:** convert callback pyramids and long `.then()` chains to `async`/`await` with `try`/`catch`; use
`Promise.all()` / `Promise.allSettled()` for genuinely parallel work.

## Coexisting Generations — Phase 4

**Nomination signals:** `v1/`/`v2/`, `legacy/`, `old/`, `new/` directories, or `*Legacy`/`*V2`/`*Old`/`*Deprecated`
symbols, where the older path still has importers; `@deprecated` JSDoc on symbols with live import sites; overlapping
dependencies in `package.json` that solve one concern (`axios` + `node-fetch` + `got`, `moment` + `date-fns` +
`dayjs`, `jest` + `vitest`, two state or validation libraries); two or more role abstractions for the same concept, all
still constructed somewhere; environment- or config-selected parallel implementations where both branches are
reachable.

### Phase 4 scans

```bash
# 1. Read package.json; list overlapping-concern dependencies (HTTP, dates, state, validation, test runners).
#    Coexistence alone nominates; it is never a finding by itself.

# 2. Generation-named symbols and paths
rg -l --type ts 'Legacy|Deprecated|V1|V2' --glob '!**/node_modules/**' --glob '!**/dist/**' .
find . -type d \( -name 'v[0-9]*' -o -name legacy -o -name old -o -name new \) \
  -not -path '*/node_modules/*' -not -path './dist/*'

# 3. Deprecation markers
rg -n --type ts '@deprecated' --glob '!**/node_modules/**' --glob '!**/dist/**' .
```

Confirm liveness for every candidate stratum. Capability and project intent decide the survivor; recency nominates
only.

## Evidence path form

Cite findings as `file/path.ts:line` (or `.tsx` / `.mts` / `.cts` as appropriate).

## Phase 2 — complexity scans

Test files are included (complexity in tests is in scope). Duplication excludes them — see Phase 3 exclude below.
Pass an explicit path to every `rg` invocation.

```bash
# Dependencies, build output, generated-code approximations — tests are NOT excluded here (N11).
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/**'

# Deep nesting (4+ indentation levels, 2-space indent)
rg '^\s{8,}\S' --type ts $EXCLUDE -- $SCOPE

# Boolean parameters
rg --pcre2 '\w+\s*[?:]?\s*:\s*boolean' --type ts $EXCLUDE -- $SCOPE

# Functions with many parameters (declarations, arrow functions, methods)
rg --pcre2 'function\s+\w+\s*\([^)]{80,}\)' --type ts $EXCLUDE -- $SCOPE
rg --pcre2 '(?:const|let)\s+\w+\s*=\s*(?:async\s+)?\([^)]{80,}\)\s*(?:=>|:)' --type ts $EXCLUDE -- $SCOPE
rg --pcre2 '^\s+\w+\s*\([^)]{80,}\)\s*[:{]' --type ts $EXCLUDE -- $SCOPE

# Nested ternaries
rg --pcre2 '\?[^:]+\?' --type ts $EXCLUDE -- $SCOPE

# Callback pyramids and long .then() chains
rg --pcre2 '\.then\([^)]*\)\s*\.then\([^)]*\)\s*\.then' --type ts $EXCLUDE -- $SCOPE
```

## Phase 3 — Duplication exclude

```bash
DUP_EXCLUDE="$EXCLUDE --glob '!**/*.test.*' --glob '!**/*.spec.*' --glob '!**/*.e2e.*' --glob '!**/__tests__/**'"
# Run duplication searches with $DUP_EXCLUDE so test-code duplication stays with test-hunter.
```
