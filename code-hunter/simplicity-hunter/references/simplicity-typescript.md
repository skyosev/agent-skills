# Simplicity Hunter — TypeScript reference

## Generated-code eligibility

**Marker:** no TypeScript-wide marker is defined; when a project documents one, apply it. `@generated` alone is not
one: it is also a JSDoc tag on single symbols. Scan globs:
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

## Dead code — ownership and liveness hooks

**Ownership:** an `export` or a file that nothing imports is in Delegated to tools (knip). Unused parameters are a
recorded gap no hunter audits.

**Liveness hooks** beyond the shared channels (SKILL.md Terms): `package.json` `exports` / `bin`; JSX use
(`<Foo />`); dynamic `import()`, including `lazy(() => import('./Page'))`; file-based routes.

## Coexisting Generations — Phase 4

**Nomination signals:** `legacy/`, `old/`, `new/` directories, or `*Legacy`/`*V2`/`*Old`/`*Deprecated`
symbols, where the older path still has importers; `@deprecated` JSDoc on symbols with live import sites; overlapping
dependencies in `package.json` that solve one concern (`axios` + `node-fetch` + `got`, `moment` + `date-fns` +
`dayjs`, `jest` + `vitest`, two state or validation libraries); two or more role abstractions for the same concept, all
still constructed somewhere; environment- or config-selected parallel implementations where both branches are
reachable.

### Phase 4 scans

```bash
# 1. Read package.json; list overlapping-concern dependencies (HTTP, dates, state, validation, test runners).

# 2. Generation-named symbols and paths
rg -l --type ts --pcre2 'Legacy|Deprecated|(?<![A-Z0-9])V[12]\b' --glob '!**/node_modules/**' --glob '!**/dist/**' .
find . -type d \( -name legacy -o -name old -o -name new \) \
  -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/.git/*'

# 3. Deprecation markers (evidence of intended replacement for a stratum the other scans nominated)
rg -n --type ts '@deprecated' --glob '!**/node_modules/**' --glob '!**/dist/**' .
```

## Delegated to tools

- ESLint with typescript-eslint, or Biome where a rule is named: deep nesting, branchy functions, nested ternaries,
  and nested callbacks (`complexity`, `max-depth`, `no-nested-ternary`, `max-nested-callbacks`, or Biome
  `noExcessiveCognitiveComplexity`, `noNestedTernary`); a guard the type already rules out
  (`@typescript-eslint/no-unnecessary-condition`); a call to a deprecated symbol (`@typescript-eslint/no-deprecated`).
- knip: an export or a file that nothing imports.

## Phase 2 — complexity scans

**Regex scans.** Restore the eligible list first: `TS_FILES=$(cat <run>/typescript.txt); [ -n "$TS_FILES" ] || exit 1`.

```bash
# Dependencies, build output, generated-code approximations.
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/**'

# Boolean parameters
rg -Hn --pcre2 '\w+\s*[?:]?\s*:\s*boolean' --type ts $EXCLUDE -- $TS_FILES

# Functions with long parameter lists (declarations, arrow functions, methods; one-line or split)
rg -Hn -U --pcre2 'function\s+\w+\s*\([^)]{80,}\)' --type ts $EXCLUDE -- $TS_FILES
rg -Hn -U --pcre2 '(?:const|let)\s+\w+\s*=\s*(?:async\s+)?\([^)]{80,}\)\s*(?:=>|:)' --type ts $EXCLUDE -- $TS_FILES
rg -Hn -U --pcre2 '^\s+\w+\s*\([^)]{80,}\)\s*[:{]' --type ts $EXCLUDE -- $TS_FILES
```

## Phase 3 — Duplication list and exclude

Run in the same call as the Phase 2 `EXCLUDE` line (shell state does not persist between calls).

```bash
DUP_EXCLUDE="$EXCLUDE --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**"
# Seeds: codebase mode ($TS_FILES is .) enumerates; diff and path mode filter the eligible list.
if [ "$TS_FILES" = . ]; then DUP_FILES=$(rg --files --type ts $DUP_EXCLUDE .)
else DUP_FILES=$(printf '%s\n' $TS_FILES | grep -Ev '\.(test|spec|e2e)\.[^/]*$|(^|/)__tests__/'); fi

# Declared copies: a copy phrase in a line or block comment, then a camelCase name within 60 characters
# (the phrase ignores case; the name does not)
rg -Hn --pcre2 '(?://|/\*|^\s*\*).*\b(?i:mirrors|mirror of|as in|same as|copy of|in step with|keep in sync with)\b.{0,60}\b[a-z]+[A-Z][A-Za-z]*' --type ts $DUP_EXCLUDE -- $DUP_FILES
```

**Probe runner** (Drifted copies): a TypeScript runner that the project already has, or `node <run>/probe.ts`. Node
strips types by default from 22.18 and 23.6, and with `--experimental-strip-types` from 22.6. Relative imports must
carry `.ts`; `enum`, `namespace` and `.tsx` do not run. Neither form type-checks. Never install a runner.
