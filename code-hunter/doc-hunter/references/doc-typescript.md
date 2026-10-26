# Doc Hunter — TypeScript reference

Contents: Applicability · Generated-code and test-path eligibility · Doc-comment form · Public symbol and Library unit · Detectors · Phase 2 — doc scans · Diff mode — removed symbols · Remedies · Evidence path form

## Applicability

| Category | Applicable | TypeScript note |
| -------- | ---------- | --------------- |
| Unexplained Business Rules | **yes** | Thresholds in comparisons and in `const` declarations; a source comment on the `const` covers its uses |
| Magic Numbers | **yes** | No scan: a configured `no-magic-numbers` rule and reading nominate |
| Non-Obvious Algorithms | **yes** | `RegExp` constructors and regex literals; bit operations are found by reading |
| Unexplained Workarounds | **yes** | `setTimeout`, `requestAnimationFrame`, `queueMicrotask`; `navigator.userAgent` and `process.platform` branches |
| Undocumented Contracts | **yes** | A `throw` that callers catch (`@throws`); `process.env` reads outside entry files. `undefined` returned for an error is error-hunter's |
| Misleading Comments and Names | **yes** | `@param` names the signature lacks; `{@link}` and `@see` to removed symbols; mapping objects as mapping sites; expiry against the lockfile |
| Missing Public Docs | **yes** | Gate: a Library unit (the exports of its entry source files), or a configured `jsdoc/require-jsdoc` or TypeDoc `notDocumented` |

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when identified by an authoritative in-file marker where one exists
(`// @generated`, `// Code generated`, GraphQL / protobuf / OpenAPI / Prisma client banners). Scan globs such as
`*.generated.*`, `__generated__/`, `*.g.ts`, `generated/` are approximations for scanning convenience.

Dependency and build trees (`node_modules/`, `dist/`, `build/`, `.next/`, `out/`), lockfiles, and Markdown-only inputs
are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*.test.*`, `*.spec.*`, `*.e2e.*`, `__tests__/`.

## Doc-comment form

- **Attachment:** a doc comment is a `/** … */` block immediately before a declaration. A `//` comment is never a doc
  comment.
- **Tags:** TSDoc `@param name -`, `@returns`, `@throws`, `{@link Name}`; JSDoc `@param {Type} name`. A `@param`
  name the signature does not have is a Misleading Comments and Names signal.
- **References:** `{@link Name}` and `@see Name` name a symbol; each resolves to a declaration.

## Public symbol and Library unit

A public symbol is exported (`export`). For the Missing Public Docs gate it must also be exported from an entry source
file of a Library unit.

Library unit: SKILL.md Terms. The `outDir` mapping, for example: `dist/index.js` → `src/index.ts` for
`outDir: dist`, `rootDir: src`.

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
rg -l --glob '**/package.json' --glob '!**/node_modules/**' '"name"' -- .                 # workspace packages
rg -H -n --glob '**/package.json' --glob '!**/node_modules/**' '"private"\s*:\s*true' -- .   # closed packages
```

Read each open package's `exports`, `main`, and `types`, and its tsconfig's `outDir` and `rootDir`.

## Detectors

**ESLint** runs when the project configures it (`eslint.config.*`, `.eslintrc.*`, an `eslintConfig` key in
`package.json`), from `node_modules/.bin/eslint` only; it is `skipped — configured, not installed` when that file is
absent. Never use `npx`, which can download. Checked on eslint-plugin-jsdoc 65.4.2.

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
TS_FILES=$(cat <run>/typescript.txt); [ -n "$TS_FILES" ] || exit 1  # STOP: empty restore
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/build/** --glob !**/.next/** --glob !**/out/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'
[ "$TS_FILES" = . ] && TS_FILES=$(rg --files --type ts $EXCLUDE -- .)   # codebase mode: enumerate
node_modules/.bin/eslint --format json $TS_FILES | node -e 'const keep=/^(jsdoc\/(check-param-names|require-jsdoc|require-param|require-returns|require-throws)|(@typescript-eslint\/)?no-magic-numbers)$/;for(const f of JSON.parse(require("fs").readFileSync(0,"utf8")))for(const m of f.messages)if(m.fatal||keep.test(m.ruleId??""))console.log(`${f.filePath}:${m.line}: ${m.ruleId??"fatal"}: ${m.message}`)'
```

The full rule set runs, type-aware rules included: ESLint has no flag that runs only some configured rules, and its
config differs per file, so no single `--print-config` shows that no kept rule is on. Without `--fix` and `--cache`,
ESLint writes nothing. The JSON result of each file with a message carries the file's whole source, so the output is
read only through the filter. The filter keeps `fatal` lines (a file ESLint could not parse; its silence there is not
coverage) and the messages of these rules:

- `jsdoc/check-param-names` reports stale `@param` names ("Expected @param names to be "a, b". Got "oldName, b"").
- `jsdoc/require-jsdoc` covers only `FunctionDeclaration` by default: an exported arrow function and a class method
  go unreported. Its silence is not coverage.
- `jsdoc/require-param`, `jsdoc/require-returns`, `jsdoc/require-throws`.
- `@typescript-eslint/no-magic-numbers` and core `no-magic-numbers`.

`jsdoc/informative-docs` reports docs that only repeat the name. That is slop-hunter's Verbose Documentation; drop it
here.

**TypeDoc** runs when the project configures it (`typedoc.json`, `typedoc.config.*`, a `typedocOptions` key in
tsconfig), with the project's `validation` options. Checked on TypeDoc 0.28.20. It runs on the project's entry points,
not on a file list, in every mode; keep the warnings whose file is in `$TS_FILES`.

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
node_modules/.bin/typedoc --emit none
```

- `--emit none` writes no output.
- `invalidLink` reports `{@link}` targets that no longer resolve.
- `notDocumented` reports undocumented exports.

**What each code nominates.** A code is filed by this list, not by the category it sounds like:

- Missing Public Docs, through the gate: `jsdoc/require-jsdoc`, TypeDoc `notDocumented`.
- Misleading Comments and Names: `jsdoc/check-param-names`, TypeDoc `invalidLink`.
- Undocumented Contracts, only when the missing text would state something the signature does not:
  `jsdoc/require-param`, `jsdoc/require-returns`, `jsdoc/require-throws`. A missing `@returns` that restates the type
  is the tag slop-hunter deletes.
- Magic Numbers: `@typescript-eslint/no-magic-numbers`, `no-magic-numbers`.

## Phase 2 — doc scans

`$TS_FILES` is this language's eligible list, restored from `<run>/typescript.txt` (SKILL.md Phase 1 step 4).

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
TS_FILES=$(cat <run>/typescript.txt); [ -n "$TS_FILES" ] || exit 1  # STOP: empty restore
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/build/** --glob !**/.next/** --glob !**/out/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

# Unexplained Workarounds: delays, platform and runtime branches, comments that call the code a hack or a workaround
rg -H -n 'setTimeout|setInterval|requestAnimationFrame|queueMicrotask|\b(delay|sleep)\(' --type ts $EXCLUDE -- $TS_FILES
rg -H -n 'navigator\.(userAgent|platform|vendor)|process\.(platform|versions?)\b' --type ts $EXCLUDE -- $TS_FILES
rg -H -n '(//|/?\*).*(?i)\b(hack|work ?around)\b' --type ts $EXCLUDE -- $TS_FILES

# Non-Obvious Algorithms: regular expressions
rg -H -n 'new RegExp\(|\.(match|matchAll|replace|replaceAll|split|search)\(\s*/' --type ts $EXCLUDE -- $TS_FILES

# Undocumented Contracts: hidden inputs
rg -H -n 'process\.env\.' --type ts $EXCLUDE -- $TS_FILES

# Misleading Comments and Names: {@link} and @see references (resolve each name); expiry conditions
rg -H -n '\{@link\s+(\w+)|@see\s+(\w+)' --type ts $EXCLUDE -- $TS_FILES
rg -H -n '(//|/?\*).*(?i)\b(until|after|once|remove|drop|when)\b.*(\bv?\d+\.\d+(\.\d+)?\b|\b\d{4}-\d{2}(-\d{2})?\b)' --type ts $EXCLUDE -- $TS_FILES
```

**Expiry.** A comment needs a condition word and a version or a date. A version is compared with the lockfile
(`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`); a version the lockfile does not pin is unresolved:
no finding. A date is compared with today's date.

**Blind spots:**

- No magic-number or bit-operation scan. `|`, `>>`, and `<` collide with union types and generics, and a digit
  pattern either misses common constants or matches every file. Magic numbers come from a configured
  `no-magic-numbers` rule and from reading; bit manipulation from reading.
- No scan nominates a defect comment without the words "hack" or "workaround", a business rule, a comparator, a
  third-party call order, a side effect, or a name that the body contradicts. Reading finds them.

## Diff mode — removed symbols

Declaration pattern, applied to the removed lines of `git diff -U0 "$MB"` (`references/diff-mode.md`) and, without the
leading `-`, to each deleted `.ts` path at the merge base:
`^-.*\b(function|class|interface|type|enum|const|let)\s+(\w+)`. A method's identity is `Class.method`.

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
MB=$(cat <run>/mb); [ -n "$MB" ] || exit 1                          # STOP: empty restore
TS_FILES=$(cat <run>/typescript.txt 2>/dev/null)                    # none in a deletions-only run
[ -z "$TS_FILES" ] || git diff -U0 "$MB" -- $TS_FILES | rg '^\+\+\+ |^-.*\b(function|class|interface|type|enum|const|let)\s+(\w+)'
git show "$MB:<deleted path>" | rg -n '\b(function|class|interface|type|enum|const|let)\s+(\w+)'   # once per deleted path

# References to one removed name in the repository's TypeScript comments: {@link}, @see, a backtick span. NAME is
# the name, or Class\.method for a method.
rg -H -n --type ts "(//|/?\*).*(\{@link\s+$NAME\b|@see\s+$NAME\b|\`$NAME\`)" -- .
# A bare word counts only when the name has an inner capital, an underscore, or a digit
rg -H -n --type ts "(//|/?\*).*\b$NAME\b" -- .
```

## Remedies

- **Constants:** a named `const` (`const RETRY_BACKOFF = 1.5`), an object of constants with `as const`; a unit or a
  range in the name (`ratePct`, `distanceNm`).
- **Doc comments:** TSDoc tags (`@param name -`, `@returns`, `@throws`, `{@link Name}`), or JSDoc where the project
  uses it.

## Evidence path form

Location is `file:line`. A symbol is `module#export` (`src/rates#getRate`), or `module#Class.method`.
