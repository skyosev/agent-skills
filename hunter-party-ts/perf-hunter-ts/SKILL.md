---
name: perf-hunter-ts
description: |
  Audit TypeScript/Node.js code for performance antipatterns and resource management issues —
  event loop blocking, sequential awaits, N+1 queries, unclosed resources, unbounded caches,
  eager materialization, missing connection pooling, and expensive operations in hot paths.

  Use when: reviewing async correctness, auditing resource lifecycle, hunting N+1 query
  patterns, checking connection pool configuration, or profiling structurally inefficient code.
---

# Perf Hunter

Audit TypeScript/Node.js code for **performance antipatterns and resource management** — places where I/O blocks the
event loop, independent operations run sequentially instead of concurrently, queries multiply inside loops, resources
leak without cleanup, caches grow without bound, or expensive work sits in hot paths. The goal: **every async function
is truly non-blocking, every resource has a bounded lifecycle, and every data access pattern scales with the workload.**

## When to Use

- Reviewing async code for correctness (event loop blocking, sequential awaits)
- Auditing resource lifecycle (unclosed files, connections, streams, database clients)
- Hunting N+1 query patterns in ORM-heavy code (Prisma, TypeORM, Drizzle, MikroORM)
- Checking connection pool and client reuse configuration
- Reviewing code for unbounded in-memory growth before production deployment
- Profiling structurally inefficient patterns in request handlers or hot paths
- Evaluating streaming vs eager data loading for large datasets

## Core Principles

1. **The event loop is sacred.** Node.js runs on a single-threaded event loop. A synchronous CPU-intensive operation
   or blocking I/O call in a request handler stalls *all* concurrent requests. Every I/O operation inside a request
   path must be non-blocking.

2. **Concurrency is the point.** Independent async operations should run concurrently. Sequential `await` on
   independent calls wastes the concurrency that async provides. Use `Promise.all()`, `Promise.allSettled()`, or
   `Promise.race()` for independent operations.

3. **Batch over loop.** One query returning N results is almost always faster than N queries returning 1 result each.
   The network round-trip dominates, not the query complexity.

4. **Resources must be bounded.** Every cache needs eviction, every pool needs a size limit, every buffer needs
   backpressure. Unbounded growth is a slow memory leak that only manifests under production load.

5. **Stream over buffer.** Don't load a million-row result set into an array to iterate over it once. Node.js streams,
   async iterators, and database cursors exist for a reason — use them for large datasets.

6. **Pool and reuse.** Creating connections, HTTP clients, and database clients is expensive. Pool them at the
   application level and reuse across requests.

7. **Profile before optimizing.** Not every hot path needs optimization. Flag patterns that are *structurally*
   inefficient (N+1, blocking I/O, unbounded caches) rather than speculating about micro-performance.

### Canonical Exceptions

Not every finding requires action. Document these but do not flag as "must-fix":

| Pattern | When Acceptable |
| ------- | --------------- |
| Sync `fs` operations at startup | `readFileSync` in module init or config loading (not in request path) |
| Sequential awaits | When call B depends on result of call A |
| `Array.from()` materialization | When random access, `.length`, or multiple iterations are needed |
| Per-request client creation | One-off scripts, CLIs, or test utilities |
| Unbounded `Map` at module level | Registries populated once at startup with bounded key space |
| `JSON.parse()` per request | Normal request body parsing — not a hot path concern |
| `crypto.randomUUID()` | Fast enough for request-level IDs |

## What to Hunt

### 1. Event Loop Blocking

Synchronous I/O or CPU-intensive operations in request handlers, middleware, or any async context that block the
event loop.

**Signals:**

- `fs.readFileSync()`, `fs.writeFileSync()`, `fs.existsSync()` in request-handling code (not startup)
- `child_process.execSync()` or `child_process.spawnSync()` in async context
- CPU-intensive operations without offloading: large JSON parsing, image processing, cryptographic operations (non-
  streaming), complex regex on large strings
- `while` loops polling a condition synchronously
- `Array.sort()` or `Array.filter()` on very large arrays (10K+ items) in request handlers
- Synchronous `require()` calls in hot paths (dynamic imports in request handlers)

**Action:** Replace with async equivalents: `fs.promises.readFile()`, `child_process.exec()` (promisified),
`crypto.subtle` for web crypto, `worker_threads` for CPU-bound work. For unavoidable sync operations, offload to
a worker thread via `worker_threads` or `piscina`.

### 2. Sequential Awaits Where Promise.all Would Work

Multiple independent `await` calls made sequentially when they could run concurrently.

**Signals:**

- Two or more consecutive `await` calls where neither depends on the result of the other:
  ```typescript
  const a = await fetchA();
  const b = await fetchB();
  const c = await fetchC();
  ```
- Especially when the fetched data is used only after all calls complete
- `for...of` loops with `await` inside where iterations are independent
- Sequential database queries that could be parallelized

**Action:** Use `Promise.all()` or `Promise.allSettled()` for independent async operations:
```typescript
const [a, b, c] = await Promise.all([fetchA(), fetchB(), fetchC()]);
```
Use `Promise.allSettled()` when partial failure should not reject the aggregate. Keep sequential for dependent calls.

### 3. N+1 Query Patterns

Code that issues one database query per item in a loop instead of a single batch query.

**Signals:**

- `for (const item of items) { await repo.findById(item.id) }` — loop with individual queries
- `for (const user of users) { user.orders = await getOrders(user.id) }` — lazy loading in a loop
- Prisma: `findUnique()` inside a loop instead of `findMany({ where: { id: { in: ids } } })`
- TypeORM: individual `.findOneBy()` calls in a loop instead of `.findBy({ id: In(ids) })`
- GraphQL resolvers that issue one query per field resolution (dataloader missing)
- `.map()` with `async` callback + `Promise.all()` wrapping individual queries (still N queries, just concurrent)

**Action:** Replace with batch queries (`WHERE id IN (...)`), use ORM eager loading (Prisma `include`, TypeORM
`relations`, MikroORM `populate`), or implement a DataLoader pattern for GraphQL. Note: `Promise.all(items.map(i =>
query(i)))` reduces latency but still issues N queries — batch is preferred.

### 4. Unclosed Resources

Files, connections, streams, or client objects opened without proper cleanup, risking resource leaks under error
conditions.

**Signals:**

- `fs.createReadStream()` without `.destroy()` or `pipeline()` error handling
- `new AbortController()` created but never `.abort()`-ed on cleanup
- Database connections acquired manually (`pool.connect()`) without `try/finally` or `using`
- `fetch()` responses where `.body` is not consumed or cancelled (keeps connection open)
- Event listeners added without corresponding `removeListener()` or `AbortSignal` cleanup
- `setInterval()` / `setTimeout()` without `clearInterval()` / `clearTimeout()` on cleanup
- HTTP servers or database clients created in tests without `close()` in `afterAll`

**Action:** Use `try/finally`, `using` (TC39 Explicit Resource Management), `stream.pipeline()`, or `AbortController`
for cleanup. For resources that span scopes, register cleanup in shutdown handlers. Prefer `using` declarations where
supported by the runtime.

### 5. Unbounded In-Memory Growth

Collections that grow without limit: Maps used as caches without eviction, arrays that accumulate indefinitely, or
queues without backpressure.

**Signals:**

- `const cache = new Map<string, T>()` populated in a function called per-request with no eviction
- Module-level `Map` or `Set` that only grows (`.set()` / `.add()` without `.delete()`)
- Arrays used as event logs or buffers that `.push()` indefinitely
- `WeakRef` or `FinalizationRegistry` misuse (not actually preventing accumulation)
- LRU cache without size limit
- In-memory session stores without TTL

**Action:** Use bounded caches with TTL (e.g., `lru-cache`, `@isaacs/ttlcache`, or `Map` with periodic eviction).
For buffers, enforce a maximum size with backpressure. For event logs, use rotation or external storage. Use
`WeakMap` / `WeakRef` when caching objects that should be GC'd when the key is.

### 6. Eager Materialization of Large Datasets

Loading entire result sets or files into memory as arrays when streaming or incremental processing would suffice.

**Signals:**

- `const rows = await db.query("SELECT * FROM large_table")` loading unbounded result sets
- `const content = await fs.readFile(path, 'utf-8')` on files that could be multi-MB
- `Array.from(asyncIterable)` or `for await` collecting into an array
- `.toArray()` on database cursors before processing
- `JSON.parse(await readFile(largePath))` loading large JSON into memory
- `response.json()` on API responses with unbounded array payloads

**Action:** Use database cursors, `LIMIT`/`OFFSET` pagination, or streaming queries. Use `fs.createReadStream()`
with line-by-line processing. Use async iterators and process items incrementally. For JSON, consider streaming
parsers (`JSONStream`, `stream-json`).

### 7. Missing Connection Pool Configuration

Database or HTTP connections created per-request without pooling, or pool defaults that are too small/large for
the workload.

**Signals:**

- `new PrismaClient()` created inside request handlers instead of shared application-level instance
- `new Pool()` (pg) without `max`, `idleTimeoutMillis`, or `connectionTimeoutMillis` configuration
- `createConnection()` (TypeORM) called per-request instead of using a shared connection pool
- `fetch()` or `axios.create()` creating new instances per request (HTTP keep-alive not reused)
- `new Redis()` (ioredis) per request instead of shared client
- No pool configuration tuning (relying on library defaults without understanding workload needs)

**Action:** Share database clients / pools at application scope (singleton or DI). Configure pool limits:
`max` connections, idle timeout, connection timeout. Reuse HTTP clients across requests (keep-alive). Use
a single Redis client instance shared across the application.

### 8. Expensive Operations in Hot Paths

Computationally expensive or I/O operations placed inside tight loops, request handlers, or frequently-called
functions without caching or batching.

**Signals:**

- `new RegExp(pattern)` inside a function called per-request (should be module-level constant)
- `JSON.parse()` / `JSON.stringify()` on the same data multiple times within one request
- `path.resolve()` or `path.join()` with `process.cwd()` called repeatedly (should be cached)
- Dynamic `import()` in a hot path (should be top-level import or cached)
- `crypto.pbkdf2Sync()` or other expensive crypto in request thread (use async variant or worker)
- Repeated file system stats on the same path within one request
- String concatenation in a loop building large strings (use array + `.join()`)
- `Date.now()` / `new Date()` called many times where a single timestamp per request suffices

**Action:** Hoist expensive operations out of loops. Pre-compile regexes at module level. Cache expensive
computations with appropriate TTL. Use batching for I/O operations. Offload CPU-intensive crypto to worker threads
or async APIs.

### 9. Memory Leak Patterns

Event listener accumulation, closure captures, and reference retention that prevent garbage collection.

**Signals:**

- `emitter.on('event', handler)` without corresponding `off()` — especially in request handlers or class instances
  that are created/destroyed frequently
- `EventEmitter` `MaxListenersExceededWarning` suppressed with `setMaxListeners(0)` instead of fixing the leak
- Closures capturing large objects (request context, database results) in long-lived callbacks
- Global `Map` keyed by request-specific identifiers without cleanup
- `setInterval()` registered in constructors without cleanup in destructors
- Promises that never resolve/reject, holding references indefinitely

**Action:** Always pair `on()` with `off()` or use `{ once: true }`. Use `AbortSignal` for listener lifecycle.
Avoid capturing request-scoped data in long-lived closures. Use `WeakMap` for caches keyed by objects. Clear
intervals in cleanup/destroy methods.

## Audit Workflow

### Phase 1: Identify Runtime Architecture

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
2. Determine the runtime and framework (Express, Fastify, NestJS, Next.js, serverless, etc.) and whether async
   patterns are prevalent.
3. Note the ORM / database client in use (Prisma, TypeORM, Drizzle, Knex, pg, etc.) and caching strategy.

### Phase 2: Scan for Performance Signals

```bash
EXCLUDE='--glob !**/*.test.* --glob !**/*.spec.* --glob !**/node_modules/** --glob !**/dist/**'

# Event loop blocking
rg 'readFileSync|writeFileSync|existsSync|accessSync|mkdirSync|readdirSync' --type ts $EXCLUDE
rg 'execSync|spawnSync' --type ts $EXCLUDE

# Sequential awaits
rg -U 'await.*\n\s*\w+\s*=\s*await' --type ts $EXCLUDE

# N+1 patterns (loop with await/query inside)
rg -U 'for\s*\(.*of\s+\w+\)\s*\{[^}]*await' --type ts $EXCLUDE
rg 'findUnique\(|findOneBy\(|findOne\(' --type ts $EXCLUDE

# Unclosed resources
rg 'createReadStream|createWriteStream' --type ts $EXCLUDE
rg 'pool\.connect\(' --type ts $EXCLUDE

# Unbounded caches
rg 'new Map\(\)|new Set\(\)' --type ts $EXCLUDE
rg --pcre2 'cache\s*[:=]\s*new\s+Map' --type ts $EXCLUDE

# Eager materialization
rg '\.toArray\(\)' --type ts $EXCLUDE
rg 'readFile\(' --type ts $EXCLUDE

# Connection pool configuration
rg 'new Pool\(|PrismaClient\(|createConnection\(|createPool\(' --type ts $EXCLUDE

# Hot path operations
rg 'new RegExp\(' --type ts $EXCLUDE
rg 'JSON\.parse|JSON\.stringify' --type ts $EXCLUDE

# Memory leak patterns
rg '\.on\(|\.addEventListener\(' --type ts $EXCLUDE
rg 'setInterval\(' --type ts $EXCLUDE
rg 'setMaxListeners\(0\)' --type ts $EXCLUDE
```

### Phase 3: Evaluate Async Correctness

For each request handler or middleware:

1. Check for synchronous file system / child process calls.
2. Identify sequential awaits that could be gathered.
3. Verify CPU-intensive operations are offloaded to workers.

### Phase 4: Evaluate Resource Lifecycle

For each opened resource:

1. Verify cleanup path — `try/finally`, `using`, `pipeline()`, `AbortController`.
2. Check that database connections are returned to pools.
3. Identify resources that span scopes without explicit lifecycle management.
4. Check event listener registration/deregistration balance.

### Phase 5: Evaluate Data Access Patterns

1. Check for N+1 patterns in loops that issue queries.
2. Verify ORM eager loading where lazy loading would cause N+1.
3. Check for missing DataLoader in GraphQL resolvers.
4. Verify batch operation opportunities.

### Phase 6: Produce Report

## Output Format

Save as `YYYY-MM-DD-perf-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs
folder exists).

```md
# Perf Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Runtime: {Node.js / Deno / Bun}
- Framework: {Express / Fastify / NestJS / Next.js / etc.}
- ORM: {Prisma / TypeORM / Drizzle / none}
- Exclusions: {list}

## Runtime Architecture

- Framework: {Express / Fastify / NestJS / Next.js / serverless / etc.}
- Async I/O: {native fetch / axios / node-fetch / undici / etc.}
- Database client: {Prisma / TypeORM / Drizzle / pg / etc.}
- Caching: {Redis / in-memory Map / lru-cache / none}

## Findings

### Event Loop Blocking

| # | Location | Blocking Call | Async Equivalent | Severity |
| - | -------- | ------------- | ---------------- | -------- |
| 1 | file:line | `readFileSync()` in handler | `fs.promises.readFile()` | High |

### Sequential Awaits

| # | Location | Calls | Independent? | Estimated Speedup | Action |
| - | -------- | ----- | ------------ | ----------------- | ------ |
| 1 | file:line | `fetchA`, `fetchB`, `fetchC` | Yes | ~3x | Use `Promise.all()` |

### N+1 Query Patterns

| # | Location | Loop | Query per Iteration | Batch Alternative |
| - | -------- | ---- | ------------------- | ----------------- |
| 1 | file:line | `for (const user of users)` | `getOrders(user.id)` | `getOrdersBatch(userIds)` |

### Unclosed Resources

| # | Location | Resource | Cleanup | Action |
| - | -------- | -------- | ------- | ------ |
| 1 | file:line | `createReadStream()` | No error cleanup | Use `stream.pipeline()` |

### Unbounded In-Memory Growth

| # | Location | Collection | Growth Pattern | Action |
| - | -------- | ---------- | -------------- | ------ |
| 1 | file:line | `cache = new Map()` | Module-level, never evicted | Use `lru-cache` with maxSize |

### Eager Materialization

| # | Location | Operation | Data Size | Action |
| - | -------- | --------- | --------- | ------ |
| 1 | file:line | `db.query().toArray()` | Unbounded | Use cursor / streaming |

### Missing Connection Pool Configuration

| # | Location | Client/Pool | Issue | Action |
| - | -------- | ----------- | ----- | ------ |
| 1 | file:line | `new PrismaClient()` | Per-request creation | Share at application scope |

### Expensive Operations in Hot Paths

| # | Location | Operation | Frequency | Action |
| - | -------- | --------- | --------- | ------ |
| 1 | file:line | `new RegExp()` in handler | Per-request | Hoist to module level |

### Memory Leak Patterns

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `.on('data', ...)` without `.off()` | Clean up on request end |

## Recommendations (Priority Order)

1. **Must-fix**: {event loop blocking in request path, N+1 in critical paths, unclosed resources, unbounded caches}
2. **Should-fix**: {sequential awaits, missing pool configuration, eager materialization of large datasets}
3. **Consider**: {hot path optimizations, memory leak patterns, streaming conversions for moderate datasets}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: performance and resource management only.** Do not flag type invariants (→ invariant-hunter-ts), type design
  (→ type-hunter-ts), structural complexity (→ simplicity-hunter-ts), module boundary issues (→ boundary-hunter-ts),
  class/interface design (→ solid-hunter-ts), missing documentation (→ doc-hunter-ts), security
  (→ security-hunter-ts), error handling design (→ error-hunter-ts), test quality (→ test-hunter-ts), or cosmetic
  style (→ slop-hunter-ts). If a finding doesn't answer "does this code waste resources or block unnecessarily?",
  it doesn't belong here.
- **Boundary with simplicity-hunter**: simplicity-hunter flags unnecessary abstractions and dead code from a structural
  perspective. Perf-hunter flags patterns that are structurally correct but operationally wasteful (blocking I/O, N+1,
  unbounded caches). If the code is over-engineered, it's simplicity. If it's under-optimized, it's perf.
- **Evidence required.** Every finding must cite `file/path.ts:line` with the exact code.
- **Structural, not speculative.** Flag patterns that are *structurally* inefficient (proven antipatterns like N+1,
  blocking I/O in request handlers), not micro-optimizations based on speculation. Don't flag `Array.map()` vs
  `for` loop for small bounded datasets.
- **Runtime awareness.** Some patterns only matter in request-handling contexts (blocking I/O, sequential awaits).
  Startup-time sync operations are generally acceptable. Note the context and don't flag startup-only code as request
  path problems.
