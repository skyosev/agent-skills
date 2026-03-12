---
name: smell-hunter-py
description: |
  Audit Python code for classic code smells — feature envy, data clumps, shotgun surgery,
  temporal coupling, comments as deodorant, temporary fields, god modules, mutable default
  arguments, and class abuse.

  Use when: reviewing Python code for structural design problems, preparing for a refactor,
  auditing code after rapid feature development, or hunting for misplaced responsibilities.
---

# Smell Hunter

Audit Python code for **code smells** — structural patterns that indicate deeper design problems. This covers
selected Fowler/Beck smells and Python-specific antipatterns that fall outside the scope of specialized hunters
(SOLID, type design, boundaries, invariants, etc.). The goal: **data lives where it's used, changes are localized,
domain concepts are modeled explicitly, and Python idioms are respected.**

**Not covered (owned by other hunters):** long method / mixed concerns (→ simplicity-hunter), dead code
(→ simplicity-hunter / slop-hunter), speculative generality (→ simplicity-hunter), magic numbers (→ doc-hunter),
interface pollution (→ simplicity-hunter / solid-hunter), primitive obsession / type design (→ type-hunter). See
Operating Constraints for handoff rules.

Code smells are symptoms, not diagnoses. Each finding indicates a *likely* design problem that warrants investigation.
Context determines whether the smell is a genuine issue or an acceptable trade-off.

## When to Use

- Reviewing code for structural design problems before a refactor
- Auditing code after rapid feature development or prototyping
- Hunting for misplaced responsibilities and data
- Identifying missing domain types and abstractions
- Preparing a codebase for long-term maintainability
- Complementing specialized hunters with cross-cutting smell detection

## Core Principles

1. **Smells are symptoms, not diseases.** A code smell indicates a probable design problem, not a guaranteed one.
   Evaluate each smell in context — some are intentional trade-offs. The goal is awareness, not mechanical elimination.

2. **Follow the data.** Feature envy and data clumps point to misplaced or undermodeled data.
   When data and behavior want to be together, let them. When a group of values always travels together, they are a
   missing type.

3. **One change, one place.** Shotgun surgery means a single logical change requires edits across many unrelated files.
   This is the hallmark of misaligned module boundaries or scattered responsibilities. The fix is cohesion.

4. **Comments should not be deodorant.** A comment explaining confusing code is a band-aid over a design problem. The
   fix is clearer code — better names, extracted functions, simpler structure — not more comments.

5. **Model the domain.** Data clumps often indicate missing domain types. A tuple of `float`s
   that represent a coordinate, or a group of parameters that always appear together — these are domain concepts
   begging for a dataclass or NamedTuple. (For primitive-to-domain-type promotions like `str` → `NewType`, see
   type-hunter-py.)

6. **Use the language, not fight it.** Python has powerful features — dataclasses, NamedTuples, Protocols, descriptors,
   context managers, generators — that eliminate entire categories of smells. When the language provides an idiom,
   use it instead of reimplementing patterns from other languages.

7. **Refactor incrementally.** Split by responsibility, not by size. Introduce abstraction only when needed (wait for
   the second use case). Preserve behavior first — add tests before restructuring.

## What to Hunt

### 1. Feature Envy

A function or method that uses more data from another module or class than from its own context.

**Signals:**

- Method on class A that primarily accesses attributes/methods of class B (passed as parameter)
- Function that destructures an object from another module and operates on most of its attributes
- Helper function that exists in module A but only operates on types from module B
- Function that receives an object and calls 3+ of its methods while using none of its own scope
- A function whose name suggests it belongs to the type it operates on, not the module it lives in

**Action:** Move the function to the module/class that owns the data it operates on. If it uses data from two types
equally, consider whether the shared data should be extracted into its own type.

### 2. Data Clumps

The same group of parameters or attributes that always appear together across multiple function signatures or type
definitions.

**Signals:**

- 3+ parameters that appear together in multiple function signatures (e.g., `host`, `port`, `scheme` or
  `latitude`, `longitude`, `altitude`)
- Multiple dataclasses/dicts with the same subset of fields (e.g., `street`, `city`, `zip`, `country` in several
  types)
- Functions that pass a group of related values individually instead of as a dataclass
- Dataclass with fields that form a logical sub-group (e.g., `start_date`, `end_date`, `timezone` inside a larger
  config)

**Action:** Extract the group into a named dataclass or NamedTuple. Replace the individual parameters/fields with the
type. If the group appears only in function signatures, create a parameter type. If it appears in multiple type
definitions, extract a shared type.

### 3. Shotgun Surgery

A single logical change requires edits across many unrelated files or modules.

**Signals:**

- Adding a new field to a domain type requires updating 5+ files (handlers, validators, serializers, tests)
- Adding a new API endpoint requires changes in routes, views, services, repositories, types, and tests with
  boilerplate that could be generated or derived
- A config change requires editing code in multiple modules rather than just the config module
- Renaming a concept requires find-and-replace across the entire codebase
- A new feature flag requires changes in config, middleware, views, and tests

**Action:** Consolidate the scattered responsibility. If a change to concept X requires touching modules A, B, C, D,
and E, then X's logic is spread too thin. Consider:
- A registry or dict-based dispatch instead of scattered if/elif chains
- Code generation or schema-driven types for boilerplate that varies with each new type/field
- A single module that owns the concept end-to-end
- Derive types from a single source of truth (e.g., Pydantic model → serializer → validator)

### 4. Temporal Coupling

Functions or operations that must be called in a specific order, but nothing in the API enforces that order.

**Signals:**

- A class with `init()`, `setup()`, or `configure()` methods that must be called before `run()` or `process()`
- Documentation or comments that say "must call X before Y"
- Runtime error or undefined behavior when methods are called in the wrong order
- A builder pattern where `build()` can be called before required fields are set
- State machine transitions that are valid only from certain states but not enforced by the type system

**Action:** Redesign the API to make the order implicit:
- Use `__init__` to accept all required dependencies — return a fully initialized object
- Use context managers (`with` statement) to enforce setup/teardown ordering
- Use factory functions that return a fully configured object
- Use dataclasses with required fields (no defaults) to enforce completeness at construction

### 5. Comments as Deodorant

Comments that paper over a confusing code structure that should be refactored instead. The smell is not the missing
documentation (→ doc-hunter) but the *design problem the comment is covering for*.

**Signals:**

- A multi-line comment explaining a block that should be an extracted function with an intent-revealing name
- Inline comments at each step of a long function, creating "sections" that should be separate functions
- Comments explaining complex boolean expressions instead of extracting them into named helpers
- Comments explaining workarounds for the code's *own* design (not external constraints)

**Action:** Extract the commented block into a function with an intent-revealing name. Replace complex expressions
with named variables or helper functions. If the comment explains an *external* constraint or business rule, it
belongs — that's doc-hunter territory, not a smell.

### 6. Temporary Field

Object attributes or dataclass fields that are meaningful only in certain states or during specific operations — they
are set for one code path and `None` for all others.

**Signals:**

- Class attribute that is non-None in only one of several code paths
- Attributes set in method A and read in method B but meaningless in methods C, D, E
- Optional fields that exist because the type is used in multiple contexts with different data requirements
- Attributes documented as "only valid when X is True" or "set only during processing"
- Dataclass with fields like `temp_result`, `cached_data`, `last_error` that serve a single transient use

**Action:** Extract the temporary attributes into a separate dataclass used only where needed. If the type represents
multiple states, use separate dataclasses per state or a tagged union. For transient computation, use local variables or
return values instead of instance attributes.

### 7. God Module

A single `.py` file that accumulates unrelated responsibilities, becoming the dumping ground for everything.

**Signals:**

- Module with 500+ lines mixing unrelated functionality
- Module name like `utils.py`, `helpers.py`, `common.py`, `misc.py` with broad scope
- Module imported by nearly every other module in the project
- Module with functions spanning different domain concepts
- `__init__.py` that contains business logic instead of just re-exports

**Action:** Split by responsibility into focused modules. Each module should have a clear, single purpose. If the
module is truly shared utilities, group by domain concept (e.g., `string_utils.py`, `date_utils.py`).

### 8. Mutable Default Arguments

Using mutable objects (lists, dicts, sets) as default argument values — a classic Python footgun.

**Signals:**

- `def func(items: list = [])` or `def func(config: dict = {})`
- Class `__init__` with mutable defaults: `def __init__(self, data: list = [])`
- Dataclass fields with `default=[]` or `default={}` (without `field(default_factory=list)`)
- Functions that mutate a default parameter and cause surprising state persistence between calls

**Action:** Use `None` as default and create the mutable object inside the function:
```python
def func(items: list[str] | None = None) -> None:
    items = items if items is not None else []
```
Or use `dataclasses.field(default_factory=list)` for dataclass fields.

### 9. Class Abuse

Using classes where plain functions, modules, or dataclasses would be simpler and more Pythonic.

**Signals:**

- Class with only `__init__` and one public method (a function in disguise)
- Class with only `@staticmethod`s or `@classmethod`s (a module in disguise)
- Class that holds no state — all methods are pure functions operating on their parameters
- Class used only to group related functions without shared state (use a module with functions)
- Class where `__init__` just assigns parameters to `self` with no validation or logic
- "Service" classes with no state that receive all data through method parameters
- Singleton classes implemented via `__new__` or metaclass (use a module-level instance)

**Action:** Replace with the simpler construct:
- Single-method class → exported function (possibly with closure for dependencies)
- Static-only class → module with named function exports
- Stateless class → module with named function exports
- Singleton class → module-level instance or factory function
- Data-holding class with meaningful behavior → keep the class or use a dataclass

## Audit Workflow

### Phase 1: Gain Context

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
2. Understand the project's domain model — what are the core entities, value objects, and operations?
3. Note the project's conventions for naming, type design, and module organization.

### Phase 2: Scan for Smell Candidates

These scans produce **candidates only** — each match requires manual validation in Phase 3–5 before it becomes a
finding. Expect a high false-positive rate from regex heuristics; the value is in surfacing locations to inspect.

For diff/path mode, append the resolved file list (`$SCOPE`) to each `rg` command. For codebase mode, omit it.

```bash
EXCLUDE='--glob !**/*_test.py --glob !**/test_*.py --glob !**/tests/** --glob !**/venv/** --glob !**/.venv/** --glob !**/dist/** --glob !**/__pycache__/**'

# Feature envy: methods that heavily reference another module's types
# (look for obj.attr.attr patterns across module boundaries — verify manually)
rg --pcre2 '\b[a-z]\w+\.[a-z]\w+\.[a-z]\w+' --type py $EXCLUDE -- $SCOPE

# Data clumps: repeated parameter groups (functions with 4+ params)
rg --pcre2 'def\s+\w+\s*\([^)]{100,}\)' --type py $EXCLUDE -- $SCOPE

# Temporal coupling: init/setup/configure methods
rg --pcre2 '(init|setup|configure|prepare)\s*\(' --type py $EXCLUDE -- $SCOPE

# Mutable default arguments
rg --pcre2 'def\s+\w+\s*\([^)]*=\s*(\[\]|\{\}|set\(\))' --type py $EXCLUDE -- $SCOPE

# God modules (large files)
find . -name '*.py' -not -path '*/venv/*' -not -path '*/.venv/*' -exec wc -l {} + | sort -rn | head -20

# Classes (then evaluate for class abuse)
rg 'class\s+\w+' --type py $EXCLUDE -- $SCOPE

# Singleton pattern
rg '__new__\s*\(|_instance' --type py $EXCLUDE -- $SCOPE

# Comments as deodorant: multi-line comment blocks before code (inspect for "what" vs "why")
rg -B1 -A1 '^\s*# ' --type py $EXCLUDE -- $SCOPE | head -200

# Shotgun surgery: per-commit co-occurrence (see Phase 4)
```

### Phase 3: Evaluate Feature Envy and Data Clumps

For each function with cross-module data access:
- Does it access more attributes/methods from another type than from its own scope?
- Would moving it to the other module improve cohesion?

For each function with 4+ parameters:
- Do the same parameters appear together in other function signatures?
- Is there a domain concept these parameters represent?

### Phase 4: Evaluate Shotgun Surgery

Shotgun surgery is detected through **per-commit co-change analysis**, not raw file churn. High churn on a single file
is not shotgun surgery — the signal is many *unrelated* files changing together for a single logical change.

```bash
# Per-commit file sets: show which files change together in each commit
git log --pretty=format:'--- %h %s' --name-only -30 | head -200

# Directory co-occurrence: for each commit, list distinct directories touched
git log --pretty=format:'COMMIT' --name-only -50 | awk '
  /^COMMIT/ { if (NR>1) { for (d in dirs) printf "%s ", d; print "" } delete dirs; next }
  /\// { sub(/\/[^\/]*$/, ""); dirs[$0]=1 }
' | sort | uniq -c | sort -rn | head -20
```

For each commit that touches 4+ directories, ask: was this a single logical change scattered across unrelated modules,
or a legitimate cross-cutting concern? Look for patterns: the same directory set appearing in multiple commits
suggests structural coupling.

### Phase 5: Evaluate Python-Specific Smells

For each class:
- Does it have state? Does it have more than one public method?
- Could it be a plain function, module, or dataclass?
- Is it a singleton?

For each mutable default argument:
- Is it actually mutated?
- Could it cause surprising state persistence?

For each god module:
- How many unrelated responsibilities does it contain?
- Can it be split by domain concept?

### Phase 6: Produce Report

## Output Format

Save as `YYYY-MM-DD-smell-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs folder
exists).

```md
# Smell Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Findings

### Feature Envy

| # | Location | Function | Envied Type | Own Data Used | Foreign Data Used | Evidence | Action |
| - | -------- | -------- | ----------- | ------------- | ----------------- | -------- | ------ |
| 1 | file:line | `format_order()` | `billing.Invoice` | 0 attributes | 5 attributes | `inv.total + inv.tax...` | Move to billing module |

### Data Clumps

| # | Locations | Parameters/Attributes | Evidence | Suggested Type | Action |
| - | --------- | -------------------- | -------- | -------------- | ------ |
| 1 | file:line, file:line, file:line | `host, port, scheme` | 3 func signatures | `Endpoint` dataclass | Extract type |

### Shotgun Surgery

| # | Concept | Files Touched | Modules Touched | Action |
| - | ------- | ------------- | --------------- | ------ |
| 1 | "Add new payment method" | 8 files | 5 modules | Consolidate payment logic |

### Temporal Coupling

| # | Location | Class/Object | Required Order | Action |
| - | -------- | ------------ | -------------- | ------ |
| 1 | file:line | `Server` | `init()` → `start()` | Require deps in `__init__` |

### Comments as Deodorant

| # | Location | Comment | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `# Parse and validate the user input` | Extract `parse_and_validate_input()` |

### Temporary Field

| # | Location | Type | Attribute | Used In | Action |
| - | -------- | ---- | --------- | ------- | ------ |
| 1 | file:line | `Processor` | `last_result` | `process()` only | Use separate dataclass or local var |

### God Module

| # | Location | Module | Lines | Responsibilities | Action |
| - | -------- | ------ | ----- | ---------------- | ------ |
| 1 | file.py | `utils.py` | 800 | string ops + date ops + I/O helpers | Split by domain |

### Mutable Default Arguments

| # | Location | Function | Default | Risk | Action |
| - | -------- | -------- | ------- | ---- | ------ |
| 1 | file:line | `add_item(items=[])` | `[]` | State persistence between calls | Use `None` sentinel |

### Class Abuse

| # | Location | Class | Methods | State | Action |
| - | -------- | ----- | ------- | ----- | ------ |
| 1 | file:line | `UserService` | 1 public | none | Replace with exported function |

## Recommendations (Priority Order)

1. **Must-fix**: {mutable default args, data clumps with 5+ occurrences, feature envy in critical paths}
2. **Should-fix**: {feature envy, shotgun surgery patterns, god modules, temporal coupling}
3. **Consider**: {class abuse, comments as deodorant, temporary fields}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: classic code smells and Python-specific antipatterns only.** Do not flag SOLID violations
  (→ solid-hunter-py), type design debt or primitive obsession (→ type-hunter-py), module boundary issues
  (→ boundary-hunter-py), invariant enforcement (→ invariant-hunter-py), structural complexity
  (→ simplicity-hunter-py), missing documentation (→ doc-hunter-py), security (→ security-hunter-py), test quality
  (→ test-hunter-py), or AI-generated noise (→ slop-hunter-py). If a finding is better described as a SOLID principle
  violation, type design issue, or boundary problem, defer to the specialized hunter.
- **Evidence required.** Every finding must cite `file/path.py:line` with the exact code.
- **Context matters.** A smell in a prototype is less urgent than a smell in a payment system. Assess severity
  relative to the code's criticality and change frequency.
- **Pragmatism.** Not every smell requires action. A data clump that appears twice may not justify a new type.
  Feature envy in a utility function may be intentional. Report the smell, assess the cost/benefit, and let the
  team decide.
- **Respect Python idioms.** Python's duck typing, module system, and dynamic features are its strengths. Calibrate
  to Python conventions, not patterns from Java, C#, or TypeScript.
- **Handoff, not duplication.** Smells often have root causes owned by other hunters. Smell-hunter owns the
  *symptom detection* (e.g., "these 8 files always change together"); the root-cause fix may belong to
  boundary-hunter (dependency direction), solid-hunter (SRP), or simplicity-hunter (mixed concerns). When a finding
  clearly belongs to another hunter's domain, note it as a cross-reference in the report and do not duplicate the
  analysis. When the smell is the primary signal and no other hunter covers the detection method, own the finding.
- **Assess refactoring risk briefly.** Actions are recommendations, not commands — implementation is a separate step.
  When a recommendation would affect exported API surface, serialization behavior, or framework constraints (e.g.,
  Django model structure, SQLAlchemy mappings), note the risk in the Action column.
