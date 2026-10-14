# Simplicity Hunter — TypeScript reference

## Generated-code eligibility

**Marker:** no TypeScript-wide marker is defined; when a project documents one, apply it. Scan globs:
`*.generated.*` / `__generated__/**` / `*.g.ts` / `generated/**`. **Vendored:** `node_modules/`, `dist/`.

## Reinvented Primitives

**Version sources:** `package.json` (TypeScript / runtime engines) and `tsconfig` `compilerOptions.lib` /
`compilerOptions.target`.

| Primitive | Toolchain gate |
| --------- | -------------- |
| `Object.groupBy` | Compatible **runtime** *or* a project-provided polyfill (compiler declarations alone do not make the method executable); **and** TypeScript **5.4+ with `esnext`**, *or* TypeScript **5.7+ with `es2024`** (5.4 shipped the declarations; stable `--lib es2024` arrived in 5.7) |
| Hand-rolled `uniq` / `chunk` / deep-equal | Already-present dependency or language/runtime primitive with exact semantic parity |
| Manual `Promise` wrappers around already-promisified APIs | Existing promisified surface |
| Ad-hoc date arithmetic | Date library already present as a dependency |

Exact semantic parity includes designed-in differences (e.g. `Object.groupBy` returns a null-prototype object and
coerces non-symbol keys).

## Dead-code liveness channels

Beyond the shared channels (SKILL.md Terms): `package.json` `exports` / `bin`.

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

# 2. Generation-named symbols and paths
rg -l --type ts 'Legacy|Deprecated|V1|V2' --glob '!**/node_modules/**' --glob '!**/dist/**' .
find . -type d \( -name 'v[0-9]*' -o -name legacy -o -name old -o -name new \) \
  -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/.git/*'

# 3. Deprecation markers
rg -n --type ts '@deprecated' --glob '!**/node_modules/**' --glob '!**/dist/**' .
```

## Phase 2 — complexity scans

Restore the eligible list first: `TS_FILES=$(cat <run>/typescript.txt); [ -n "$TS_FILES" ] || exit 1`.

```bash
# Dependencies, build output, generated-code approximations.
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/**'

# Deep nesting (4+ indentation levels, 2-space indent)
rg -H '^\s{8,}\S' --type ts $EXCLUDE -- $TS_FILES

# Boolean parameters
rg -H --pcre2 '\w+\s*[?:]?\s*:\s*boolean' --type ts $EXCLUDE -- $TS_FILES

# Functions with many parameters (declarations, arrow functions, methods)
rg -H --pcre2 'function\s+\w+\s*\([^)]{80,}\)' --type ts $EXCLUDE -- $TS_FILES
rg -H --pcre2 '(?:const|let)\s+\w+\s*=\s*(?:async\s+)?\([^)]{80,}\)\s*(?:=>|:)' --type ts $EXCLUDE -- $TS_FILES
rg -H --pcre2 '^\s+\w+\s*\([^)]{80,}\)\s*[:{]' --type ts $EXCLUDE -- $TS_FILES

# Nested ternaries (skips ?. ?? and optional members `a?:`)
rg -H --pcre2 '(?<!\?)\?(?![.?:])[^;,]*(?<!\?)\?(?![.?:])[^;,]*:' --type ts $EXCLUDE -- $TS_FILES

# Callback pyramids and long .then() chains
rg -H --pcre2 '\.then\([^)]*\)\s*\.then\([^)]*\)\s*\.then' --type ts $EXCLUDE -- $TS_FILES
```

## Phase 3 — Duplication list and exclude

Run in the same call as the Phase 2 `EXCLUDE` line (shell state does not persist between calls).

```bash
DUP_EXCLUDE="$EXCLUDE --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**"
# Seeds: codebase mode ($TS_FILES is .) enumerates; diff and path mode filter the eligible list.
if [ "$TS_FILES" = . ]; then DUP_FILES=$(rg --files --type ts $DUP_EXCLUDE .)
else DUP_FILES=$(printf '%s\n' $TS_FILES | grep -Ev '\.(test|spec|e2e)\.[^/]*$|(^|/)__tests__/'); fi
```
