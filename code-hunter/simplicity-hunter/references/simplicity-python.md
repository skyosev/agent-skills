# Simplicity Hunter — Python reference

Language-specific rules for Python.

## Generated-code eligibility

A file is generated (ineligible for reporting) only when identified by an authoritative in-file marker **where Python
defines one** — never by filename guessing. Vendored trees (`venv/`, `.venv/`, `dist/`, `__pycache__/`, `*.egg-info/`),
lockfiles, and Markdown-only inputs are also ineligible.

## Reinvented Primitives

**Version source:** `requires-python`, CI matrix, or runtime.

| Primitive | Toolchain gate |
| --------- | -------------- |
| `functools.cache` | Python 3.9+ |
| `functools.lru_cache` | stdlib (note hashability / concurrency / eviction semantics) |
| `itertools`, `collections.Counter`, `collections.defaultdict`, `pathlib` | stdlib |
| `contextlib` helpers (`contextmanager`, `ExitStack`, `closing`, `suppress`, `nullcontext`) | stdlib |

**Signals:** loops replicating `itertools` / `Counter` / `defaultdict` / `pathlib`; manual context management that
`contextlib` already covers; re-rolled memoization that is an exact substitute for `functools.lru_cache` /
`functools.cache`.

Exact semantic parity includes designed-in differences: `functools.lru_cache` imposes hashability and carries
concurrency, eviction, and repeated-concurrent-call semantics.

## Dead-code liveness channels

Beyond call sites: reflection/`getattr`, DI registration, registries, entry-point configuration, `__all__`, and
packaging entry points (`pyproject.toml` / `setup.cfg` `console_scripts` / `entry_points`). Cite channels relevant to
*this* symbol.

## Unnecessary Abstractions — Python signals

In addition to the shared signals: an ABC/Protocol with a single implementation and no plan for more — *unless* the
Protocol exists to enable test doubles, define a DI boundary, or stabilize a real architectural seam; a decorator that
does nothing beyond calling the wrapped function.

## Complex Control Flow — Python signals

In addition to the shared signals: nested conditional expressions (`a if b else (c if d else e)`); complex
comprehensions with multiple `if` clauses and nested loops.

## Coexisting Generations — false positives and Phase 4

**Excluded as false positives:**

- `unittest` + `pytest` — `unittest` is standard library, and pytest officially runs `unittest` suites to support
  incremental adoption
- `pydantic` v1 + v2 — `pydantic.v1` is an officially supported migration namespace within V2

Multiple HTTP packages may legitimately differ by ownership, protocol, sync/async role, or transitive origin —
coexistence alone is a candidate, never a finding.

**Nomination signals:** overlapping HTTP or serialization dependencies in `pyproject.toml` / `requirements*.txt`;
`warnings.warn(..., DeprecationWarning)` or `@deprecated` on symbols with live importers; `legacy/` / `old/` packages
whose older path still has importers; duplicate role classes all still constructed somewhere; environment- or
config-selected parallel implementations where both branches are reachable.

### Phase 4 scans

```bash
# 1. Read pyproject.toml and requirements*.txt; list overlapping-concern dependencies.
#    Coexistence alone is never a finding (see false positives above).

# 2. Generation-named symbols and paths
rg -l --type py 'Legacy|Deprecated|V1|V2|_v1|_v2' \
  --glob '!**/venv/**' --glob '!**/.venv/**' --glob '!**/dist/**' .
find . -type d \( -name 'v[0-9]*' -o -name legacy -o -name old -o -name new \) \
  -not -path '*/venv/*' -not -path '*/.venv/*' -not -path './dist/*'

# 3. Deprecation markers
rg -n --type py 'DeprecationWarning|@deprecated|warnings\.warn' \
  --glob '!**/venv/**' --glob '!**/.venv/**' --glob '!**/dist/**' .
```

Confirm liveness for every candidate stratum. Capability and project intent decide the survivor;
`git log -1 --format=%as -- <path>` and recent call-site choice nominate only.

## Evidence path form

Cite findings as `file/path.py:line`.

## Phase 2 — complexity scans

Test files are included (complexity in tests is in scope). Duplication excludes them — see Phase 3 exclude below.
Pass an explicit path to every `rg` invocation.

```bash
EXCLUDE='--glob !**/venv/** --glob !**/.venv/** --glob !**/dist/** --glob !**/__pycache__/** --glob !**/*.egg-info/**'

# Deep nesting (4+ indentation levels, 4-space indent)
rg '^\s{16,}\S' --type py $EXCLUDE -- $SCOPE

# Boolean parameters
rg --pcre2 '\w+\s*:\s*bool\b' --type py $EXCLUDE -- $SCOPE

# Functions with many parameters
rg --pcre2 'def\s+\w+\s*\([^)]{80,}\)' --type py $EXCLUDE -- $SCOPE

# **kwargs catch-all
rg '\*\*kwargs' --type py $EXCLUDE -- $SCOPE

# Nested conditional expressions
rg --pcre2 'if\s+.*\s+else\s+.*\s+if\s+' --type py $EXCLUDE -- $SCOPE

# Long functions (files with significant line spans between def statements)
rg 'def\s+\w+' --type py $EXCLUDE -n -- $SCOPE

# Reinvented-primitive candidates
rg --pcre2 'for\s+\w+\s+in\s+.+:\s*$' --type py $EXCLUDE -- $SCOPE
rg 'functools\.lru_cache|@lru_cache|@cache\b' --type py $EXCLUDE -- $SCOPE
```

## Phase 3 — Duplication exclude

```bash
DUP_EXCLUDE="$EXCLUDE --glob '!**/test_*.py' --glob '!**/*_test.py' --glob '!**/tests/**' --glob '!**/conftest.py'"
# Run duplication searches with $DUP_EXCLUDE so test-code duplication stays with test-hunter.
```
