---
name: security-hunter-ts
description: |
  Audit TypeScript code for security vulnerabilities — hardcoded secrets, injection risks,
  missing input validation at trust boundaries, insecure defaults, auth gaps, sensitive data
  exposure, and unsafe patterns like eval or innerHTML.

  Use when: reviewing TypeScript code before deployment, auditing trust boundaries, preparing
  for a security review, onboarding third-party integrations, or hardening an application.
disable-model-invocation: true
---

# Security Hunter

Audit code for **security vulnerabilities** — places where untrusted input flows into sensitive operations without
validation, secrets are embedded in source, defaults are permissive, or auth checks are missing. The goal: **every
trust boundary validates its inputs, no secrets live in code, and the principle of least privilege is applied
throughout.**

## When to Use

- Reviewing code before production deployment
- Auditing trust boundaries (API endpoints, form handlers, webhooks)
- Preparing for a formal security review or pen test
- Onboarding third-party integrations or new external data sources
- Hardening an application after a security incident

## Core Principles

1. **Trust boundaries are the perimeter.** Every point where external data enters the system — HTTP requests, file
   uploads, environment variables, database reads, third-party API responses — is a trust boundary. Input must be
   validated, sanitized, or escaped before it flows into operations that could be exploited.

2. **Secrets belong in the environment, never in code.** API keys, passwords, tokens, certificates, and connection
   strings must come from environment variables, secret managers, or encrypted config — never from source files,
   comments, or committed config.

3. **Default to deny.** Defaults should be restrictive: CORS origins explicit not `*`, auth required not optional,
   permissions minimal not broad. Permissive defaults are the most common class of security misconfiguration.

4. **Defense in depth.** No single validation layer is sufficient. Validate at the boundary, escape at the output,
   enforce at the data layer. If one layer fails, another should catch the exploit.

5. **Fail closed.** When auth/authz checks fail or throw, the result should be denial, not access. Error paths must
   not bypass security controls.

6. **Type-safe ≠ runtime safe.** TypeScript types are erased at runtime. `(await response.json()) as User` compiles but
   does not validate — an attacker controls the wire format. Every external payload must pass schema validation before
   it enters typed business logic; derive downstream types from the schema (`z.infer<typeof schema>`).

## What to Hunt

### 1. Hardcoded Secrets

API keys, passwords, tokens, or connection strings embedded directly in source code.

**Signals:**

- String literals matching key patterns: `sk_live_`, `AKIA`, `ghp_`, `Bearer `, `password=`
- Connection strings with embedded credentials: `postgres://user:pass@host`
- Base64-encoded strings in auth headers or config
- `.env` files or secret-bearing config committed to the repo
- Comments containing credentials ("temporary key: xyz123")

**Action:** Move to environment variables or a secret manager. Add the pattern to `.gitignore`. Rotate any committed
secret immediately — it's already compromised if the repo was ever shared.

### 2. Injection Vulnerabilities

Untrusted input concatenated into strings that are interpreted as code, queries, or commands.

**Signals:**

- SQL: string concatenation or template literals in query strings instead of parameterized queries
- Command: `exec()`, `spawn()`, `system()` with user-controlled arguments
- Path traversal: user input in `fs.readFile()`, `path.join()`, or URL construction without sanitization
- Template injection: user input rendered in server-side templates without escaping
- Regex: user input passed directly to `new RegExp()` (ReDoS risk)
- `eval()`, `Function()`, `setTimeout(string)` with dynamic input

**Action:** Use parameterized queries, allowlists, path canonicalization, template auto-escaping, or regex escaping.
Never concatenate untrusted input into interpreted strings.

### 3. Missing Input Validation at Trust Boundaries

Endpoints, handlers, or integration points that accept external data without schema validation or sanitization.

**Signals:**

- API handlers that destructure `req.body` or `req.query` without validation (no Zod, Joi, class-validator, etc.)
- File upload handlers without type/size/content validation
- Webhook handlers without signature verification
- URL parameters used directly in business logic without parsing/validation
- Form inputs passed to database operations without sanitization
- `(await response.json()) as T`, `JSON.parse(...) as T`, or `req.body as T` — compile-time cast with no runtime schema
- Validation schema exists in one layer but downstream functions accept manually duplicated types instead of
  `z.infer<typeof schema>`

**Action:** Add schema validation at every trust boundary. Validate type, format, range, and length. Reject invalid
input explicitly — don't coerce or default. Parse with Zod/Joi/class-validator and type downstream code from the schema
inference (`type User = z.infer<typeof UserSchema>`), not a parallel manual interface.

### 4. Insecure Defaults and Configuration

Permissive defaults that weaken security posture when not explicitly overridden.

**Signals:**

- CORS: `Access-Control-Allow-Origin: *` or `credentials: true` with wildcard origin
- CSRF: protection disabled or missing on state-changing endpoints
- Cookie: missing `Secure`, `HttpOnly`, or `SameSite` attributes
- TLS: certificate validation disabled (`rejectUnauthorized: false`)
- Rate limiting: absent on auth endpoints or public APIs
- Debug/dev mode enabled in production config
- Permissive CSP headers or missing security headers

**Action:** Restrict defaults. Require explicit opt-in for permissive settings with justification.

### 5. Authentication and Authorization Gaps

Missing or inconsistent auth checks that allow unauthorized access or privilege escalation.

**Signals:**

- Routes/endpoints without auth middleware where peer routes have it
- Authorization checks that compare user IDs with string equality on user-controlled values
- Role checks using client-provided role claims without server-side verification
- Admin functionality accessible by changing a URL parameter or request body field
- Session tokens without expiry, rotation, or revocation
- Password handling: plain-text storage, weak hashing (MD5, SHA1), missing salting

**Action:** Ensure every endpoint has explicit auth/authz. Check authorization server-side against the session, not
client-provided claims. Use bcrypt/scrypt/argon2 for password hashing.

### 6. Sensitive Data Exposure

Personal data, secrets, or internal details leaked through logs, errors, responses, or storage.

**Signals:**

- Logging of request bodies, auth headers, or user PII
- Error responses that include stack traces, internal paths, or database details
- API responses that return more fields than the client needs (no field filtering)
- Sensitive data stored in localStorage, sessionStorage, or unencrypted cookies
- PII in URLs (email, SSN, tokens in query parameters — logged by default in most servers)

**Action:** Strip sensitive fields from logs and error responses. Filter API responses to only required fields. Use
encrypted/httpOnly storage for sensitive client-side data.

### 7. Dependency and Supply-Chain Risks

Package dependencies with known vulnerabilities, unvetted postinstall scripts, or lockfile integrity issues.

**Signals:**

- `package.json` dependencies pinned to `*` or very wide ranges without a lockfile
- Lockfile (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) not committed to the repo
- Packages with `postinstall`, `preinstall`, or `install` lifecycle scripts that execute arbitrary code
- Dependencies with known CVEs (check via `npm audit` or equivalent)
- Importing from CDNs or unpinned URLs at runtime

**Action:** Commit the lockfile. Pin dependency ranges. Run `npm audit` and address critical/high findings. Review
lifecycle scripts in new dependencies before adding them.

### 8. Unsafe Code Patterns

Language-level patterns that create exploitable conditions.

**Signals:**

- `innerHTML`, `dangerouslySetInnerHTML`, `document.write()` with dynamic content (XSS)
- `Object.assign()` or spread from untrusted input without allowlisting properties (prototype pollution)
- `JSON.parse()` of untrusted input without a try/catch or schema validation
- Timing-sensitive comparisons of secrets (use constant-time comparison instead)
- Unrestricted file write paths derived from user input
- Deserialization of untrusted data without schema validation
- `__proto__` or `constructor.prototype` accessible via user-controlled object keys (prototype pollution)

**Action:** Use `textContent` instead of `innerHTML`, allowlist properties on untrusted objects, validate schemas
after parsing, use `crypto.timingSafeEqual()` for secret comparison. Use `Object.create(null)` for lookup maps
populated from user input to prevent prototype pollution.

### 9. TypeScript-Specific Security Patterns

Leveraging (or failing to leverage) TypeScript's type system for security enforcement.

**Signals:**

- `(await response.json()) as T` or `JSON.parse(untrusted) as T` — typed appearance with no runtime validation
- `as any` or `as unknown as T` bypassing validation at trust boundaries — input flows from `any` into typed
  operations without runtime validation
- Branded types not used for security-sensitive strings (raw `string` for SQL fragments, HTML content, URLs,
  file paths) — allows accidental mixing of validated and unvalidated values
- Missing type guards at security validation boundaries — `typeof` / `instanceof` checks that should narrow
  to validated types but are plain boolean checks instead
- `strict: false` or `strictNullChecks: false` in `tsconfig.json` — permissive compiler settings that weaken
  security invariants
- Zod/Joi/class-validator schemas that exist but whose inferred types aren't used in downstream function
  signatures — validation runs but the type system doesn't enforce it
- `@ts-ignore` or `@ts-expect-error` suppressing errors in security-sensitive code (auth, validation, crypto)

**Action:** Replace cast-then-trust with parse-then-narrow: `const user = UserSchema.parse(await response.json())`.
Use branded types for security-sensitive values (`type SafeHtml = string & { __brand: 'SafeHtml' }`). Enable
`strict: true` in `tsconfig.json`. Use type predicates or assertion functions (`asserts input is ValidatedRequest`) at
trust boundaries. Derive all downstream types from validation schemas (`z.infer<typeof schema>`) — one source of truth
for runtime shape and compile-time types.

### 10. GraphQL and WebSocket Security

Missing protections specific to GraphQL APIs and WebSocket connections.

**Signals:**

- GraphQL: no query depth limiting (allows deeply nested queries that exhaust server resources)
- GraphQL: no query complexity analysis or cost limiting
- GraphQL: introspection enabled in production (exposes full schema to attackers)
- GraphQL: mutations without authentication or authorization checks in resolvers
- GraphQL: no persisted queries or query allowlisting in production
- WebSocket: missing origin validation on connection upgrade
- WebSocket: no authentication on WebSocket handshake (relying only on initial HTTP auth)
- WebSocket: no rate limiting on message frequency
- WebSocket: user input from messages used in operations without validation
- Server-Sent Events (SSE): no authentication or authorization on event streams

**Action:** Add query depth and complexity limits (e.g., `graphql-depth-limit`, `graphql-query-complexity`).
Disable introspection in production. Validate WebSocket origin headers. Authenticate WebSocket connections on
handshake. Rate-limit WebSocket messages. Validate all user input from WebSocket messages with schema validation.

### 11. SSRF, Weak Randomness, and JWT Verification Gaps

These are **candidate signals, not grep-findings** — each nominated site requires validation before it becomes a
finding.

**Signals:**

- **SSRF candidates:** `fetch()`, `axios()`, `http.request()` where the URL is a variable rather than a literal.
  A finding requires tracing user-controlled data to the request sink — the grep only nominates sites for
  data-flow validation. Confirmed SSRF needs an allowlist of destinations or URL parsing + host validation.
- **Weak randomness (nearly direct):** `Math.random()` used for tokens, session IDs, password-reset codes, or
  anything security-bearing. Validate only that the value is security-relevant; the fix is
  `crypto.randomBytes()` / `crypto.randomUUID()`.
- **JWT verification gaps (library-aware):** `jwt.decode()` where verification is expected — in `jsonwebtoken`,
  `decode()` does **not** verify the signature (its own docs warn about this); `jwt.verify()` does. The finding
  requires confirming which library and call path is in play — other libraries (`jose`, framework middleware)
  have different APIs. Also check: `algorithms` not pinned on verify, and secrets accepted from user input.

**Action:** For each candidate, trace the data flow or library call path first. Report only validated findings;
list unvalidated candidates separately as "requires manual verification" when the trace was inconclusive.

## Audit Workflow

### Phase 1: Map Trust Boundaries

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, and untracked
   - **Path**: specific files, folders, or layers
   - **Codebase**: the entire project (the default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot (a resolved file list), use it verbatim and do
   not re-resolve. The resolution below applies to standalone runs only.

   For diff mode, resolve fail-closed:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
   if [ -z "$BASE" ]; then
     for b in origin/main origin/master main master; do
       git rev-parse -q --verify "$b" >/dev/null && BASE=$b && break
     done
   fi
   # If BASE is still empty: STOP. Ask for an explicit base. Do not continue.

   SCOPE=$( { git diff --name-only --diff-filter=d "$BASE"...HEAD;
              git diff --name-only --diff-filter=d HEAD;
              git ls-files --others --exclude-standard; } | sort -u )
   DELETED=$( { git diff --name-only --diff-filter=D "$BASE"...HEAD;
                git diff --name-only --diff-filter=D HEAD; } | sort -u )
   ```
   If `$SCOPE` is empty, run no scans: write the report with "Audit completed: 0 findings — empty diff scope",
   listing `$DELETED` under "Deleted in diff" if non-empty, and stop — deleted files matter here: a deleted
   test or authorization check is security-relevant context. If the resolved surface exceeds what can be read
   within the context budget, report the file count and ask to narrow or chunk.

   **Two surfaces.** Findings are reported only against the **target scope** (`$SCOPE`) — every finding anchors
   (file:line) there. Related files may still be *read* as **context**: trust-boundary mapping and data-flow
   tracing (Phases 1, 3, 4) read the whole project, because in-scope input can reach sinks outside the scope and
   vice versa — anchor the finding at its in-scope end.
2. Identify trust boundaries: API route handlers, webhooks, file upload endpoints, third-party integration points,
   CLI argument parsers, config loaders.
3. Identify auth/authz middleware and where it's applied.

### Phase 2: Scan for Security Signals

Run every scan against the target scope (`SCOPE=.` in codebase mode). Two exclusion profiles apply:

- **Secrets and dependency scans use the minimal profile** — only `node_modules` is excluded. Tests and generated
  files stay in scope: a live key in a test fixture is exactly as compromised as one in `src/`, and generated
  artifacts can embed committed credentials too.
- All other scans use the production profile.

```bash
# Minimal profile — secrets and dependency scans only
EXCLUDE_MINIMAL='--glob !**/node_modules/**'

# Production profile — everything else
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

# Hardcoded secrets (common patterns) — minimal profile, all file types
rg --pcre2 '(sk_live_|AKIA|ghp_|password\s*=\s*["\x27]|secret\s*=\s*["\x27])' $EXCLUDE_MINIMAL -- $SCOPE
rg --pcre2 '(postgres|mysql|mongodb)://\w+:\w+@' $EXCLUDE_MINIMAL -- $SCOPE

# Injection: eval, exec, spawn, Function constructor
rg '\beval\s*\(|\bexec\s*\(|\bspawn\s*\(|\bFunction\s*\(' --type ts $EXCLUDE -- $SCOPE

# TypeScript-specific security
rg 'as any|as unknown' --type ts $EXCLUDE -- $SCOPE
rg --pcre2 '\.json\(\)\)\s+as\s|\bJSON\.parse\([^)]+\)\s+as\s' --type ts $EXCLUDE -- $SCOPE
rg 'strict.*false|strictNullChecks.*false' --glob 'tsconfig*.json'
rg '@ts-ignore|@ts-expect-error' --type ts $EXCLUDE -- $SCOPE

# GraphQL security
rg 'introspection|depthLimit|queryComplexity' --type ts $EXCLUDE -- $SCOPE

# WebSocket security
rg 'WebSocket|socket\.io|ws\.' --type ts $EXCLUDE -- $SCOPE

# Injection: string concatenation in queries
rg --pcre2 '(query|sql|execute)\s*\(\s*[`"\x27].*\$\{' --type ts $EXCLUDE -- $SCOPE

# XSS: innerHTML, dangerouslySetInnerHTML, document.write
rg 'innerHTML|dangerouslySetInnerHTML|document\.write' --type ts $EXCLUDE -- $SCOPE

# Insecure config
rg --pcre2 'Access-Control-Allow-Origin.*\*|rejectUnauthorized.*false|secure.*false' $EXCLUDE -- $SCOPE

# Missing auth (route definitions without auth middleware — project-specific, adapt pattern)
rg '(app|router)\.(get|post|put|patch|delete)\s*\(' --type ts $EXCLUDE -- $SCOPE

# Logging of sensitive data
rg --pcre2 'console\.(log|info|debug).*\b(password|token|secret|authorization|cookie)\b' -i $EXCLUDE -- $SCOPE

# Regex from user input
rg 'new RegExp\(' --type ts $EXCLUDE -- $SCOPE

# SSRF candidates (variable URLs — nominate for data-flow validation, §11)
rg --pcre2 '(fetch|axios(\.\w+)?|https?\.request)\(\s*[a-zA-Z_$`]' --type ts $EXCLUDE -- $SCOPE

# Weak randomness for security values (§11)
rg 'Math\.random\(' --type ts $EXCLUDE -- $SCOPE

# JWT: decode without verify (library-aware validation required, §11)
rg '\bjwt\.decode\(|\.decode\(.*token' --type ts $EXCLUDE -- $SCOPE

# Dependency risks: lifecycle scripts in package.json — minimal profile
rg '"(pre|post)?install"' --glob 'package.json' $EXCLUDE_MINIMAL
```

### Phase 3: Trace Data Flows

For each trust boundary found in Phase 1:

1. Does untrusted input pass through validation before reaching sensitive operations?
2. Are query parameters, body fields, and headers validated for type, format, and range?
3. Could a malicious input reach `eval`, `exec`, a database query, or DOM manipulation?

### Phase 4: Evaluate Auth Coverage

1. List all routes/endpoints. For each: is auth middleware applied?
2. Identify authorization logic. Is it server-side? Does it rely on client claims?
3. Check session management: expiry, rotation, revocation.

### Phase 5: Produce Report

## Output Format

Save as `YYYY-MM-DD-security-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies
an output path (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

```md
# Security Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list — note the minimal profile used for secrets/dependency scans}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Audit completed: {N} findings

## Trust Boundary Map

| # | Boundary | Location | Validation | Auth |
| - | -------- | -------- | ---------- | ---- |
| 1 | POST /api/users | file:line | Zod schema | JWT middleware |
| 2 | Webhook /hooks/stripe | file:line | None | None |

## Findings

### Hardcoded Secrets

| # | Location | Pattern | Severity | Action |
| - | -------- | ------- | -------- | ------ |
| 1 | file:line | `sk_live_...` Stripe key | Critical | Move to env, rotate immediately |

### Injection Risks

| # | Location | Type | Untrusted Input | Action |
| - | -------- | ---- | --------------- | ------ |
| 1 | file:line | SQL injection | `req.query.id` concatenated into query | Use parameterized query |

### Missing Input Validation

| # | Location | Boundary | Input | Action |
| - | -------- | -------- | ----- | ------ |
| 1 | file:line | POST /api/orders | `req.body` used without validation | Add Zod/Joi schema |

### Insecure Defaults

| # | Location | Setting | Current | Action |
| - | -------- | ------- | ------- | ------ |
| 1 | file:line | CORS origin | `*` | Restrict to allowed origins |

### Auth/Authz Gaps

| # | Location | Endpoint | Issue | Action |
| - | -------- | -------- | ----- | ------ |
| 1 | file:line | GET /admin/users | No auth middleware | Add admin auth |

### Sensitive Data Exposure

| # | Location | Data | Channel | Action |
| - | -------- | ---- | ------- | ------ |
| 1 | file:line | Auth token | console.log | Remove from logs |

### Unsafe Patterns

| # | Location | Pattern | Risk | Action |
| - | -------- | ------- | ---- | ------ |
| 1 | file:line | `innerHTML = userInput` | XSS | Use `textContent` |

### Dependency / Supply-Chain Risks

| # | Location | Issue | Severity | Action |
| - | -------- | ----- | -------- | ------ |
| 1 | package.json | No lockfile committed | High | Commit lockfile |

### SSRF / Randomness / JWT Candidates (validated)

| # | Location | Candidate | Validation Result | Action |
| - | -------- | --------- | ----------------- | ------ |
| 1 | file:line | `fetch(userUrl)` | User input reaches sink unfiltered | Allowlist destinations |

## Recommendations (Priority Order)

1. **Critical**: {hardcoded secrets to rotate, injection vulnerabilities, auth bypasses, confirmed SSRF}
2. **High**: {missing input validation, insecure defaults, auth gaps, dependency CVEs, weak randomness for tokens}
3. **Medium**: {sensitive data exposure, unsafe patterns, supply-chain hygiene}
4. **Low**: {hardening opportunities without a concrete exploit path}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: security vulnerabilities only.** If a finding doesn't answer "could this be exploited?", it belongs to
  another hunter — do not flag it here. Boundary with invariant-hunter: it flags the unsafe cast and loose typing
  at trust boundaries; this hunter flags the exploitable boundary and recommends schema + `z.infer<>`.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact code.
- **Severity matters.** Use the Critical / High / Medium / Low definitions above. A hardcoded production secret is
  not the same severity as a missing `SameSite` cookie attribute. Prioritize accordingly.
- **Context over pattern-matching.** A `new RegExp()` with a hardcoded pattern is fine. A `new RegExp(userInput)` is
  a ReDoS risk. Grep finds both — judgment separates them.
- **No false confidence.** This audit catches common patterns, not all vulnerabilities. It is not a substitute for
  professional penetration testing or automated security scanning.
