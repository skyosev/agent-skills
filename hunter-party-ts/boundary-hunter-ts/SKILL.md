---
name: boundary-hunter-ts
description: |
  Audit TypeScript modules for black-box boundary violations — leaked internals via exports, coupling through
  shared types, Law of Demeter chains, missing abstraction layers around externals, and over-exported APIs.

  Use when: reviewing module structure, shrinking public API surface, enforcing encapsulation,
  preparing modules for replacement, or untangling tight coupling between layers.
---

# Boundary Hunter

Audit TypeScript code for **module boundary violations** — places where implementation details leak through exports,
where modules reach into each other's internals, or where coupling makes replacement impossible. The goal: **every
module is a black box, replaceable from its interface alone.**

## When to Use

- Reviewing module boundaries before or after a refactor
- Shrinking a module's public API to what is actually consumed
- Preparing a module to be replaceable (rewritable from interface alone)
- Untangling tight coupling between layers or packages
- Wrapping external dependencies behind internal abstractions
- Enforcing unidirectional dependency flow between layers

## Core Principles

1. **A module is its interface.** Everything not exported is an implementation detail. Everything exported is a promise.
   Exports should describe _what the module does_, never _how it does it_. If a consumer must understand internals to
   use the API correctly, the boundary is broken.

2. **Minimal public surface.** Export only what is consumed or serves as a deliberate extension point. Every additional
   export is a coupling point that constrains future changes. `index.ts` barrel files should re-export the _public API_,
   not the entire directory.

3. **Depend on abstractions, not concretions.** Modules should depend on interfaces (types, contracts) owned by the
   consumer or a shared kernel — not on concrete implementations from other modules. If module A imports a class from
   module B, A is coupled to B's implementation. If A imports an interface that B happens to implement, A is coupled
   only to the interface contract.

4. **Dependency direction must follow architectural intent.** In a layered architecture, dependencies flow inward:
   infrastructure → application → domain. A domain module importing a concrete implementation from infrastructure is a
   boundary violation. **Exception:** type-only imports from a shared kernel or contracts layer that both sides depend on
   are not violations — this is standard DDD practice. Type-only import cycles between co-evolving modules in the same
   layer may be acceptable with explicit justification, but default to breaking them. Runtime cycles are always
   violations.

5. **Wrap externals — don't let them leak.** Third-party types and APIs should not appear in domain or application layer
   interfaces. Wrap them behind owned types so the external can be replaced without changing consumers.
   Infrastructure/adapter modules _are_ the wrapping layer — they may use external types in their implementation and
   even in their own interface when they serve as the system edge. The rule is strict for inward layers, relaxed at the
   boundary with the outside world.

6. **One reach, not a chain.** A consumer should call a module's API directly — not reach through it into a transitive
   dependency's API. `a.getB().getC().doThing()` (Law of Demeter violation) exposes B's and C's existence to A's caller.
   If a consumer needs something from a transitive dependency, the immediate dependency should expose it through its own
   API.

7. **Primitives flow; implementation types stay home.** Data that flows between modules should be expressed as primitive
   types, plain objects, or shared domain types — not as module-internal classes or enums that force consumers to import
   from the implementation. Branded/opaque types (e.g., `UserId`, `Millimetres`) are fine to cross boundaries when they
   represent _domain contracts_; they are violations when they encode _implementation details_ (e.g., internal cache
   keys, serialization formats).

## What to Hunt

### 1. Leaked Internals

Internal helpers, intermediate types, constants, or utility functions that are exported but serve no external consumer.

**Signals:**

- Exported symbol has zero external import sites
- Exported type includes implementation-specific fields (e.g., internal caches, memoization keys, AST nodes)
- A type's structure reveals _how_ the module works, not _what_ it produces
- Utility/helper functions exported alongside domain API

**Action:** Remove export, or if consumed externally, evaluate whether the consumer should own the concept.

### 2. Over-Exported Barrel Files

`index.ts` that re-exports everything from every internal file, turning the entire module into a public API.

**Signals:**

- `export * from './internal-file'` patterns
- Barrel re-exports symbols that no external module imports
- Consumers import deep paths (`module/internal/helper`) bypassing the barrel

**Action:** Replace `export *` with explicit named re-exports of the public API. Block deep imports via package.json
`exports` field or path conventions.

### 3. Coupling Through Shared Types

Two modules that share a type where neither owns it, or where one module's internal type appears in another module's
function signatures.

**Signals:**

- Module A imports a type defined inside module B's internal files (not B's public API)
- A "shared types" file that grows unboundedly, coupling all importers
- Function signature contains a parameter typed as another module's internal class/interface

**Action:** Move shared types to a shared kernel / contracts layer owned by neither module. Or, define the type in the
consumer and have the producer conform to it (dependency inversion).

### 4. Law of Demeter Violations (Train Wrecks)

Long chains of property access or method calls that traverse multiple levels of abstraction.

**Signals:**

- `a.b.c.d` chains accessing nested properties across module boundaries
- Functions that destructure deeply into a parameter: `({ config: { theme: { colors } } }) => ...`
- Consumer code that "knows" the internal structure of a returned value three levels deep

**Action:** Expose a direct API on the immediate dependency. If the consumer needs `c.d`, then the module owning `c`
should provide a method or accessor for it.

### 5. Missing Abstraction Over Externals

Third-party library types or APIs used directly in domain or application layer interfaces, coupling consumers to a
specific library.

**Signals:**

- Function parameter or return type in domain/application code is a type imported from `node_modules`
- Module re-exports a third-party type as part of its own API
- Switching the underlying library would require changing consumer code
- Framework-specific types (e.g., `Express.Request`, `React.FC`) in domain or application layers

**Acceptable:** Infrastructure/adapter modules using external types in their own interface — they _are_ the wrapping
layer. Flag only when these types leak inward into domain/application consumers.

**Action:** Define an owned interface that wraps the external type. The wrapping module is the only place that imports
from the external. Consumers depend on the owned interface.

### 6. Cyclic Dependencies

Two or more modules that import from each other, directly or transitively.

**Signals:**

- Module A imports from B, and B imports from A (direct cycle)
- Longer chains: A → B → C → A (transitive cycle)
- Barrel files that create implicit cycles by re-exporting across boundaries
- Circular reference errors at runtime or in bundlers

**Action:** Runtime cycles and cycles that cross architectural layers are must-fix — break by extracting the shared
concept into a third module, or inverting the dependency direction. Type-only import cycles between co-evolving modules
in the same layer may be acceptable if explicitly justified.

### 7. Dependency Direction Violations

A lower-level module importing from a higher-level module, breaking the intended layering.

**Signals:**

- Domain module importing from infrastructure or UI layer
- Shared utility importing from a feature module
- A "core" module that depends on a "feature" module

**Action:** Invert the dependency. Define an interface in the lower layer; implement it in the higher layer. Wire via
dependency injection, factory, or configuration.

## Audit Workflow

### Phase 1: Map Module Boundaries

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or layers
   - **Codebase**: the entire project
   If unspecified, default to **codebase**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent scans to the resolved surface.
2. **Identify modules.** A module is a directory with an `index.ts` or a standalone file that other files import from.
   If the project uses `package.json` `exports` or tsconfig path aliases to define boundaries, use those as the source
   of truth. List all modules and their barrel files.
3. **Catalogue exports.** For each module, list its public exports (from `index.ts` or direct imports). Classify each
   as: type, function, constant, class, enum.
4. **List external dependencies.** For each module, list imports from `node_modules`. Note which external types appear
   in the module's public interface.

### Phase 2: Analyze Dependency Graph

1. **Build import map.** For each module, list which other internal modules it imports from.
2. **Check direction.** If the project has an intended layering (domain → application → infrastructure), verify all
   arrows point in the correct direction.
3. **Detect cycles.** Identify direct and transitive cycles.
4. **Measure fan-in / fan-out.** Modules with high fan-in (many importers) are stability anchors — changes are costly.
   Modules with high fan-out (many imports) are fragile — sensitive to changes elsewhere.

### Phase 3: Audit Export Surface

For each module:

1. **Dead exports.** Is every export consumed by at least one external module? Use grep as a first-pass heuristic:
   ```bash
   # Find all exports
   rg 'export (function|const|class|enum|type|interface|default)' path/to/module/

   # For each exported symbol, check external usage
   rg 'import.*{.*SymbolName.*}.*from.*module-path' --type ts
   ```
   This misses default imports, namespace imports, re-exports, and alias paths. Verify each candidate finding manually
   before reporting — a grep miss is not proof of zero usage.
2. **Leaked internals.** Do any exports expose implementation details (internal caches, intermediate representations,
   helper utilities)?
3. **External type leaks.** Do any exports use third-party types in their signatures?

### Phase 4: Audit Consumer Access Patterns

For each module's consumers:

1. **Deep imports.** Are consumers importing from internal paths (bypassing the barrel)?
   Replace `(module-name)` and `@alias` below with actual module names and tsconfig path aliases from the project:
   ```bash
   EXCLUDE='--glob !**/*.test.* --glob !**/*.spec.* --glob !**/node_modules/**'

   # Relative deep imports (substitute actual module directory name)
   rg --pcre2 "from ['\"]\..*/(module-name)/(?!index)" --type ts $EXCLUDE

   # Alias-based deep imports (substitute actual tsconfig paths alias)
   rg --pcre2 "from ['\"]@alias/(module-name)/" --type ts $EXCLUDE
   ```
2. **Train wrecks.** Are consumers accessing nested properties across boundaries?
   ```bash
   # Find deep property chains (3+ levels)
   rg --pcre2 '\w+\.\w+\.\w+\.\w+' --type ts $EXCLUDE
   ```
3. **Knowledge coupling.** Do consumers make decisions based on implementation details of the imported module (e.g.,
   checking internal state, knowing about internal data structures)?

### Phase 5: Evaluate Replaceability

For each module, answer:

1. **Could this module be rewritten from its interface alone?** If a new developer needed to rewrite the module, would
   the public types + function signatures be sufficient? Or would they need to read consumers to understand implicit
   contracts?
2. **What would break if the implementation changed completely?** If the answer is "only the module's tests", the
   boundary is clean. If consumers would break, the boundary leaks.
3. **Are there implicit contracts not captured in the interface?** Ordering guarantees, side effects, mutation of
   parameters, callback timing — anything consumers depend on that isn't in the type signature.

## Output Format

Produce a single report. Save as `YYYY-MM-DD-boundary-hunter-audit.md` in the project's docs folder (or project root if no docs folder exists).

```md
# Boundary Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Module Map

| Module        | Public Exports | External Deps | Fan-In | Fan-Out |
| ------------- | -------------- | ------------- | ------ | ------- |
| domain/shapes | 5 types, 2 fns | 0             | 8      | 1       |
| infra/svg     | 3 fns          | 1 (d3-path)   | 2      | 4       |

## Dependency Graph Issues

### Cycles

- A → B → A (via {symbols})

### Direction Violations

- domain/X imports from infra/Y ({symbol}, {file:line})

## Export Surface Issues

### Dead Exports

| # | Module      | Export     | Type     | External Consumers |
| - | ----------- | ---------- | -------- | ------------------ |
| 1 | module/path | `helperFn` | function | 0                  |

### Leaked Internals

| # | Module      | Export          | Why Internal          | Action        |
| - | ----------- | --------------- | --------------------- | ------------- |
| 1 | module/path | `InternalCache` | Implementation detail | Remove export |

### External Type Leaks

| # | Module      | Export / Signature        | External Type | Action                 |
| - | ----------- | ------------------------- | ------------- | ---------------------- |
| 1 | module/path | `process(input: LibType)` | `lib@LibType` | Wrap behind owned type |

## Consumer Access Violations

### Deep Imports (Bypassing Barrel)

| # | Consumer     | Imported Path            | Should Use |
| - | ------------ | ------------------------ | ---------- |
| 1 | file.ts:line | `module/internal/helper` | `module`   |

### Law of Demeter Violations

| # | Location     | Chain     | Depth | Action            |
| - | ------------ | --------- | ----- | ----------------- |
| 1 | file.ts:line | `a.b.c.d` | 4     | Expose API on `a` |

## Replaceability Assessment

### {Module Name}

- Replaceable from interface? {yes/no — why}
- Implicit contracts: {ordering, side effects, timing, etc.}
- Coupling risk: {low/med/high}

## Recommendations (Priority Order)

1. **Must-fix**: {runtime cycles, direction violations, external leaks in domain layer}
2. **Should-fix**: {dead exports, leaked internals, deep imports}
3. **Consider**: {replaceability improvements, barrel cleanup, train wrecks}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: module boundaries only.** Encapsulation, coupling, dependency direction, API surface. Do not flag type
  invariants (→ invariant-hunter-ts), type design (→ type-hunter-ts), structural complexity (→ simplicity-hunter-ts),
  class/interface design (→ solid-hunter-ts), missing documentation (→ doc-hunter-ts), security (→ security-hunter-ts),
  test quality (→ test-hunter-ts), or cosmetic style (→ slop-hunter-ts). If a finding doesn't answer "is this boundary
  clean?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact code or import statement.
- **Architecture-first.** Understand the project's intended layering before flagging violations. Ask if unclear.
- **Pragmatism over purism.** Not every coupling is worth breaking. Small utilities shared between two closely related
  modules may be fine. Flag, but don't insist on architectural astronautics.
- **Measure, don't guess.** Use `rg` and import analysis to count actual consumers, not hypothetical ones.
- **Challenge assumptions.** If the current structure makes a deliberate trade-off (e.g., a shared types file for
  co-evolving modules), acknowledge it rather than mechanically flagging it.
