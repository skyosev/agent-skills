---
name: boundary-hunter-go
description: |
  Audit Go packages for boundary violations — leaked internals via exports, coupling through
  shared types, import cycles, missing internal/ packages, over-exported APIs, and dependency
  direction violations.

  Use when: reviewing package structure, shrinking public API surface, enforcing encapsulation,
  preparing packages for replacement, or untangling tight coupling between layers.
---

# Boundary Hunter

Audit Go code for **package boundary violations** — places where implementation details leak through exports, where
packages reach into each other's internals, or where coupling makes replacement impossible. The goal: **every package
is a black box, replaceable from its exported API alone.**

Go enforces some boundaries at the language level (unexported identifiers, import cycle prohibition, `internal/`
packages), but many boundary violations are still possible within those constraints.

## When to Use

- Reviewing package boundaries before or after a refactor
- Shrinking a package's exported API to what is actually consumed
- Preparing a package to be replaceable (rewritable from its API alone)
- Untangling tight coupling between layers or modules
- Wrapping external dependencies behind internal interfaces
- Enforcing unidirectional dependency flow between layers

## Core Principles

1. **A package is its exported API.** Exported identifiers are promises. Unexported identifiers are implementation
   details. Exports should describe _what the package does_, never _how it does it_. If a consumer must understand
   internals to use the API correctly, the boundary is broken.

2. **Minimal exported surface.** Export only what is consumed or serves as a deliberate extension point. Every exported
   symbol is a coupling point that constrains future changes. Go's convention: start unexported, export when needed.

3. **Depend on interfaces, not concretions.** Packages should depend on interfaces (defined at the consumer) — not on
   concrete types from other packages. If package A imports a concrete struct from package B, A is coupled to B's
   implementation. If A defines an interface that B happens to implement, A is coupled only to the contract.

4. **Dependency direction must follow architectural intent.** In a layered architecture, dependencies flow inward:
   infrastructure → application → domain. A domain package importing from infrastructure is a boundary violation.

5. **Wrap externals — don't let them leak.** Third-party types and APIs should not appear in domain or application
   layer exported signatures. Wrap them behind owned types so the external can be replaced without changing consumers.
   Infrastructure/adapter packages may use external types in their implementation. The rule is strict for inward
   layers, relaxed at the system edge.

6. **Use `internal/` for enforced encapsulation.** Go's `internal/` package mechanism provides compiler-enforced
   boundary protection. Packages that should not be imported by external consumers belong under `internal/`.

7. **Primitives flow; implementation types stay home.** Data that flows between packages should be expressed as
   primitive types, standard library types, or shared domain types — not as package-internal structs that force
   consumers to import from the implementation.

## What to Hunt

### 1. Over-Exported API Surface

Exported symbols that serve no external consumer — internal helpers, intermediate types, or implementation utilities
that happen to start with an uppercase letter.

**Signals:**

- Exported function/type with zero import sites outside its own package
- Exported type that includes implementation-specific fields (internal caches, state machines)
- Exported helpers/utilities alongside domain API
- Exported constructor for a type that should be package-private

**Action:** Unexport the symbol. If consumed externally, evaluate whether the consumer should own the concept.

### 2. Missing `internal/` Packages

Implementation packages that are importable by external consumers but shouldn't be.

**Signals:**

- Utility packages under `pkg/` that are only used by sibling packages in the same module
- Shared helper packages that are not part of the public API
- Packages containing implementation details that external consumers could accidentally depend on
- Infrastructure adapters that should not be directly imported by domain packages

**Action:** Move to `internal/` to enforce the boundary at the compiler level.

### 3. Coupling Through Shared Types

Two packages that share a type where neither owns it, or where one package's internal type appears in another
package's function signatures.

**Signals:**

- Package A imports a type defined in package B that is not part of B's intended public API
- A "shared types" package that grows unboundedly, coupling all importers
- Function signature contains a parameter typed as another package's internal struct
- Domain types defined in infrastructure packages

**Action:** Move shared types to a dedicated domain/contracts package owned by neither. Or define the interface in the
consumer and have the producer conform to it.

### 4. Deep Import Paths

Consumers importing sub-packages that should be internal to a parent package.

**Signals:**

- Imports like `github.com/org/repo/pkg/auth/internal/tokens` from outside `auth/`
- Imports reaching into implementation sub-packages (`service/impl/`, `handler/private/`)
- Multiple import paths for the same concept (re-exported inconsistently)

**Action:** Use `internal/` to enforce boundaries. Expose needed symbols through the parent package's API.

### 5. Dependency Direction Violations

A lower-level package importing from a higher-level package, breaking the intended layering.

**Signals:**

- Domain package importing from infrastructure or transport layer
- Shared utility importing from a feature package
- A "core" package that depends on a "feature" package
- Model/entity package importing from handler/controller package

**Action:** Invert the dependency. Define an interface in the lower layer; implement it in the higher layer. Wire via
dependency injection at the composition root.

### 6. External Type Leaks

Third-party library types appearing in exported signatures of domain or application packages.

**Signals:**

- Exported function parameter or return type from a third-party module in a domain package
- Package re-exports a third-party type as part of its own API
- Switching the underlying library would require changing consumer code
- Framework-specific types (e.g., `gin.Context`, `echo.Context`) in domain or application packages

**Acceptable:** Infrastructure/adapter packages using external types in their exported API — they _are_ the wrapping
layer. Flag only when these types leak inward into domain/application consumers.

**Action:** Define an owned interface or type that wraps the external. The wrapping package is the only place that
imports from the external. Consumers depend on the owned type.

### 7. Package Naming and Organization Issues

Packages named by what they contain rather than what they provide.

**Signals:**

- Packages named `util`, `utils`, `helpers`, `common`, `misc`, `base`, `shared`
- Package name that doesn't match the directory name
- Package `models` that contains types for unrelated domains
- Deeply nested package paths for simple concepts
- Multiple files in a package spanning unrelated concerns

**Action:** Name packages after their domain concept or capability. Split mixed-concern packages. Flatten unnecessary
nesting.

## Audit Workflow

### Phase 1: Map Package Boundaries

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project
   If unspecified, default to **codebase**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent scans to the resolved surface.
2. **Identify packages.** List all Go packages and their import paths. Note `internal/` packages.
3. **Catalogue exports.** For each package, list exported types, functions, and variables. Classify each as:
   type, function, constant, variable.
4. **List external dependencies.** For each package, list imports from outside the module. Note which external types
   appear in exported signatures.

### Phase 2: Analyze Dependency Graph

1. **Build import map.** For each package, list which other internal packages it imports from.
   ```bash
   # List all imports per file
   rg '^import' --type go -A 20 --glob '!**/vendor/**' --glob '!**/*_test.go'

   # Or use go list for structured data
   go list -json ./... 2>/dev/null | rg '"(Imports|ImportPath)"'
   ```
2. **Check direction.** If the project has an intended layering (domain → application → infrastructure), verify all
   import arrows point in the correct direction.
3. **Check for `internal/` usage.** Are implementation packages properly under `internal/`?
4. **Measure fan-in / fan-out.** Packages with high fan-in (many importers) are stability anchors — changes are costly.
   Packages with high fan-out (many imports) are fragile.

### Phase 3: Audit Export Surface

For each package:

1. **Dead exports.** Is every exported symbol consumed by at least one external package?
   ```bash
   EXCLUDE='--glob !**/vendor/** --glob !**/*_test.go'

   # Find all exported symbols
   rg 'func\s+[A-Z]|type\s+[A-Z]|var\s+[A-Z]|const\s+[A-Z]' --type go $EXCLUDE

   # For each exported symbol, check external usage
   rg 'SymbolName' --type go $EXCLUDE
   ```
   Verify each candidate finding manually — a grep miss is not proof of zero usage.
2. **Leaked internals.** Do any exports expose implementation details?
3. **External type leaks.** Do any exports use third-party types in their signatures?

### Phase 4: Audit Consumer Access Patterns

For each package's consumers:

1. **Deep imports.** Are consumers importing sub-packages that should be internal?
2. **Knowledge coupling.** Do consumers make decisions based on implementation details of the imported package?

### Phase 5: Evaluate Replaceability

For each package, answer:

1. **Could this package be rewritten from its exported API alone?** If a new developer needed to rewrite the package,
   would the exported types + function signatures be sufficient?
2. **What would break if the implementation changed completely?** If the answer is "only the package's tests", the
   boundary is clean.
3. **Are there implicit contracts not captured in the API?** Ordering guarantees, side effects, goroutine safety,
   context cancellation behavior — anything consumers depend on that isn't in the type signature.

## Output Format

Save as `YYYY-MM-DD-boundary-hunter-audit.md` in the project's docs folder (or project root if no docs folder exists).

```md
# Boundary Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Package Map

| Package | Exported Symbols | External Deps | Fan-In | Fan-Out |
| ------- | ---------------- | ------------- | ------ | ------- |
| domain/order | 5 types, 2 fns | 0 | 8 | 1 |
| infra/postgres | 3 fns | 1 (pgx) | 2 | 4 |

## Dependency Graph Issues

### Direction Violations

- domain/X imports from infra/Y ({symbol}, {file:line})

## Export Surface Issues

### Over-Exported API

| # | Package | Export | Type | External Consumers |
| - | ------- | ------ | ---- | ------------------ |
| 1 | pkg/auth | `helperFn` | function | 0 |

### Missing internal/ Packages

| # | Package | Reason | Action |
| - | ------- | ------ | ------ |
| 1 | pkg/crypto/impl | Only used by pkg/crypto | Move to internal/ |

### External Type Leaks

| # | Package | Export / Signature | External Type | Action |
| - | ------- | ------------------ | ------------- | ------ |
| 1 | domain/user | `Save(ctx context.Context, tx pgx.Tx)` | `pgx.Tx` | Wrap behind owned interface |

## Consumer Access Violations

### Deep Imports

| # | Consumer | Imported Path | Should Use |
| - | -------- | ------------- | ---------- |
| 1 | file.go:line | `auth/internal/tokens` | `auth` |

## Package Naming Issues

| # | Package | Issue | Action |
| - | ------- | ----- | ------ |
| 1 | `utils` | Generic name, mixed concerns | Split by capability |

## Replaceability Assessment

### {Package Name}

- Replaceable from API? {yes/no — why}
- Implicit contracts: {goroutine safety, ordering, side effects}
- Coupling risk: {low/med/high}

## Recommendations (Priority Order)

1. **Must-fix**: {direction violations, external leaks in domain layer}
2. **Should-fix**: {dead exports, missing internal/, over-exported API}
3. **Consider**: {replaceability improvements, package naming, deep imports}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: package boundaries only.** Encapsulation, coupling, dependency direction, API surface. Do not flag type
  safety (→ invariant-hunter-go), type design (→ type-hunter-go), structural complexity (→ simplicity-hunter-go),
  interface design (→ solid-hunter-go), missing documentation (→ doc-hunter-go), security (→ security-hunter-go),
  test quality (→ test-hunter-go), or cosmetic style (→ slop-hunter-go). If a finding doesn't answer "is this boundary
  clean?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code or import statement.
- **Architecture-first.** Understand the project's intended layering before flagging violations. Ask if unclear.
- **Pragmatism over purism.** Not every coupling is worth breaking. Small utilities shared between two closely related
  packages may be fine. Flag, but don't insist on architectural astronautics.
- **Measure, don't guess.** Use `rg`, `go list`, and import analysis to count actual consumers.
- **Respect Go conventions.** Go packages are designed to be flat and focused. Don't impose Java-style deep package
  hierarchies. Go's `internal/` mechanism is the primary boundary enforcement tool.
