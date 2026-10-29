# Security Hunter — report format

The report is, in order: `## Scope`; `## Findings` with one `###` section per category that has at least one finding;
`## Recommendations (Priority Order)`. Unbraced Scope lines appear on every run that reaches scanning; a `{braced}`
line appears only when its condition holds. A run that stops early (empty scope, no eligible source) writes the Scope
lines resolved so far and its `Audit completed` line, nothing else. A category with no findings gets no heading,
table, or "none found" line; a thin report is a valid result.

**Boundaries line.** The boundaries Phase 1 step 5 recorded, by kind, with counts and files.

**Auth line.** How authentication is applied (global middleware, per-route decorators or middleware, a framework
default, or `none found`) and the files that apply it.

**Language versions line.** The language versions Phase 1 step 5 recorded, with the file each came from; then, after
`resolved:`, only the library versions Phase 4 looked up for a candidate, with the lockfile each came from. A version
that could not be read is `unknown`.

**Deployment evidence line.** Each environment setting the Phase 1 scan found, with its file, or `none found`.

**Detectors line.** One entry per detector `security-common.md` and the language references name, in one of the
states of SKILL.md Phase 2.

**Untraced line.** Only when the context budget stopped a trace: the count of candidates whose trace was cut short.
They are not findings.

**Policy line.** Only when repository instructions state a security policy that covers a reported row: the quoted
instruction and the rows it covers. Each covered row keeps its Severity, and its Evidence cell ends with `accepted by
policy`.

**Secrets are truncated** in every cell: the secret part of the value keeps its recognizable prefix and the next four
characters, then `…`; the non-secret parts around it (scheme, user, host, port, database, the variable name) may stay,
so `postgres://app:s3cr…@prod-db:5432/app` is the rule applied to a connection string. The report never reproduces a
credential.

**Recommendation-only entries.** Each is a Low entry under Recommendations, with no table row; `Audit completed`
counts findings only:

- secret-detector adoption (gitleaks or trufflehog) when neither is configured: regex sees known prefixes and
  `name = "literal"` forms, never high-entropy generic secrets, and this hunter never reads git history;
- rate limiting when the repository applies no limiter anywhere: the entry names the credential routes and says a
  gateway may provide the limit.

No other detector is recommended.

*The Evidence cell* in SKILL.md is, per table, the last column before Severity: Credential (Hardcoded Secrets), Path
(Injection), Reaches (Unvalidated Boundary Input), Effective In (Insecure Configuration), Evidence (Auth Gaps), Channel
(Sensitive Data Exposure), Used For (Weak Cryptography), Bound (Resource Exhaustion), Evidence (Dependency and
Supply-Chain Risks).

**Evidence cells** follow each category's evidence bar in SKILL.md; the Path cell ends with the auth in front of the
boundary.

```md
# Security Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Commit: {short SHA}{, dirty working tree — line numbers match no commit; re-locate findings by symbol name}
- {Base: {ref} → merge base {short SHA} — diff scope only}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists}; all-file list: {count}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker / test paths (secrets excepted)}
- References loaded: common{, go, python, typescript as present}
- {excluded — no reference for .<ext>: {count} files — when applicable, naming each extension}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Boundaries: {14 HTTP routes (api/*.go) | 2 webhooks (hooks/) | 1 gRPC service (rpc/) | 1 CLI (cmd/)}
- Auth: {global middleware api/mw/auth.go | per-route decorators (views/*.py) | NestJS APP_GUARD (app.module.ts) | none found}
- Language versions: {go 1.22 (go.mod) | requires-python >=3.11 (pyproject.toml) | node 20 (engines)}{; resolved: lxml 5.2 (poetry.lock), jsonwebtoken 9 (api/package-lock.json)}
- Deployment evidence: {DJANGO_SETTINGS_MODULE=app.settings.prod (Dockerfile) | NODE_ENV=production (compose.yaml) | none found}
- Detectors: {per detector — `gitleaks: ran — gitleaks dir . --no-banner --redact …` / `gosec: skipped — not configured` / `ESLint: skipped — no security-relevant rules enabled` / `govulncheck: errored — fetching vuln.go.dev: …`}
- {Untraced: {N} candidates (budget)}
- {Policy: "{quoted instruction}" — accepted by policy: {category} rows {#, #} at {boundary}}
- Audit completed: {N} findings

## Findings

### Hardcoded Secrets

| # | Location | Code | Credential | Severity | Impact | Action |
| - | -------- | ---- | ---------- | -------- | ------ | ------ |
| 1 | config/db.go:12 | `postgres://app:s3cr…@prod-db:5432/app` | connection-string: production Postgres (host in compose.yaml) | Critical | High | Read `DATABASE_URL` from the environment; rotate the password |

### Injection

| # | Location | Sink | Source | Path | Severity | Impact | Action |
| - | -------- | ---- | ------ | ---- | -------- | ------ | ------ |
| 1 | api/users.go:48 | sql: `db.Query(fmt.Sprintf(…))` | `r.URL.Query().Get("id")` at api/users.go:41 | users.go:41 → users.go:45 (no check) → users.go:48; no auth on `GET /users` | Critical | High | Parameterize: `db.Query("… WHERE id = $1", id)` |

### Unvalidated Boundary Input

| # | Location | Boundary | Field | Reaches | Severity | Impact | Action |
| - | -------- | -------- | ----- | ------- | -------- | ------ | ------ |
| 1 | routes/orders.ts:30 | `POST /orders` | `req.body` (whole) | `Order.create(req.body)`: `total` is a writable column, so a client sets its own price | High | Medium | `OrderSchema.parse(req.body)` with `.strict()`; pass the parsed value to `create` |

### Insecure Configuration

| # | Location | Setting | Value | Effective In | Severity | Impact | Action |
| - | -------- | ------- | ----- | ------------ | -------- | ------ | ------ |
| 1 | settings/prod.py:7 | debug | `DEBUG = True` | app.settings.prod (`DJANGO_SETTINGS_MODULE` in Dockerfile) | High | High | `DEBUG = False`; read it from the environment |

### Auth Gaps

| # | Location | Endpoint | Kind | Evidence | Severity | Impact | Action |
| - | -------- | -------- | ---- | -------- | -------- | ------ | ------ |
| 1 | api/admin.ts:14 | `DELETE /admin/users/:id` | no-auth | peer `DELETE /admin/orders/:id` at admin.ts:22 uses `requireAdmin`; this route has none | Critical | Medium | `router.delete("/admin/users/:id", requireAdmin, …)` |

### Sensitive Data Exposure

| # | Location | Data | Channel | Severity | Impact | Action |
| - | -------- | ---- | ------- | -------- | ------ | ------ |
| 1 | svc/auth.py:55 | token (reset link) | url: `GET /reset?token=…` logged by the access log | Medium | Medium | Single-use token with a 15-minute expiry; `Referrer-Policy: no-referrer` on the reset page; the new password submitted by POST |

### Weak Cryptography

| # | Location | Primitive | Used For | Severity | Impact | Action |
| - | -------- | --------- | -------- | -------- | ------ | ------ |
| 1 | svc/token.go:21 | `math/rand` | session id | High | High | `crypto/rand.Text()` (Go 1.24) or `rand.Read` |

### Resource Exhaustion

| # | Location | Resource | Triggered By | Bound | Severity | Impact | Action |
| - | -------- | -------- | ------------ | ----- | -------- | ------ | ------ |
| 1 | api/server.go:88 | time | any client holding a connection open | `http.ListenAndServe` with no timeouts; no proxy in the deployment evidence | Medium | High | `http.Server{ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 30 * time.Second}` |

### Dependency and Supply-Chain Risks

| # | Location | Issue | Evidence | Severity | Impact | Action |
| - | -------- | ----- | -------- | -------- | ------ | ------ |
| 1 | web/package.json:1 | no-lockfile | dependencies present; no package-lock.json, pnpm-lock.yaml, yarn.lock, or bun.lock in web/ or the root | Medium | Medium | Commit the lockfile the team's package manager writes |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).
```
