---
name: boundary-hunter-tooling
description: |
  Audit TypeScript module boundaries with machine-verifiable evidence from dependency-cruiser and ts-morph only.
  Detect cycles, direction violations, deep imports, dead exports, leaked internals, and external type leaks.

  Use when: gating CI on architecture contracts, validating refactors, or replacing regex-only boundary audits.
---

# Boundary Hunter Tooling

Companion skill to `boundary-hunter`. This one is strict: boundary findings must come from `dependency-cruiser` and
`ts-morph`, not grep heuristics.

## Scope

- Boundary violations only: dependency direction, cycles, deep imports, export surface leaks
- No type-invariant audit
- No code edits; produce an audit report only

## Tool Roles

1. **`dependency-cruiser`**: dependency graph truth
   - Runtime and type-only cycles
   - Layer direction violations
   - Deep import violations
   - Fan-in and fan-out hotspots
2. **`ts-morph`**: symbol/API truth
   - Public export inventory
   - Dead export candidates with real reference counts
   - Exported signatures that leak external package types
   - Exports that expose implementation details

## Preconditions

1. Confirm a TypeScript project root and `tsconfig.json` path.
2. Confirm source roots (for example `{app_source}`, `packages/*/src`).
3. Confirm layer map with the requester before enforcing direction rules.
4. Ensure tools are available:
   ```bash
   npm ls dependency-cruiser ts-morph --depth=0
   ```
   If missing, request approval and install:
   ```bash
   npm install -D dependency-cruiser ts-morph
   ```

Before running the audit, fill these placeholders for the target codebase:

- `{app_source}`: main app source root (for example `src`, `new-app/src`, `packages/app/src`)
- `{domain_layer}`: domain layer segment (for example `domain`, `core/domain`)
- `{application_layer}`: application/use-case layer segment (for example `application`, `use-cases`)
- `{infrastructure_layers_regex}`: infrastructure/edge layers as regex group (for example `(infra|adapters|ui|render)`)
- `{source_roots_regex}`: depcruise include regex for all roots under audit
- `{source_roots_args}`: CLI roots list for depcruise (space-separated)
- `{source_roots_csv}`: comma-separated roots for ts-morph script input
- `{test_exclude_regex}`: test/spec exclusion regex for depcruise

## Audit Workflow

### Phase 1: Encode Architecture Rules for `dependency-cruiser`

Create a temporary rules file (customize path regexes to the current codebase):

```js
// /tmp/{agent-name}-depcruise.boundary.cjs
/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
    // Fill placeholders before running:
    // {app_source}, {domain_layer}, {application_layer},
    // {infrastructure_layers_regex}, {source_roots_regex}, {test_exclude_regex}
    forbidden: [
        {
            name: 'no-circular-runtime',
            severity: 'error',
            from: {},
            to: { circular: true, dependencyTypesNot: ['type-only'] }
        },
        {
            name: 'no-domain-to-application',
            severity: 'error',
            from: { path: '^{app_source}/{domain_layer}' },
            to: { path: '^{app_source}/{application_layer}' }
        },
        {
            name: 'no-domain-to-infra',
            severity: 'error',
            from: { path: '^{app_source}/{domain_layer}' },
            to: { path: '^{app_source}/{infrastructure_layers_regex}' }
        },
        {
            name: 'no-application-to-infra',
            severity: 'warn',
            from: { path: '^{app_source}/{application_layer}' },
            to: { path: '^{app_source}/{infrastructure_layers_regex}' }
        },
        {
            name: 'no-deep-imports',
            severity: 'warn',
            from: {},
            to: {
                path: '^{app_source}/.+/.+',
                pathNot: 'index\\.ts$'
            }
        }
    ],
    options: {
        tsConfig: { fileName: 'tsconfig.json' },
        doNotFollow: { path: 'node_modules' },
        includeOnly: '{source_roots_regex}',
        exclude: {
            path: '{test_exclude_regex}'
        }
    }
};
```

### Phase 2: Run Graph Analysis

```bash
# Human-readable rule breaches
npx depcruise --config /tmp/{agent-name}-depcruise.boundary.cjs --output-type err-long {source_roots_args} \
  > /tmp/{agent-name}-depcruise.boundary.err.txt

# Full machine-readable graph (for cycle/fan-in/fan-out analysis)
npx depcruise --config /tmp/{agent-name}-depcruise.boundary.cjs --output-type json {source_roots_args} \
  > /tmp/depcruise.boundary.json
```

Required outputs from this phase:

- Rule violations by rule name (`no-circular-runtime`, direction rules, deep imports)
- Runtime cycles vs type-only cycles
- Module fan-in/fan-out list (top 10 each)

### Phase 3: Run `ts-morph` Export Surface Audit

Write and run a temporary `ts-morph` script that outputs JSON evidence. The script must:

1. Load the project from `tsconfig.json`.
2. Identify module entry files (`index.ts` and package entrypoints from `exports`).
3. Enumerate exported declarations for each module.
4. For each exported symbol, count references outside the declaring module.
5. Flag dead export candidates (`externalConsumers = 0`).
6. Flag exported signatures that include types imported from package specifiers (non-relative imports).
7. Emit `file:line` for each finding.

Run the script and persist output:

```bash
node /tmp/{agent-name}-ts-morph-boundary-audit.mjs \
  --tsconfig tsconfig.json \
  --roots {source_roots_csv} \
  --out /tmp/{agent-name}-tsmorph.boundary.json
```

### Phase 4: Correlate and Classify Findings

Correlate both artifacts before reporting:

- A depcruise direction violation + ts-morph external type leak in the same module = stronger evidence, higher priority
- A ts-morph dead export without graph pressure = lower priority cleanup
- Runtime cycles are **must-fix**
- Type-only cycles in same-layer co-evolving modules are **should-fix** unless explicitly justified

## Output Format

Save report as `Y-m-d-boundary-audit-tooling-{agent-name}.md` (for example under `docs/dev-specs/`).

```md
# Boundary Audit (Tool-Assisted) — {date}

## Context

- tsconfig: {path}
- Source roots: {list}
- Layer map used: {list}
- depcruise config: {/tmp/{agent-name}-depcruise.boundary.cjs}
- Artifacts:
  - {/tmp/{agent-name}-depcruise.boundary.err.txt}
  - {/tmp/{agent-name}-depcruise.boundary.json}
  - {/tmp/{agent-name}-tsmorph.boundary.json}

## Dependency Graph Findings (`dependency-cruiser`)

### Runtime Cycles (Must-Fix)

- {A -> B -> A} ({files})

### Type-Only Cycles (Needs Justification or Fix)

- {A -> B -> A} ({files}, justification={yes/no})

### Direction Violations

- {ruleName}: {from} -> {to} ({file:line})

### Deep Imports

- {consumer} imports {internal/path} ({file:line})

### High Fan-In / Fan-Out

- Fan-in: {module, count}
- Fan-out: {module, count}

## Export Surface Findings (`ts-morph`)

### Dead Export Candidates

| # | Module | Export | Kind | External Consumers | Evidence  |
| - | ------ | ------ | ---- | ------------------ | --------- |
| 1 | ...    | ...    | ...  | 0                  | file:line |

### External Type Leaks in Public Signatures

| # | Module | Export | External Type | Layer                         | Evidence  |
| - | ------ | ------ | ------------- | ----------------------------- | --------- |
| 1 | ...    | ...    | ...           | {domain_or_application_layer} | file:line |

### Leaked Implementation Types

| # | Module | Export | Why Internal | Evidence  |
| - | ------ | ------ | ------------ | --------- |
| 1 | ...    | ...    | ...          | file:line |

## Recommendations (Priority Order)

1. **Must-fix**: runtime cycles, inward direction violations, external type leaks into `{domain_layer}` /
   `{application_layer}` APIs
2. **Should-fix**: type-only cycles without justification, deep imports, dead exports with zero consumers
3. **Consider**: API simplification for replaceability and fan-out reduction
```

## Operating Constraints

- **Tool purity**: findings must be derived from `dependency-cruiser` and `ts-morph` outputs.
- **No grep-only evidence**: regex search can help orient exploration but is insufficient as proof.
- **Evidence required**: every finding includes `file:line` and artifact source.
- **Architecture-first**: do not enforce direction rules without an explicit layer map.
- **No implementation edits**: this skill ends at an audit report.
