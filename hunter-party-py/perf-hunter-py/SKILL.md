---
name: perf-hunter-py
description: |
  Audit Python code for performance antipatterns and resource management issues — blocking I/O
  in async contexts, sequential awaits, N+1 queries, unclosed resources, unbounded caches,
  eager materialization, missing connection pooling, and expensive operations in hot paths.

  Use when: reviewing async correctness, auditing resource lifecycle, hunting N+1 query
  patterns, checking connection pool configuration, or profiling structurally inefficient code.
disable-model-invocation: true  
---

# Perf Hunter

Audit Python code for **performance antipatterns and resource management** — places where I/O blocks the event loop,
independent operations run sequentially instead of concurrently, queries multiply inside loops, resources leak without
cleanup, caches grow without bound, or expensive work sits in hot paths. The goal: **every async function is truly
non-blocking, every resource has a bounded lifecycle, and every data access pattern scales with the workload.**

## When to Use

- Reviewing async code for correctness (blocking I/O, sequential awaits)
- Auditing resource lifecycle (unclosed files, connections, sessions)
- Hunting N+1 query patterns in ORM-heavy code
- Checking connection pool and client reuse configuration
- Reviewing code for unbounded in-memory growth before production deployment
- Profiling structurally inefficient patterns in request handlers or hot paths

## Core Principles

1. **Async means non-blocking.** An `async def` that calls blocking I/O is worse than sync — it blocks the entire
   event loop, stalling all concurrent coroutines. Every I/O operation inside an async function must use an async API.

2. **Concurrency is the point.** Independent async operations should run concurrently. Sequential `await` on
   independent calls wastes the concurrency that async provides.

3. **Batch over loop.** One query returning N results is almost always faster than N queries returning 1 result each.
   The network round-trip dominates, not the query complexity.

4. **Resources must be bounded.** Every cache needs eviction, every pool needs a size limit, every buffer needs
   backpressure. Unbounded growth is a slow memory leak that only manifests under production load.

5. **Lazy over eager.** Don't materialize a million-item list to iterate over it once. Generators, iterators, and
   streaming APIs exist for a reason — use them for large datasets.

6. **Pool and reuse.** Creating connections, clients, and sessions is expensive. Pool them at the application level
   and reuse across requests.

7. **Profile before optimizing.** Not every hot path needs optimization. Flag patterns that are *structurally*
   inefficient (N+1, blocking I/O in async, unbounded caches) rather than speculating about micro-performance.

### Canonical Exceptions

Not every finding requires action. Document these but do not flag as "must-fix":

| Pattern | When Acceptable |
| ------- | --------------- |
| Blocking I/O in `async def` | Wrapped in `asyncio.to_thread()` or `run_in_executor()` |
| Sequential awaits | When call B depends on result of call A |
| `list()` materialization | When random access, `len()`, or multiple iterations are needed |
| Per-request client creation | One-off scripts, CLIs, or test utilities |
| `@lru_cache(maxsize=None)` | Pure functions with bounded input domains (e.g., enum→string mapping) |
| Module-level mutable state | Application registries populated once at startup |

## What to Hunt

### 1. Blocking I/O in Async Context

Synchronous I/O calls inside `async def` functions that block the event loop, defeating the purpose of async.

**Signals:**

- `open()` inside `async def`
- `requests.get()` / `requests.post()` inside `async def`
- `time.sleep()` inside `async def` (should be `asyncio.sleep()`)
- Synchronous database calls (`cursor.execute()`) inside `async def`
- `subprocess.run()` inside `async def` (should be `asyncio.create_subprocess_exec()`)

**Action:** Replace with async equivalents: `aiofiles.open()`, `httpx.AsyncClient`, `asyncio.sleep()`, async database
drivers, `asyncio.create_subprocess_exec()`. If no async equivalent exists, use `asyncio.to_thread()` or
`loop.run_in_executor()`.

### 2. Sequential Awaits Where Gather Would Work

Multiple independent `await` calls made sequentially when they could run concurrently with `asyncio.gather()` or
`asyncio.TaskGroup`.

**Signals:**

- Two or more consecutive `await` calls where neither depends on the result of the other:
  `a = await fetch_a(); b = await fetch_b(); c = await fetch_c()`
- Especially when the fetched data is used only after all calls complete

**Action:** Use `asyncio.gather()` or `asyncio.TaskGroup` (3.11+) for independent async operations. Keep sequential
for dependent calls.

### 3. N+1 Query Patterns

Code that issues one database query per item in a loop instead of a single batch query.

**Signals:**

- `for item in items: await repo.find_by_id(item.id)` — loop with individual queries
- `for user in users: user.orders = await get_orders(user.id)` — lazy loading in a loop
- ORM attribute access in a loop that triggers individual SELECT statements
- `SELECT ... WHERE id = ?` called N times in a loop instead of `SELECT ... WHERE id IN (?)`

**Action:** Replace with batch queries (`WHERE id IN (...)`), use ORM eager loading (`joinedload`, `selectinload` in
SQLAlchemy), or prefetch related data before the loop.

### 4. Unclosed Resources

Files, connections, sessions, or client objects opened without proper cleanup, risking resource leaks.

**Signals:**

- `f = open(...)` without `with` statement
- `session = Session()` without context manager
- `client = httpx.AsyncClient()` without `async with`
- `conn = await pool.acquire()` without `try/finally` or context manager
- `tempfile.NamedTemporaryFile(delete=False)` without cleanup logic
- Database connections opened in function scope and not returned to pool

**Action:** Wrap in context managers (`with`/`async with`). For resources that span scopes, use
`contextlib.AsyncExitStack` or register cleanup in `finally` / `atexit`.

### 5. Unbounded In-Memory Growth

Collections that grow without limit: caches without eviction, lists that accumulate indefinitely, or queues without
backpressure.

**Signals:**

- `cache = {}` populated in a function called repeatedly with no eviction
- `results = []` appending in an infinite loop or long-running server
- `@lru_cache` without `maxsize` (defaults to 128, but `@lru_cache(maxsize=None)` is explicitly unbounded)
- Module-level mutable collections that only grow
- `deque()` without `maxlen` used as a buffer

**Action:** Use `@lru_cache(maxsize=N)` or `cachetools.TTLCache` with TTL and size limits. For buffers, use
`collections.deque(maxlen=N)`. For event logs, use rotation. Prefer weak references
(`weakref.WeakValueDictionary`) when caching objects.

### 6. Eager Materialization of Large Sequences

List comprehensions or `list()` calls that materialize large datasets into memory when a generator or iterator would
suffice.

**Signals:**

- `list(range(1_000_000))`
- `[x for x in huge_query_result]` followed by iteration
- `data = list(reader)` when processing line-by-line would work
- `sorted(huge_list)` on data only partially consumed
- `readlines()` instead of iterating the file object directly

**Action:** Use generator expressions `(x for x in ...)`, iterate directly over iterables, use `itertools.islice()`
for partial consumption, process files line-by-line with `for line in f:`.

### 7. Missing Connection Pool Configuration

Database or HTTP connections created per-request without pooling, or pool defaults that are too small/large.

**Signals:**

- `create_engine()` without `pool_size`, `pool_pre_ping`, or `pool_recycle` args
- New `httpx.Client()` or `requests.Session()` created inside request handlers (per-request)
- `aiohttp.ClientSession()` created inside a loop
- Direct `psycopg2.connect()` or `asyncpg.connect()` without pool wrapper
- No `pool_size` or `max_overflow` tuning for SQLAlchemy engines

**Action:** Use connection pooling (`create_async_engine(pool_size=N, max_overflow=M)`). Reuse HTTP clients as
application-scoped singletons. Use `asyncpg.create_pool()` instead of individual connections.

### 8. Expensive Operations in Hot Paths

Computationally expensive or I/O operations placed inside tight loops, request handlers, or frequently-called functions
without caching or batching.

**Signals:**

- `re.compile()` inside a function called in a loop (should be module-level constant)
- `json.loads()`/`json.dumps()` on the same data multiple times
- Repeated `os.path.exists()` / `Path.exists()` checks on the same path in one request
- `importlib.import_module()` in a hot path
- Repeated string concatenation in a loop instead of `str.join()` or `io.StringIO`

**Action:** Hoist expensive operations out of loops. Pre-compile regexes at module level. Cache expensive computations
with appropriate TTL. Use batching for I/O operations.

## Audit Workflow

### Phase 1: Identify Async Architecture

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
2. Determine if the project uses async (FastAPI, aiohttp, asyncio) or sync (Flask, Django sync), and identify the
   runtime.
3. Note async I/O libraries in use (httpx, aiofiles, asyncpg, etc.).

### Phase 2: Scan for Performance Signals

```bash
EXCLUDE='--glob !**/*_test.py --glob !**/test_*.py --glob !**/tests/** --glob !**/venv/** --glob !**/.venv/**'

# Blocking I/O in async context
rg 'async def' --type py $EXCLUDE -l | head -20
rg --pcre2 'async def[\s\S]*?(?:open\(|requests\.|time\.sleep|subprocess\.run)' --type py $EXCLUDE
rg 'requests\.(get|post|put|delete|patch)\(' --type py $EXCLUDE
rg 'time\.sleep\(' --type py $EXCLUDE

# Sequential awaits
rg -U 'await.*\n\s*\w+\s*=\s*await' --type py $EXCLUDE

# N+1 patterns (loop with await/query inside)
rg -U 'for\s+\w+\s+in\s+\w+.*:\s*\n\s*.*await' --type py $EXCLUDE
rg -U 'for\s+\w+\s+in\s+\w+.*:\s*\n\s*.*\.execute\(' --type py $EXCLUDE

# Unclosed resources
rg --pcre2 '(?<!with\s)\bopen\(' --type py $EXCLUDE
rg 'Client\(\)' --type py $EXCLUDE
rg 'Session\(\)' --type py $EXCLUDE

# Unbounded caches
rg 'lru_cache\(maxsize=None\)|@lru_cache\s*$' --type py $EXCLUDE
rg --pcre2 'cache\s*[:=]\s*\{\}' --type py $EXCLUDE

# Eager materialization
rg 'readlines\(\)' --type py $EXCLUDE
rg 'list(range\(' --type py $EXCLUDE

# Connection pool configuration
rg 'create_engine\(|create_async_engine\(' --type py $EXCLUDE
rg 'pool_size|pool_pre_ping|max_overflow' --type py $EXCLUDE

# Hot path operations
rg 're\.compile\(' --type py $EXCLUDE
```

### Phase 3: Evaluate Async Correctness

For each async function identified in Phase 2:

1. Check all I/O calls for async equivalents.
2. Identify sequential awaits that could be gathered.
3. Verify `asyncio.to_thread()` or `run_in_executor()` wrapping for unavoidable blocking calls.

### Phase 4: Evaluate Resource Lifecycle

For each opened resource:

1. Verify cleanup path — context manager, `try/finally`, or `atexit`.
2. Check that connections are returned to pools.
3. Identify resources that span scopes without explicit lifecycle management.

### Phase 5: Evaluate Data Access Patterns

1. Check for N+1 patterns in loops that issue queries.
2. Verify ORM eager loading where lazy loading would cause N+1.
3. Check for missing batching opportunities.

### Phase 6: Produce Report

## Output Format

Save as `YYYY-MM-DD-perf-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs
folder exists).

```md
# Perf Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Runtime: {async (FastAPI/aiohttp) / sync (Flask/Django) / mixed}
- Exclusions: {list}

## Async Architecture

- Framework: {FastAPI / aiohttp / Django async / Flask / sync-only}
- Event loop: {uvloop / default asyncio / N/A}
- Async I/O libraries: {httpx / aiofiles / asyncpg / etc.}

## Findings

### Blocking I/O in Async Context

| # | Location | Blocking Call | Async Equivalent | Severity |
| - | -------- | ------------- | ---------------- | -------- |
| 1 | file:line | `requests.get()` in `async def` | `httpx.AsyncClient.get()` | High |

### Sequential Awaits

| # | Location | Calls | Independent? | Estimated Speedup | Action |
| - | -------- | ----- | ------------ | ------------------ | ------ |
| 1 | file:line | `fetch_a`, `fetch_b`, `fetch_c` | Yes | ~3x | Use `asyncio.gather()` |

### N+1 Query Patterns

| # | Location | Loop | Query per Iteration | Batch Alternative |
| - | -------- | ---- | ------------------- | ----------------- |
| 1 | file:line | `for user in users` | `get_orders(user.id)` | `get_orders_batch(user_ids)` |

### Unclosed Resources

| # | Location | Resource | Cleanup | Action |
| - | -------- | -------- | ------- | ------ |
| 1 | file:line | `open()` | No `with` | Wrap in context manager |

### Unbounded In-Memory Growth

| # | Location | Collection | Growth Pattern | Action |
| - | -------- | ---------- | -------------- | ------ |
| 1 | file:line | `cache = {}` | Module-level dict, never evicted | Use `TTLCache(maxsize=1000, ttl=300)` |

### Eager Materialization

| # | Location | Operation | Data Size | Action |
| - | -------- | --------- | --------- | ------ |
| 1 | file:line | `list(reader)` | Unbounded file | Iterate directly |

### Missing Connection Pool Configuration

| # | Location | Client/Engine | Issue | Action |
| - | -------- | ------------- | ----- | ------ |
| 1 | file:line | `create_async_engine()` | No `pool_size` | Add `pool_size=5, max_overflow=10` |

### Expensive Operations in Hot Paths

| # | Location | Operation | Frequency | Action |
| - | -------- | --------- | --------- | ------ |
| 1 | file:line | `re.compile()` in loop | Per-request | Hoist to module level |

## Recommendations (Priority Order)

1. **Must-fix**: {blocking I/O in async, N+1 in critical paths, unclosed resources, unbounded caches in production}
2. **Should-fix**: {sequential awaits, missing pool configuration, eager materialization of large datasets}
3. **Consider**: {hot path optimizations, generator conversions for moderate datasets}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: performance and resource management only.** Do not flag type invariants (→ invariant-hunter-py), type design
  (→ type-hunter-py), structural complexity (→ simplicity-hunter-py), module boundary issues (→ boundary-hunter-py),
  class/interface design (→ solid-hunter-py), missing documentation (→ doc-hunter-py), security
  (→ security-hunter-py), test quality (→ test-hunter-py), or cosmetic style (→ slop-hunter-py). If a finding doesn't
  answer "does this code waste resources or block unnecessarily?", it doesn't belong here.
- **Boundary with simplicity-hunter**: simplicity-hunter flags unnecessary abstractions and dead code from a structural
  perspective. Perf-hunter flags patterns that are structurally correct but operationally wasteful (blocking I/O, N+1,
  unbounded caches). If the code is over-engineered, it's simplicity. If it's under-optimized, it's perf.
- **Evidence required.** Every finding must cite `file/path.py:line` with the exact code.
- **Structural, not speculative.** Flag patterns that are *structurally* inefficient (proven antipatterns like N+1,
  blocking I/O in async), not micro-optimizations based on speculation. Don't flag `list comprehension vs generator`
  for small bounded datasets.
- **Runtime awareness.** Some patterns only matter in async contexts (blocking I/O, sequential awaits). Note the
  runtime context and don't flag sync-only issues as async problems.
