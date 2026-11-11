# Doc Hunter — TypeScript reference

Contents: Applicability · Generated-code and test-path eligibility · Doc-comment form · Public symbol and Library unit · Delegated to tools · Phase 2 — doc scans · Diff mode — removed symbols · Remedies · Evidence path form

## Applicability

| Category | Applicable | TypeScript note |
| -------- | ---------- | --------------- |
| Unexplained Business Rules | **yes** | Thresholds in comparisons and in `const` declarations; a source comment on the `const` covers its uses |
| Non-Obvious Algorithms | **yes** | `RegExp` constructors and regex literals; bit operations are found by reading |
| Unexplained Workarounds | **yes** | `setTimeout`, `requestAnimationFrame`, `queueMicrotask`; `navigator.userAgent` and `process.platform` branches |
| Undocumented Contracts | **yes** | A `throw` that callers catch (`@throws`); `process.env` reads outside entry files. `undefined` returned for an error is exception-hunter's (Swallowed Errors) |
| Misleading Comments and Names | **yes** | `@see` to removed symbols; mapping objects as mapping sites |

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
- **Tags:** TSDoc `@param name -`, `@returns`, `@throws`, `{@link Name}`; JSDoc `@param {Type} name`.
- **References:** `{@link Name}` and `@see Name` name a symbol; each resolves to a declaration.

## Public symbol and Library unit

A public symbol is exported (`export`). A Library unit's public symbols are those exported from its entry source
files.

Library unit: SKILL.md Terms. The `outDir` mapping, for example: `dist/index.js` → `src/index.ts` for
`outDir: dist`, `rootDir: src`.

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
rg -l --glob '**/package.json' --glob '!**/node_modules/**' '"name"' -- .                 # workspace packages
rg -H -n --glob '**/package.json' --glob '!**/node_modules/**' '"private"\s*:\s*true' -- .   # closed packages
```

Read each open package's `exports`, `main`, and `types`, and its tsconfig's `outDir` and `rootDir`.

## Delegated to tools

- ESLint with typescript-eslint, eslint-plugin-jsdoc and eslint-plugin-unicorn, or Biome where a rule is named: a
  numeric literal with no name (`@typescript-eslint/no-magic-numbers` with `ignore: [-1, 0, 1]`, or Biome
  `noMagicNumbers`); a `@param` name the signature lacks (`jsdoc/check-param-names`); a `TODO [>=version]` or
  `TODO [date]` whose condition has passed (`unicorn/expiring-todo-comments`).
- ESLint's `jsdoc/require-jsdoc`, only when a Library unit is in scope (SKILL.md Terms): an exported function, arrow
  function, class, or method with no doc comment (`publicOnly: true`, and `require` on for `FunctionDeclaration`,
  `ArrowFunctionExpression`, `ClassDeclaration`, `MethodDefinition`).
- TypeDoc, only when the project builds its docs with TypeDoc: a `{@link Name}` that does not resolve
  (`validation.invalidLink`).

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

# Misleading Comments and Names: @see references (resolve each name)
rg -H -n '@see\s+(\w+)' --type ts $EXCLUDE -- $TS_FILES
```

**Blind spots:**

- No bit-operation scan: `|`, `>>`, and `<` collide with union types and generics. Bit manipulation is found by
  reading.
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

# References to one removed name in the repository's TypeScript comments: @see, a backtick span. NAME is the name,
# or Class\.method for a method.
rg -H -n --type ts "(//|/?\*).*(@see\s+$NAME\b|\`$NAME\`)" -- .
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
