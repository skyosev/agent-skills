# Type Hunter — TypeScript reference

Contents: Applicability of the universal categories · Generated-code and test-path eligibility · Per-category TypeScript content · TypeScript-only category · Phase 2 — type scans · Phase 4 — TypeScript-specific evaluation

## Applicability of the universal categories

| Category | Applicable | Reason |
| -------- | ---------- | ------ |
| Duplicated Type Declarations | **yes** | All three source kinds: sibling type (`Pick` / `Omit` / `Partial` / `Readonly` / intersection), runtime value (`(typeof arr)[number]`, `(typeof obj)[keyof typeof obj]`), schema (the installed library's inference type in the right role) |
| Generics That Never Vary | **yes** | Type arguments are inferred at call sites; explicit `<User>` is the exception, so the instantiation set is read from consumers |
| Loose Type Parameter Constraints | **yes** | `<T>` / `<T extends unknown>` used as an object; plus the missing `const` type parameter form (TS 5.0+) |
| Over-Powered Type Constructs | **yes** | Conditional, recursive, `as`-remapped mapped, and template-literal metaprogramming beyond any existing use |
| Enum Construct Mechanics | **yes** | `enum` whose members are only compared or serialized; numeric non-flag serialized; `===` to raw literals; single member |
| Alias vs Named Type Mechanics | **n/a** | Structural typing makes `type UserId = string` identical to `string` and two same-shaped aliases mutually assignable; smell-typescript's brand-or-withdraw rule owns the alias question as Primitive Obsession's remedy |

**TypeScript-only category:** Reinvented Utility Types, defined below.

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when identified by an authoritative in-file marker where one exists
(`// @generated`, `// Code generated`, GraphQL / protobuf / OpenAPI / Prisma client banners). Scan globs such as
`*.generated.*`, `__generated__/`, `*.g.ts`, `generated/` are approximations for scanning convenience.

Dependency and build trees (`node_modules/`, `dist/`, `build/`, `.next/`, `out/`), lockfiles, and Markdown-only inputs
are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*.test.*`, `*.spec.*`, `*.e2e.*`, `__tests__/`.

## Per-category TypeScript content

### Duplicated Type Declarations — TypeScript consolidation paths

- **Sibling type.** A hand-listed subset → `Pick<User, 'id' | 'name'>`; a hand-listed complement → `Omit`; every
  field optional by hand → `Partial`; every field `readonly` by hand → `Readonly`; a superset → `User & { … }` or
  `interface Admin extends User`. Every member mapped; the Overlap is `mapped/total`.
- **Runtime value.** A hand-written union beside an array or object of the same values → `as const` on the value
  (the Action adds it where missing) and `(typeof roles)[number]` or `(typeof Status)[keyof typeof Status]`.
  `satisfies` (TS 4.9+) appears only as part of that Action, to keep the value checked against a wider type while preserving
  literals. `as const` on a value with **no** parallel declared type is invariant-hunter's adoption finding, not
  duplication.
- **Schema.** A manual interface beside a schema of the same shape → the installed library's inference type **in the
  right role**: Zod `z.infer` / `z.output` for decoded output, `z.input` where the schema transforms and the interface
  types the accepted input; io-ts `t.TypeOf` / `t.OutputOf`; TypeBox `Static<typeof T>`; Valibot `InferOutput` /
  `InferInput`; ArkType `typeof T.infer`; or the equivalent in whatever library the project already has — only an
  installed library. A transforming schema has an input type and an output type, and its serialized form may differ
  from both. The Evidence names whether the copy is accepted input, decoded output, or serialized data;
  a manual type for the *serialized* form of a transforming schema may have no role-matching inference type → drop.
- **Parallel enums or unions for one value set** → delete-and-use; parallel `enum` and union → also Enum Construct
  Mechanics at the `enum`, cross-referenced, one finding per site by within-skill precedence (the duplication is
  reported; the Evidence names the enum reading).

### Generics That Never Vary — TypeScript forms

`class Store<T>` constructed only as `new Store<User>()` or `new Store(users)`; `function fetchAll<T>()` whose one call
site passes `<User>`; `interface Envelope<T> { payload: T }` where every use is `Envelope<Event>`; `T` used in one
property only. Instantiations are read from explicit type arguments, inferred call sites, `extends` / `implements`
clauses, and annotations, project-wide. Closed and open units follow the TypeScript rows of **Closed consumer set**
in SKILL.md Terms.

### Loose Type Parameter Constraints — TypeScript forms

- `<T>` / `<T extends unknown>` / `<T extends any>` whose body indexes (`(o as any)[k]`), reads properties, spreads as
  an object, or calls methods → `T extends Record<string, unknown>`, `T extends { id: string }`, `T extends object`,
  whichever every instantiation satisfies and the body needs. The `as any` inside the body that the constraint removes
  is cited here.
- `<T extends object>` where the body reads a named property → the property in the constraint.
- **The `const` form (TS 5.0+).** `function keys<T extends readonly string[]>(xs: T)` called as `keys(['a', 'b'])`
  where a downstream consumer wants `'a' | 'b'` and re-narrows with `as` or a manual union: `T` infers `string[]`, the
  literals are lost. Action: `<const T extends readonly string[]>`. Evidence: the parameter type is an array or object
  literal type, and the re-narrowing consumer is named. A scalar `T extends string` already preserves the literal → no
  finding. Below 5.0 the Action is a `readonly ['a', 'b']` parameter type or `as const` at the call site.

### Over-Powered Type Constructs — TypeScript forms

- **Conditional types** nested where a union or an overload-free signature types every use
- **Recursive types** (`DeepMerge`, `DeepReadonly`) where every instantiation is flat → `A & B`, `Readonly<T>` — only
  when no instantiation has a key present in both with different types (the intersection yields `never` there) or a
  nested object the recursion handles
- **Mapped types with `as` key remapping** where `Pick` / `Omit` / `Record` types every use
- **Template-literal metaprogramming** (type-level string splitting, case conversion) where a runtime function with a
  typed return, or a plain union, types every use; a template literal *missing* for a structured string is
  smell-hunter's

### Enum Construct Mechanics — TypeScript forms

- **`enum` whose members are only compared or serialized** — no reverse mapping used, no bitwise combination, no
  non-TS consumer named. The paying consumers are the comparison and serialization sites; value imports of the enum
  across modules that a type-only union would erase are supporting evidence. Action: `type Status = 'active' |
  'inactive'`, or `const Status = { … } as const` with the union derived, when runtime access to the set is wanted.
  The Action names two things where they apply: the **serialization risk** where the value crosses a boundary (a
  numeric enum serializes as numbers; a string enum as its strings — a union of the same strings serializes
  identically), and **`erasableSyntaxOnly`** (TS 5.8) or Node's type stripping where the project sets or targets them,
  which reject `enum` and `const enum` outright and make the union the only compiling form.
- **Numeric `enum` for unordered, non-flag values that is serialized** — the wire carries meaningless integers.
- **`enum` members compared to raw literals with `===`** (`if (s === 'active')` beside `enum Status`) — the enum
  defeats itself; the comparison site pays.
- **Single-member `enum`** — a constant.
- **Not findings:** reverse mapping in use (`Status[0]`), bitwise flags (`Perm.Read | Perm.Write`), a non-TS consumer
  named in the code or its serialization; `const enum` as such — its problems (`isolatedModules`, ambient declarations,
  `erasableSyntaxOnly`) are build configuration, named in the Action above as context, not a defect. `const enum`
  whose value is logged → the compiler inlines the value and logging works; no finding.

## TypeScript-only category

### Reinvented Utility Types

A hand-rolled type equal to a built-in utility.

**Forms:** `{ [K in keyof T]?: T[K] }` → `Partial<T>`; `{ readonly [K in keyof T]: T[K] }` → `Readonly<T>`;
`{ [K in keyof T]-?: T[K] }` → `Required<T>`; `T extends U ? never : T` (distributive) → `Exclude<T, U>`;
`T extends U ? T : never` → `Extract<T, U>`; a hand-rolled `Awaited`, `Parameters`, `ConstructorParameters`,
`InstanceType`, `Record`. Not parity by default: `T extends null | undefined ? never : T` is `NonNullable<T>` only
below TS 4.8 (since 4.8 the built-in is `T & {}`, which differs on an unresolved generic `T`); a hand-rolled
`ReturnType` without the built-in's `T extends (...args: any) => any` constraint, or with a `never` fallback where the
built-in has `any`, is not `ReturnType<T>`. Gate 2 decides both on every use.

**Gates:**

1. **Version.** The project's resolved TypeScript version (lockfile) ships the built-in — `Awaited` 4.5, `Omit` 3.5,
   the rest 2.8 or earlier.
2. **Exact semantic parity**, including homomorphic modifier preservation: `Partial` / `Readonly` / `Required` /
   `Pick` are homomorphic and preserve `readonly` and `?` from `T`; a hand-rolled form that strips or adds modifiers
   differently is not equal. `Exclude` / `Extract` / `NonNullable` are distributive over unions; a non-distributive
   hand-rolled variant (`[T] extends [U] ? …`) is not equal. `DeepPartial` is not `Partial`; a `Pick` that errors on
   missing keys is `Pick`'s own behaviour, but a lenient one that accepts any key is not.
3. **Net concept reduction.** Replacing removes a name; if the hand-rolled type is the project's documented
   vocabulary re-exported everywhere and the built-in would be aliased back to the same name, the reduction is nil →
   no finding.

**Action:** replace with the built-in.

**Severity:** Low.

**Not findings:** a utility with different semantics (above); a hand-rolled `Awaited` in a project pinned below 4.5.

**Ownership:** simplicity-typescript's Reinvented Primitives list is runtime code; utility types are here.

## Phase 2 — type scans

`$TS_FILES` is this language's eligible list, restored from `<run>/typescript.txt` (SKILL.md Phase 1 step 4).

Every scan takes the eligible TypeScript list. A bare `<\w+` scan is deliberately omitted (it matches JSX,
comparisons, and every generic use).

```bash
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/build/** --glob !**/.next/** --glob !**/out/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

# Duplicated Type Declarations: declaration census (then compare member sets by concept, project-wide)
rg -H -n --pcre2 '^\s*(export\s+)?(interface|type)\s+\w+' --type ts $EXCLUDE -- $TS_FILES

# Duplicated Type Declarations: runtime values that may be a union's source, and schemas
rg -H -n 'as\s+const\b' --type ts $EXCLUDE -- $TS_FILES
rg -H -n --pcre2 '\b(z\.object|z\.enum|t\.type|t\.union|Type\.Object|v\.object|type\(\{)' --type ts $EXCLUDE -- $TS_FILES
rg -H -n --pcre2 '\b(z\.(infer|input|output)|t\.(TypeOf|OutputOf)|Static<|Infer(Output|Input)?<)' --type ts $EXCLUDE -- $TS_FILES

# Generics That Never Vary / Loose Type Parameter Constraints: declared type parameter lists
rg -H -n --pcre2 '\b(class|interface|type|function)\s+\w+\s*<|^\s*(export\s+)?(const|let)\s+\w+\s*=\s*(async\s*)?<|^\s*((public|private|protected|static|async|readonly)\s+)*\w+\s*<[^>]*>\s*\([^)]*\)\s*(:[^={]+)?\{' --type ts $EXCLUDE -- $TS_FILES
rg -H -n --pcre2 '<\s*(const\s+)?[A-Z]\w*\s+extends\s+(any|unknown)\b' --type ts $EXCLUDE -- $TS_FILES

# Loose Type Parameter Constraints: bridges inside generic bodies (then confirm the enclosing function is generic)
rg -H -n --pcre2 'as\s+any\)?\s*\[' --type ts $EXCLUDE -- $TS_FILES

# Over-Powered Type Constructs: conditional, mapped-with-remap, recursive, template-literal types
rg -H -n --pcre2 'extends\s+[^?]+\?\s' --type ts $EXCLUDE -- $TS_FILES
rg -H -n --pcre2 '\[\s*\w+\s+in\s+keyof\s+\w+\s+as\s' --type ts $EXCLUDE -- $TS_FILES
rg -H -n --pcre2 '^\s*(export\s+)?type\s+\w+\s*(<[^>]*>)?\s*=\s*`' --type ts $EXCLUDE -- $TS_FILES

# Reinvented Utility Types: mapped types over keyof (then compare with the built-in's definition)
rg -H -n --pcre2 '\[\s*\w+\s+in\s+keyof\s+\w+\s*\]' --type ts $EXCLUDE -- $TS_FILES
rg -H -n --pcre2 'infer\s+\w+' --type ts $EXCLUDE -- $TS_FILES

# Enum Construct Mechanics: enum declarations, and comparisons to raw literals near them (read the consumers)
rg -H -n --pcre2 '^\s*(export\s+)?(declare\s+)?(const\s+)?enum\s+\w+' --type ts $EXCLUDE -- $TS_FILES
```

**Version gates:** the resolved `typescript` version from the lockfile (`package-lock.json`, `pnpm-lock.yaml`,
`yarn.lock`, `bun.lock`), not `package.json`'s range; `erasableSyntaxOnly` and `isolatedModules` from `tsconfig.json` (and any `extends` chain).

## Phase 4 — TypeScript-specific evaluation

For each pair of declarations nominated as duplicates:

- Is either a mirror of a Prisma / OpenAPI / GraphQL / ORM / SDK type, with or without `toDomain()`? → not this
  category (SKILL.md Terms, Cross-layer mirror); stop.
- Name the concept, map every member. Source kind: sibling → the utility type; runtime value → `as const` +
  indexed access; schema → the inference type in the role the copy plays (input, output, serialized — none
  matching → drop).
- Both copies live and already diverged, both consumed → name the divergence in Evidence.
- An `as const` value with no parallel declared type → invariant-hunter; not here.

For each type parameter:

- Enumerate instantiations — explicit arguments, inferred call sites, `extends` / `implements`, annotations — tests
  marked. One production type, set closed → Generics That Never Vary; the Action names the test fake's replacement.
  Reachable from `exports` / `main` without `private: true` → withdraw with a `Limitation`.
- What does the body do with `T`? Opaque → no Loose finding. Index, property read, spread, method call, `as any`
  bridge → Loose, with the tightest constraint every instantiation satisfies. Array or object literal parameter whose
  literal types a consumer re-narrows → the `const` form (5.0+ per lockfile).

For each conditional / recursive / remapped / template-literal type:

- What does each enumerated instantiation need of it? A simpler form that holds equal precision on every one → Over-
  Powered Type Constructs. Any instantiation that needs the power (a conflicting key, a nested object, a library
  constraint) → no finding.

For each hand-rolled mapped or conditional utility:

- Which built-in? Gate 1 (lockfile version), gate 2 (homomorphic modifiers, distributivity, identical behaviour on
  every use), gate 3 (a name is removed). All three → Reinvented Utility Types. Different semantics → no finding.

For each `enum`: apply Enum Construct Mechanics — TypeScript forms above.

A `type X = string`-style alias is not judged here (Applicability).
