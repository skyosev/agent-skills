---
name: security-hunter
description: |
  Audit code for security vulnerabilities — hardcoded secrets, injection risks, missing
  input validation at trust boundaries, insecure defaults, auth gaps, sensitive data
  exposure, and unsafe patterns like eval or innerHTML.

  Use when: reviewing code before deployment, auditing trust boundaries, preparing for
  a security review, onboarding third-party integrations, or hardening an application.
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

**Action:** Add schema validation at every trust boundary. Validate type, format, range, and length. Reject invalid
input explicitly — don't coerce or default.

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

### 7. Unsafe Code Patterns

Language-level patterns that create exploitable conditions.

**Signals:**

- `innerHTML`, `dangerouslySetInnerHTML`, `document.write()` with dynamic content (XSS)
- `Object.assign()` or spread from untrusted input without allowlisting properties (prototype pollution)
- `JSON.parse()` of untrusted input without a try/catch or schema validation
- Timing-sensitive comparisons of secrets (use constant-time comparison instead)
- Unrestricted file write paths derived from user input
- Deserialization of untrusted data without schema validation

**Action:** Use `textContent` instead of `innerHTML`, allowlist properties on untrusted objects, validate schemas
after parsing, use `crypto.timingSafeEqual()` for secret comparison.

## Audit Workflow

### Phase 1: Map Trust Boundaries

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
2. Identify trust boundaries: API route handlers, webhooks, file upload endpoints, third-party integration points,
   CLI argument parsers, config loaders.
3. Identify auth/authz middleware and where it's applied.

### Phase 2: Scan for Security Signals

```bash
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.test.* --glob !**/*.spec.*'

# Hardcoded secrets (common patterns)
rg --pcre2 '(sk_live_|AKIA|ghp_|password\s*=\s*["\x27]|secret\s*=\s*["\x27])' $EXCLUDE
rg --pcre2 '(postgres|mysql|mongodb)://\w+:\w+@' $EXCLUDE

# Injection: eval, exec, spawn, Function constructor
rg '\beval\s*\(|\bexec\s*\(|\bspawn\s*\(|\bFunction\s*\(' --type ts $EXCLUDE

# Injection: string concatenation in queries
rg --pcre2 '(query|sql|execute)\s*\(\s*[`"\x27].*\$\{' --type ts $EXCLUDE

# XSS: innerHTML, dangerouslySetInnerHTML, document.write
rg 'innerHTML|dangerouslySetInnerHTML|document\.write' --type ts $EXCLUDE

# Insecure config
rg --pcre2 'Access-Control-Allow-Origin.*\*|rejectUnauthorized.*false|secure.*false' $EXCLUDE

# Missing auth (route definitions without auth middleware — project-specific, adapt pattern)
rg '(app|router)\.(get|post|put|patch|delete)\s*\(' --type ts $EXCLUDE

# Logging of sensitive data
rg --pcre2 'console\.(log|info|debug).*\b(password|token|secret|authorization|cookie)\b' -i $EXCLUDE

# Regex from user input
rg 'new RegExp\(' --type ts $EXCLUDE
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

Save as `Y-m-d-security-hunter-audit.md` in the project's docs folder.

```md
# Security Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

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

## Recommendations (Priority Order)

1. **Critical**: {hardcoded secrets to rotate, injection vulnerabilities, auth bypasses}
2. **Must-fix**: {missing input validation, insecure defaults, auth gaps}
3. **Should-fix**: {sensitive data exposure, unsafe patterns}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: security vulnerabilities only.** Do not flag type invariants (→ invariant-hunter), type design
  (→ type-hunter), structural complexity (→ simplicity-hunter), module boundary issues (→ boundary-hunter),
  class/interface design (→ solid-hunter), missing documentation (→ doc-hunter), test quality (→ test-hunter),
  or cosmetic style (→ slop-hunter). If a finding doesn't answer "could this be exploited?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact code.
- **Severity matters.** Use Critical / Must-fix / Should-fix. A hardcoded production secret is not the same severity
  as a missing `SameSite` cookie attribute. Prioritize accordingly.
- **Context over pattern-matching.** A `new RegExp()` with a hardcoded pattern is fine. A `new RegExp(userInput)` is
  a ReDoS risk. Grep finds both — judgment separates them.
- **No false confidence.** This audit catches common patterns, not all vulnerabilities. It is not a substitute for
  professional penetration testing or automated security scanning.
