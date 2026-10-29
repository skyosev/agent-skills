---
name: security-hunter
description: Audit Go, Python, or TypeScript code for exploitable weaknesses — hardcoded secrets, injection, unvalidated boundary input, insecure configuration, auth gaps, sensitive data exposure, weak cryptography, resource exhaustion, dependency and supply-chain risks. Defaults to the codebase.
disable-model-invocation: true
---

# Security Hunter

Audit code for **exploitable weaknesses** — places where someone outside the system can make it do what its owner
did not intend: `db.Query(fmt.Sprintf("… %s", r.URL.Query().Get("id")))` on a public route, `SECRET_KEY =
'django-insecure-…'` in the settings module the Dockerfile loads, `jwt.decode(token)` whose `sub` selects the
account, `router.delete("/admin/users/:id", h)` beside a peer that requires an admin, `io.ReadAll(r.Body)` with no
limit. Goal: **every value that crosses a trust boundary is checked before it is interpreted, stored, or decided on;
no credential lives in a committed file; every protected action is protected on every route.**

**Not covered (owned by other hunters):** type-system bypasses (`as any`, `as unknown as T`, `@ts-ignore`,
`strict: false`, Go bare type assertions), the unguarded type claim at a trust boundary, races on goroutine shared
state, the unchecked conversion of external input to a named constant type (→ invariant-hunter); the wrong status for
a failure, the handler shape of a fail-open catch, panics on input (→ exception-hunter); linter suppressions
(`#nosec`, `# nosec`, `eslint-disable security/…`) and narration (→ slop-hunter); Primitive Obsession for identity
types (→ smell-hunter); concurrency structure more complex than its workload (→ simplicity-hunter); weak patterns
inside tests, tests that assert insecure behavior (→ test-hunter). Check-then-act races on persistent state (a
balance read, then a debit) and request-reachable deadlocks are reported by no hunter. Where ownership is
*contested*, the category's **Ownership:** note in What to Hunt is authoritative.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `perf-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

Category names are canonical: the heading here, in What to Hunt, and in the report are identical.

| Category | Core signal | Action |
| -------- | ----------- | ------ |
| Hardcoded Secrets | A live credential literal in a committed file | Move to the environment or a secret manager; rotate |
| Injection | Untrusted input reaches an interpreting sink without a content check | Parameterize, allowlist, canonicalize and prefix-check, escape, safe deserializer |
| Unvalidated Boundary Input | Untrusted input reaches a storing sink or a business decision with no content check | Parse with a schema at the boundary; reject, do not coerce |
| Insecure Configuration | A permissive transport or framework setting effective in production | Restrict; opt in to permissive values with a stated reason |
| Auth Gaps | A request reaches a protected action without the check its peers have, or with a check the client controls | Apply the peer's middleware; decide server-side; verify signatures |
| Sensitive Data Exposure | A secret, credential, or personal datum leaves through a channel it should not | Redact; generic error bodies; httpOnly cookie; encrypt at rest |
| Weak Cryptography | A primitive that does not provide the property the use needs | bcrypt / argon2 / scrypt; CSPRNG; constant-time compare; pinned algorithms |
| Resource Exhaustion | Work or allocation a request can grow without a bound | Body and payload limits; timeouts; worker pools; depth and complexity limits; limiter on credential endpoints |
| Dependency and Supply-Chain Risks | Dependency resolution that cannot be verified or pinned, or a CVE a configured tool reported | Lockfile; pin; checksum verification on; fetch by hash |

## Core Principles

1. **Scans and detectors nominate; tracing decides.** Nothing is a finding until Phase 4 has found the untrusted
   source, read the path, and named the auth in front of the boundary (Phase 4 lists what a setting or a secret
   needs instead). Tracing starts with reachability: a sink in a
   function no recorded boundary reaches is closed without a trace, so the budget goes to the paths that exist.
   Nominators are narrow for the same reason (a `go` statement inside a loop, not every `go`; Python `subprocess`
   with a string command, not every `subprocess` call).
2. **Every finding names its attacker.** Who sends the input (anyone, an authenticated user, an admin, another
   service) and what they get. Severity follows that, never the pattern.
3. **Content checks live at the boundary.** A value is parsed once where it enters, and typed code downstream trusts
   the parsed value. A check downstream of the first use is too late; a check at every layer is not asked for
   (defense in depth is a remedy option, not a finding).
4. **Settings are judged where they take effect.** A permissive value in a module the deployment does not load is
   not a finding; a value whose gate cannot be found is stated as unknown.
5. **Default to deny.** An auth check that cannot decide denies; a route without a decision inherits its peers'.

## Terms

- **Trust boundary** — a place where a value enters the process from outside (a request, a message, a file, the
  environment, a CLI argument); each language reference's Boundary inventory lists the kinds. Data another tenant
  stored is external too, but nothing inventories it, so second-order injection is a blind spot.
- **Untrusted input** — a value that crosses a trust boundary, and every value derived from it before a content
  check.
- **Content check** — a check on the *value*: a schema parse (Zod, Pydantic, struct validation), a range, a length, a
  format, an allowlist, canonicalization plus a prefix check. A check ends untrustedness only for the property it
  establishes: `z.string()` proves a string, not a safe SQL fragment, so a schema type never closes an Injection
  candidate; only the sink's own remedy (parameterization, escaping, a path check) or a shape the sink cannot
  misinterpret (digits, an enum, a UUID) does. A type guard alone (`typeof`, `isinstance`, a Go type assertion) is
  not a content check; it is invariant-hunter's concern.
- **Interpreting sink** — an operation that reads its argument as code, a query, a command, a path, a URL, markup,
  or a serialized object: SQL or NoSQL query text, `exec`, `eval`, a deserializer, `os.Open`, `fetch(url)`,
  `innerHTML`, a redirect target, a response header value.
- **Storing sink** — an operation that persists or sends the value as data: an insert or update, a file write to a
  fixed path, a message publish, a business decision (`if amount > limit`).
- **Credential endpoint** — a route that accepts a secret the caller proves possession of: login, password reset,
  OTP or 2FA verification, token or API-key issue, account recovery.
- **Peer route** — a route registered by the same mechanism in the same file or router group (the same `router`, the
  same controller class, the same `urlpatterns`).
- **Protected action** — a route that mutates or returns a record selected by a client-supplied id where the record
  has an owner or tenant column, or that writes a privilege or money column.
- **Credential literal** — a committed value with a credential's format (`AKIA…`, `sk_live_…`, `ghp_…`, a PEM private
  key, a connection string with a password) or a credential's use (`password = "…"` read by a client), that is not a
  placeholder, a published example, or a format-marked test key. Liveness is never tested; it is inferred from
  format and use (Hardcoded Secrets, Severity).
- **Effective in production** — a configuration value is effective when its file is the one the deployment loads
  (`DJANGO_SETTINGS_MODULE` in a Dockerfile, compose file, or CI; `NODE_ENV` gating; an unconditional literal), or
  when no gate separates it from production. With no deployment evidence in the repository, the cell says `unknown`.
- **Reachability** — the traced path from a trust boundary to a sink: the boundary read, each hop, the sink, and the
  auth in front of the boundary.
- **Target scope** — the files a finding may anchor at; every other file is read as context: the boundary, the
  middleware chain, the settings module, the deployment files (Phase 1 step 4, Two surfaces).

## What to Hunt

### Hardcoded Secrets

A live credential literal in a committed file: source, test, config, YAML, `.env`, Dockerfile, CI file, comment, or
documentation.

**Kinds** (the report's Credential column names what it unlocks): `api-key`, `password`, `connection-string`,
`private-key`, `token` (a JWT, a session token, a bearer value), `signing-secret` (Django `SECRET_KEY`, Flask
`secret_key`, a JWT secret, a webhook secret), `default-credential` (a secret-looking default in a signature or a
settings class).

**Signals:**

- The `security-common.md` secret scans.
- The language forms each reference's Applicability table lists (a Python default argument, a Pydantic `Settings`
  default, a Django `SECRET_KEY` in the settings module the deployment loads). A secret name under a public env
  prefix is Sensitive Data Exposure (`public-env`); a literal value there is also here.

**Not a finding:**

- A placeholder: `changeme`, `password`, `xxx`, `<your-key>`, `TODO`, `example`, `dummy`, a string of one repeated
  character, `${VAR}` / `os.environ[...]` / `process.env.X` interpolation.
- A published example: the jwt.io sample token, or any JWT whose decoded payload is an obvious example; AWS's
  documented keys (`AKIAIOSFODNN7EXAMPLE`, `AKIAI44QH8DHBEXAMPLE`, the matching `…EXAMPLEKEY` secret); a value a
  vendor's documentation prints.
- A public identifier: a Stripe publishable key (`pk_live_`), a Google Maps browser key with a referrer restriction
  stated, a Sentry DSN (public by design), an OAuth client id.
- A value in a `.env.example` with a placeholder; a `*.pem` that is a CA certificate (no `PRIVATE KEY` block).
- A format-marked test key (`sk_test_`, `rk_test_`, `pk_test_`) anywhere, fixture or not: the format itself says the
  key reaches no production account.

**Evidence bar:** the Code cell shows the literal truncated to its recognizable prefix and four characters
(`references/report-format.md`); the Credential cell names the kind and the system it unlocks (the host in a
connection string, the service behind a key format, the signer for a signing secret). For `default-credential`, the
call or settings object that would use the default.

**Action:** read it from the environment or a secret manager; rotate the committed value (the repository's history
holds it); add the file pattern to `.gitignore` when a file was committed. For a signing secret: rotate and
invalidate sessions.

**Ownership:** a secret in a comment, in AI narration, or in a test fixture is here (doc-hunter, slop-hunter, and
test-hunter route it here).

**Severity:** Critical when the literal is a complete credential (a key id with its secret key, a `sk_live_` /
`rk_live_` key, a private key with the service it unlocks, a connection string with its password, a signing secret)
and production code or the deployed configuration reads it, or its format marks a live account (`sk_live_`); High for
a complete credential whose use the trace did not find (a key pair in a comment, a stray `.pem`); Medium for a partial
credential (an `AKIA` id with no secret key in the repository, a user and host with no password); Low for an unmarked
sandbox credential. `AKIA` / `ASIA` and PEM mark a key type and an encoding, not production; an access-key id alone
authenticates nothing (AWS access-key reference). The Credential cell says what the format or use implies, never that
the credential was tested.

### Injection

Untrusted input reaches an interpreting sink without a content check on the path.

**Kinds** (the report's Sink column): `sql`, `nosql`, `command`, `code` (`eval`, `Function`, `exec`, `compile`, `vm`),
`deserialization` (`pickle`, `marshal`, `yaml.load` with an unsafe loader, `jsonpickle`), `path`, `html` (server
template, DOM sink, `mark_safe`, `template.HTML`), `header`, `redirect`, `ssrf`, `xxe` (lxml with entity
resolution), `proto` (a recursive merge, a set-by-path, or an `Object.assign` whose result is read for inherited
keys, fed untrusted keys). LDAP and XPath injection have no scan and no Phase 5 question, so they are not kinds.

**Signals:** each language reference's scans nominate the sinks; the boundary inventory supplies the sources. Two
shapes no scan names: a list-form command whose program accepts option-like arguments from input; a lexical path
check (`IsLocal`, `is_relative_to`, a prefix check) under a base that can hold attacker-created entries (an upload
directory), which a symlink defeats.

**Not a finding:**

- A parameterized query (`$1`, `%s` with a tuple, `?`, a tagged `sql` template, an ORM call with a dict); query text
  that is a literal or a constant; a table or column name chosen from an allowlist.
- A command in list form whose program is a literal and takes no option-like argument from input.
- A path checked with `filepath.IsLocal` (Go), `Path.resolve().is_relative_to(base)` (Python), or `path.resolve` plus
  a `startsWith(base + sep)` check (TypeScript) on the same value the open uses, under a base that holds no entries
  an attacker created; `os.Root.Open` on any base; a file name taken from an allowlist, or an id mapped to a path.
- A redirect to a URL validated against an allowlist of hosts or paths, or built from a path-only input with a
  leading `/` and no `//`, `\\`, or scheme.
- SSRF: a URL whose host is literal or chosen from an allowlist; a client with an outbound allowlist the code shows.
- `innerHTML` with a sanitized value (DOMPurify, bleach, `html.escape`) or a literal.

**Evidence bar:** the Source cell names the boundary field (`req.query.id` at `file:line`); the Path cell lists each
hop as `file:line`; the Sink cell names the kind and the call; the finding states the auth in front of the boundary
(none, session, admin). No source traced → no finding.

**Action:** parameterize; list-form commands with a literal program; the path checks above, and on a writable base
`os.Root` (Go ≥ 1.24), `openat2` with `RESOLVE_BENEATH`, or a `realpath` check on the opened file; `html/template`,
autoescape, `textContent`, a sanitizer; a host allowlist for outbound URLs; `yaml.safe_load`, or JSON instead of
`pickle`; `Object.create(null)` maps, `hasOwnProperty` reads, and key allowlists for merges. A branded type for the
validated string is an option the Action may name, never the finding.

**Ownership:** an unguarded cast on the same path is invariant-hunter's (both findings stand at different sites).

### Unvalidated Boundary Input

Untrusted input reaches a storing sink or a business decision with no content check, so an out-of-range, over-long,
wrong-format, or unexpected-field value is persisted or acted on.

**Signals:**

- A body or query field written to storage or passed to a service without a schema parse on the path: Go
  `json.NewDecoder(r.Body).Decode(&req)` then `repo.Save(req)` with no validation call; Python `request.json["n"]`
  used in `Order(quantity=n)`; TypeScript `await Order.create(req.body)`.
- Mass assignment: the whole body persisted (`create(req.body)`, `Model(**request.json)`, `update(id, req.body)`,
  `copier.Copy(&model, &req)` with no field list), **and** the model has a named column the route must not set
  (`price`, `status`, `balance`, `credits`, `verified`, `discount`) that the body can reach; the Reaches cell names
  that column (routing rule 9). A model whose every column is meant to be client-settable (a profile with name and
  bio) is not a finding.
- A file upload stored with the client's content type or extension trusted (routing rule 10).
- Python `assert` as the only check on external input (stripped under `-O`).
- A CGO call whose argument comes from a boundary with no length or range check (Go).
- A numeric or enum field converted with no range check at a boundary (`Status(n)` from a body; invariant-hunter keeps
  the unchecked conversion, this category the content).
- A schema that exists but is bypassed on one route while its peers parse.

**Not a finding:**

- A field that is only compared, returned, or logged (a wrong value changes nothing persisted).
- A schema parse on the path (Zod, Joi, class-validator with `ValidationPipe`, a Pydantic model, marshmallow, Go
  struct validation via `validator` tags with a `Validate` call, protobuf validation), even when its inferred type is
  not used downstream (that is invariant-hunter's, if anything). A schema that admits a value the sink mishandles
  (`z.number()` for a quantity the handler debits; `int` for a `limit` the query uses with no cap) is a finding only
  when the Reaches cell names that value and what it does; "the schema could be stricter" is not.
- Framework-level validation the code shows is applied (each language reference's Not-a-finding list).
- A write of an opaque blob the service never interprets (a file body stored under a server-chosen name).

**Evidence bar:** the Boundary cell names the route; the Field cell the input; the Reaches cell the sink or decision
and what a wrong value does there (a negative quantity stored; an arbitrary `status` written; a 10 MB string in a
`VARCHAR`). The content check searched for and not found is named.

**Action:** parse with a schema at the boundary and pass the parsed value inward; runtime field selection for
persistence (`schema.pick(...)` / `.strict()`, `whitelist: true`, `extra = "forbid"`, lodash `pick`, a DTO the pipe
strips to), never TypeScript's `Pick<T, K>`, which is a type and removes no property at runtime; reject, never coerce
or default.

**Ownership:** the unguarded type claim is invariant-hunter's; this category is the content.

### Insecure Configuration

A permissive transport or framework setting that is effective in production.

**Settings** (the report's Setting column):

- `tls-verify` — verification disabled; also package-fetch switches in build files: `npm config set strict-ssl
  false`, `pip --trusted-host` / `PIP_TRUSTED_HOST`, `NODE_TLS_REJECT_UNAUTHORIZED=0` in a Dockerfile or CI step.
- `tls-version` — a minimum below TLS 1.2.
- `cors` — a wildcard or reflected origin with credentials; `origin: true`.
- `cookie` — a session cookie without `Secure`, `HttpOnly`, or `SameSite`.
- `csrf` — protection disabled or exempted on a state-changing route with cookie auth.
- `debug` — debug mode, GraphQL introspection or playground, `maskedErrors: false`.
- `diagnostics` — `net/http/pprof` or `expvar` registered on a served mux with no auth.
- `perms/tmp` — two rules: any world-writable mode (`0666`, `0777`, `os.ModePerm`) on a file or directory the process
  creates; a group- or other-readable mode (`0644`, `0640`, `0755`) on a file the code shows holds a secret, key, or
  token. Also `tempfile.mktemp`.
- `headers` — a CSP with `unsafe-inline` / `unsafe-eval`, or `contentSecurityPolicy: false`, on a page that renders
  user content.
- `trust-proxy` — `trust proxy: true` with no proxy, so a client can set `X-Forwarded-For`.
- `ws-origin` — a WebSocket server with no origin check and cookie auth.
- `hosts` — `ALLOWED_HOSTS = ['*']`.

Binding `0.0.0.0` is not a setting here: every container, PaaS, and ingress requires it.

**Signals:** each reference's scans; the Phase 1 deployment evidence decides the Effective In cell.

**Not a finding:**

- A value in a dev-only settings module, behind `if app.debug` / `NODE_ENV !== 'production'`, or in a file the
  deployment evidence shows is not loaded.
- `InsecureSkipVerify: true` / `verify=False` / `rejectUnauthorized: false` in a client that pins the certificate
  another way the code shows (`VerifyPeerCertificate`, a custom `checkServerIdentity`, a CA bundle for a local test
  server), with the reason in a comment the code confirms.
- CORS `*` without credentials on a public read-only API.
- A missing `SameSite` on a cookie that is not a session or CSRF cookie.
- `trust proxy` set when the deployment evidence shows a reverse proxy.

**Evidence bar:** the Setting and Value cells; the Effective In cell names the file the deployment loads (or
`unconditional`, or `unknown`). For `cookie`, the cookie's role (session, CSRF, preference). For `diagnostics`, the
mux and its auth.

**Action:** enable verification; an explicit `MinVersion: tls.VersionTLS12` only where the version gate says the
default is lower; an origin allowlist; `Secure; HttpOnly; SameSite=Lax` on session cookies; CSRF middleware or a
non-cookie auth; debug and introspection off in production; a protected mux, or none, for pprof; `0600` for secret
files, `0755` at most for anything else; `mkstemp`.

**Ownership:** a permissive `#nosec` / `# nosec` suppression is slop-hunter's.

### Auth Gaps

A request reaches a protected action without the authentication or authorization check its peers have, or with a
check the client controls.

**Kinds** (the report's Kind column):

- `no-auth` — a route with no auth in its chain while its peers have one; or, with no peer that has auth, a route that
  performs a protected action (Terms) with none.
- `client-claim` — a role, tenant, owner, or permission read from the request body, the query, or an unverified token
  and used in a decision or persisted.
- `idor` — an object loaded by a client-supplied id and returned or mutated with no ownership or tenant check, where
  peers check.
- `fail-open` — an auth check whose error path grants access: `if err != nil { next() }`, `except Exception: pass`
  around a token verify, a `try` / `catch` that falls through to the handler.
- `unverified-signature` — `jwt.decode` / `decodeJwt` where a claim it returns is trusted; `algorithms` including
  `none`; `verify: false`; a webhook handler with no signature check while the provider supplies one; a session
  cookie read without the framework's signing.
- `session` — no expiry on an issued token; a session id not rotated at login where the framework does not do it.

**Signals:** the route and auth inventories from Phase 1; the reference scans for JWT and webhook calls, privilege
fields, and fail-open shapes.

**Not a finding:**

- A route whose auth is applied globally (a global guard, `app.use(auth)` before the router, NestJS `APP_GUARD`,
  Django middleware) and not repeated per route; a route marked public on purpose where the mechanism shows it
  (`@Public()`, `AllowAny`, a documented health or login route).
- A read of a public resource with no ownership concept (a product catalogue).
- A role read from a *verified* token's claims; a tenant id taken from the session and compared with the record.
- `jwt.decode` used only to read a non-security claim (a `kid` to pick the key) before `verify`.
- A webhook from a provider that offers no signature (the Action may name IP allowlisting).
- With no authenticated peer and no protected action, a route public by nature (signup, login, contact,
  password-reset request, health, a webhook receiver, whose auth is its signature): the inherited decision is public.

**Evidence bar:** `no-auth`: the route, its chain, and the peer route with its chain; without a peer, the
protected-action evidence (Terms). `client-claim`: the
field, its source, and the decision or write it reaches. `idor`: the id source, the load, and a peer that checks
ownership (or the record's owner column that is never compared). `fail-open`: the check and the error path that
continues. `unverified-signature`: the decode call, the library, and the claim the code trusts. `session`: the issue
site and the missing field.

**Action:** apply the peer's middleware; decide from the session or a verified token, never from the body; compare
the record's owner or tenant with the session; deny on error; `jwt.verify` with pinned `algorithms`; the provider's
signature verification with a constant-time compare; `expiresIn`; session regeneration at login.

**Ownership:** the handler shape of a fail-open catch (`except Exception: pass`) is exception-hunter's Swallowed
Errors; the access it grants is here. A check-then-act race on auth or account state is reported by no hunter.

### Sensitive Data Exposure

A secret, credential, or personal datum leaves through a channel it should not.

**Channels** (the report's Channel column):

- `log` — a log call whose arguments include a password, token, cookie, authorization header, card number, national
  id, or a whole request or headers object.
- `response` — an error body with `err.Error()`, a stack trace, a SQL statement, an internal path, or an object with
  more fields than the client needs when one of them is sensitive.
- `url` — a token, password, or personal datum in a query string or path, which servers and proxies log.
- `client-storage` — a token or secret in `localStorage` / `sessionStorage` / a non-httpOnly cookie.
- `storage` — a password or secret stored in plaintext; a personal datum in a world-readable file.
- `public-env` — a secret name under a bundler's public prefix: `NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, `EXPO_PUBLIC_`,
  `NUXT_PUBLIC_`, `PUBLIC_`.

**Not a finding:**

- A log that names the field without its value (`"password rotated for user %s", id`).
- An error body with a generic message and a correlation id; a stack trace behind a debug gate that production
  evidence shows off.
- A JWT in an `Authorization` header (not a URL).
- `NEXT_PUBLIC_API_URL` and other public names that hold no secret.

**Evidence bar:** the Data cell names the datum and how the finding knows it is sensitive (the variable's name, its
source field, the header name); the Channel cell names the call and, for `response`, the route; for `storage`, the
write and the schema or model field; for `public-env`, the prefix and the deployment or `.env` line.

**Action:** redact or drop the field; structured logging with a redaction list; separate internal and external error
messages; move tokens to httpOnly cookies or memory; hash passwords (Weak Cryptography then judges the algorithm);
rename the env var out of the public prefix.

**Ownership:** the wrong HTTP status for a failure is exception-hunter's Untranslated Boundary Errors; the internal
detail in the body is here. Error-response shape and `Content-Type` are not judged.

### Weak Cryptography

A primitive that does not provide the property its use needs.

**Primitives and uses** (the report's Primitive and Used For columns):

- MD5, SHA-1, or unsalted or single-round SHA-2 for `password storage`; bcrypt cost below 10, or `argon2` with
  parameters below the library's defaults, for `password storage`; Python `hashlib.md5(..., usedforsecurity=True)`
  when the use is a password.
- A non-cryptographic RNG (`math/rand`, `math/rand/v2`, Python `random`, `Math.random`, `uuid1`) for a `token`,
  `session id`, `reset code`, `nonce`, or `salt`.
- `==` / `===` / `bytes.Equal` on a `signature`, `hmac`, `token`, or `otp` (a timing leak).
- DES, RC4, Blowfish, ECB mode, or a static IV for `encryption`; `createCipher` (a key derived from a password with
  MD5, no IV); a hand-rolled hash or cipher.
- JWT verification that lets the token choose between HMAC and a public key (`algorithm confusion`), at the library
  versions and key forms the language references' version gates name.

**Not a finding:**

- MD5 or SHA-1 for a non-security checksum: a cache key, an ETag, a dedup key, a git object id, a content hash
  compared with no attacker-controlled input.
- `math/rand` / `random` for shuffles, jitter, sampling, test data.
- Comparison of a *hash* with `==` where the hash is of a password the server computed and the comparison input is
  not attacker-timed (judged; the library's `check_password` / `bcrypt.compare` is the Action anyway).
- A verification with pinned algorithms (`algorithms: ['RS256']`, PyJWT `algorithms=[...]`, golang-jwt
  `jwt.WithValidMethods`), and every unpinned form the version gates clear. Pinning without an exploit is not a row.
- SHA-256 for a token the server stores and looks up (hashing a high-entropy token is fine).

**Evidence bar:** the Primitive cell names the call; the Used For cell names the value's role, from its name, its
source, or its consumer (the function stores it as `password_hash`; the value is sent as a reset link). Without a
role, no finding.

**Action:** `bcrypt` / `scrypt` / `argon2id` via the framework's hasher; `crypto/rand` (`rand.Text` on Go ≥ 1.24),
`secrets.token_urlsafe`, `crypto.randomBytes` / `randomUUID`; `subtle.ConstantTimeCompare`, `hmac.compare_digest`,
`crypto.timingSafeEqual`; AES-GCM or a library's authenticated encryption; a pinned algorithm list.

**Ownership:** plaintext password storage is Sensitive Data Exposure (`storage`); routing rules 3 and 4 split the
rest.

### Resource Exhaustion

Work or allocation a request can grow without a bound the code or the framework sets.

**Resources** (the report's Resource column):

- `memory` — `io.ReadAll(r.Body)` with no `MaxBytesReader`; a multipart form with no `maxMemory` and no size check;
  Flask with no `MAX_CONTENT_LENGTH`; Starlette / FastAPI `await request.body()` with no limit; an upload with no size
  cap; decompression of client data with no size cap; an image decoded with no dimension cap.
- `cpu` — a regex compiled from input in Python or TypeScript; a literal pattern with a nested or overlapping
  quantifier (`(a+)+$`, `(\w+\s?)*$`, `(x|xy)*`) run on boundary input, which needs no pattern injection, even
  behind a length cap (`re.fullmatch(r"(a+)+$", "a" * 25 + "!")` runs for about a second in Python), so the Action
  is the rewrite or RE2; a GraphQL server with no depth or complexity limit; bcrypt on an unbounded password length.
- `concurrency` — a goroutine, thread, or task per request item with no pool or semaphore;
  `Promise.all(items.map(fetch))` on a client-sized list; a WebSocket server with no `maxPayload` or message rate
  limit.
- `time` — `http.ListenAndServe` or an `http.Server` with no `ReadHeaderTimeout`; a Node server with the default
  `headersTimeout` behind no proxy (judged).
- `attempts` — a credential endpoint with no limiter while its peers have one.

**Not a finding:**

- A body or message bounded by a framework default at the recorded version (each language reference's version
  gates), or by `http.MaxBytesHandler` / `MaxBytesReader` on the path. A default or raised limit is a finding only
  when the route's payloads have no reason to approach it.
- A goroutine or task count bounded by a pool, an `errgroup.SetLimit`, a semaphore, `asyncio.Semaphore`, `p-limit`.
- A literal pattern without a nested or overlapping quantifier. A regex from input run by Go `regexp` (linear time)
  or by a library the code shows is RE2 (the `re2` npm package, Python `google-re2`).
- GraphQL with persisted queries only, or with `graphql-armor` / `depthLimit` / complexity rules in the
  `validationRules`.
- A credential endpoint when the deployment evidence shows a gateway limiter (a `rate_limit` in an ingress
  annotation, a Cloudflare rule in the repository).
- Rate limiting on any route that is not a credential endpoint; a missing timeout on an outbound client call
  (reliability, not security).

**Evidence bar:** the Resource cell; the Triggered By cell names the boundary and the client-controlled dimension
(body size, list length, nesting depth, pattern or matched text); the Bound cell names the missing limit and the
framework default the finding checked. For `attempts`, the peer route with a limiter. With no limiter anywhere in the
repository there is no row: one Low entry under Recommendations names the credential routes and says a gateway may
provide the limit.

**Action:** `http.MaxBytesHandler` / `MaxBytesReader`; `MAX_CONTENT_LENGTH`; a `limit` on body parsers where the
default is wrong for the route; a size cap before decompression (`io.LimitReader`, a `zipfile` member size check);
`ReadHeaderTimeout` and `ReadTimeout`; a pool or semaphore; depth and complexity limits; RE2 or a pattern allowlist;
a limiter on credential endpoints (`express-rate-limit`, `slowapi`, `golang.org/x/time/rate`).

**Ownership:** a data race in the fan-out is invariant-hunter's. A worker pool more complex than its workload needs is
simplicity-hunter's, which judges the structure; this category judges the bound.

### Dependency and Supply-Chain Risks

Dependency resolution the repository cannot verify or pin, or a vulnerability a configured tool reported.

**Issues** (the report's Issue column):

- `no-lockfile` — a manifest with dependencies and no committed lockfile.
- `unpinned` — `requirements.txt` lines with no `==`, `package.json` ranges of `*`, `latest`, `>=`, or `x`, when the
  deployment installs from that file rather than from a lockfile.
- `vcs-dependency` — `git+`, a tarball URL, `github:`, or `file:` sources in a manifest.
- `local-replace` — a `go.mod` `replace x => ../y` whose target lies outside the repository, in a module that is
  deployed.
- `checksum-bypass` — `GOSUMDB=off`; `GONOSUMDB` / `GOPRIVATE` wider than the organization's namespace the module
  path shows: the two settings that skip the checksum database.
- `remote-install` — `curl … | sh`, `wget … | bash`, `pip install` from a URL, an `npx` of an unpinned package, in a
  Dockerfile, a CI file, or the project's own `postinstall`.
- `cdn-script` — a `<script src="https://…">` with no `integrity` attribute in a served template.
- `cve` — a vulnerability a configured `govulncheck`, `pip-audit`, or `npm audit` run reported, with its id.

Lifecycle scripts of third-party dependencies are not judged: they live in `node_modules`, which is untracked and
excluded.

**Not a finding:**

- The Go module cases the Go reference's Not-a-finding list names (`replace`, `go.sum`, `GOPRIVATE`, `GOFLAGS`).
- Caret and tilde ranges with a lockfile committed that the install step uses (`npm ci`, `pnpm install
  --frozen-lockfile`, `poetry install`, `uv sync`); `requirements.in` unpinned beside a pinned `requirements.txt`. A
  `poetry.lock` beside a `requirements.txt` that the Dockerfile installs with `pip install -r` constrains nothing: the
  deployment evidence decides which file is the input.
- A CDN script with `integrity` and `crossorigin`; a first-party static asset.
- The project's own `postinstall` that runs a local script (husky, patch-package).

**Evidence bar:** the Location is the manifest line (or the Dockerfile or CI line); the Evidence cell names what is
missing or what the tool reported (the lockfile names searched for; the CVE id and the tool's output line).

**Action:** commit the lockfile; pin, or use the lockfile's resolution; checksum verification on; fetch by digest or
pinned version; `integrity` attributes; upgrade the reported package (the tool's fixed version).

**Ownership:** none contested. Findings anchor only at manifests in the target scope (Two surfaces); a manifest
outside the scope is read as context.

### Within-skill routing

One site, one finding. The rules, in order:

1. **A credential literal is Hardcoded Secrets wherever it sits** (a settings module, a settings-class default, a
   signature default). The same name read from the environment is not a finding anywhere.
2. **The sink decides Injection vs Unvalidated Boundary Input.** An interpreting sink → Injection. A storing sink or a
   business decision → Unvalidated Boundary Input. A privilege, ownership, or tenant field from the client → Auth Gaps
   (`client-claim`), whatever the sink.
3. **Verification decides Auth Gaps vs Weak Cryptography.** A signature not verified → Auth Gaps
   (`unverified-signature`). A verified signature with a weak primitive or an unpinned algorithm list → Weak
   Cryptography.
4. **Settings vs primitives.** TLS verification and minimum version, cookie flags, CORS, CSRF, debug, file
   permissions, exposed diagnostics → Insecure Configuration. Hash, RNG, cipher mode, comparison → Weak Cryptography.
5. **A missing bound is Resource Exhaustion; a permissive value is Insecure Configuration.** No `ReadHeaderTimeout`
   → Resource Exhaustion (`time`). `introspection: true` → Insecure Configuration (`debug`).
6. **The channel decides Sensitive Data Exposure vs Hardcoded Secrets.** A secret in a log, response, URL, or client
   storage → Sensitive Data Exposure at that line. The literal in source → Hardcoded Secrets at its line. Both can
   exist for one value.
7. **Regex from input.** Python and TypeScript → Resource Exhaustion (`cpu`). Go → not a finding. Never Injection.
8. **Deserializers and XML.** An unsafe deserializer on untrusted bytes → Injection (`deserialization`); external
   entities → Injection (`xxe`); entity expansion as a denial of service → Resource Exhaustion (`memory`), only for a
   parser the version gate marks vulnerable.
9. **Mass assignment.** The whole body persisted with a named non-privilege column the route must not set (price,
   status, balance) → Unvalidated Boundary Input; with a privilege or ownership column reachable → Auth Gaps
   (`client-claim`), one finding; with no such column → not a finding.
10. **Uploads.** The client's file name in the path → Injection (`path`); the client's content type trusted →
    Unvalidated Boundary Input; no size cap → Resource Exhaustion (`memory`). Three sites, up to three findings.
11. **A justifying comment** is judged with its site, in the category of the site. It is never a separate finding.
12. **Build-file switches.** A switch that turns off TLS for a package fetch → Insecure Configuration (`tls-verify`;
    Effective In is the Dockerfile or CI step). A switch that skips the checksum database → Dependency and
    Supply-Chain Risks (`checksum-bypass`).

## Applicability

All nine categories apply in Go, Python, and TypeScript. Each language reference's Applicability table states the
language's markers and the ones it lacks: Go has no ReDoS (`regexp` is RE2); Go and Python have no DOM sinks.

## Test-code scope

**Hardcoded Secrets runs over every committed file, test paths included:** a live key in a fixture is compromised.
Every other category excludes test paths: the language lists are test-excluded, and the other all-file scans use
`$ALL_NONTEST`. A weak pattern inside a test (`verify=False` against a local server) is not a finding;
a test that asserts an insecure behavior is test-hunter's Weak Tests. The exclusion is by path: a helper imported by
production code from a non-test path is audited.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is.** It measures consequence, not confidence. One scale; the rules below say
which evidence moves a finding up it.

- **Reachability governs Injection, Auth Gaps, and Unvalidated Boundary Input.**
  - **Critical** — the finding names the boundary, the path, and the sink, and no authentication stands in front of
    the boundary; or an auth bypass on a protected action (`no-auth` with the protected-action evidence,
    `unverified-signature` on a session token, `fail-open`). Examples: `db.Query(fmt.Sprintf(…,
    r.URL.Query().Get("id")))` on a public route; `pickle.loads(request.body)`; `jwt.decode(token)` whose `sub`
    selects the account.
  - **High** — the path needs an authenticated user or a precondition the finding names (a feature flag, a tenant
    role, a file the attacker must first upload); an `idor` on another user's record; a `client-claim` that escalates
    a logged-in user; an SSRF from an admin-only route; an `unverified-signature` on a webhook (forged events, not a
    session).
  - **Medium** — a traced path whose consequence is bounded (a header injection into a response nobody caches; a
    redirect on a page with no session).
- **Effective-in-production and missing-control govern Insecure Configuration, Sensitive Data Exposure, Weak
  Cryptography, and Dependency and Supply-Chain Risks.** High at most.
  - **High** — the value is effective in the deployed configuration, or the control is missing on the production
    path, and the consequence is a credential or a session that leaves the system's control: `DEBUG = True` in the
    deployed settings module; `math/rand` for a session id; MD5 for password storage; a secret under a public env
    prefix (shipped to every browser); `cve` with a reachable call and a fixed version.
  - **Medium** — the consequence is bounded, or the deployment evidence is `unknown`: a session cookie without
    `SameSite`; `err.Error()` in a response body; a password in a log; a token in `localStorage`; CORS `origin: true`
    with credentials on an API that also uses bearer tokens; a TLS minimum below 1.2; `no-lockfile`; `local-replace`;
    `checksum-bypass`; `remote-install`.
  - **Low** — hygiene: `unpinned`; `mktemp`; a `cdn-script`; a log at a debug level the production config the
    repository shows disables (the Action still asks for redaction); a short-lived token in `sessionStorage` for a
    pure SPA with no cookie option, when a comment states the trade-off and the code shows the lifetime.
- **Resource Exhaustion is High at most:** High on a public boundary (`io.ReadAll(r.Body)` on a public route; `new
  RegExp(req.query.q)`); Medium with a partial bound or an authenticated boundary, and for `time` and `attempts` (a
  slow client holds connections; one credential route lacks the limiter its peers have); Low for `time` behind a
  reverse proxy whose config in the repository names this listener's host or port as its upstream (nginx reads the
  whole header before it connects upstream), with the Bound cell noting that direct reachability of the backend is
  not established and the Action still naming `ReadHeaderTimeout`. A denial of service is never Critical.
- **Hardcoded Secrets** follow their own rule: format and use (the category's Severity paragraph).

Outside Hardcoded Secrets, Critical needs the traced path. A traced path whose boundary auth could not be determined
(middleware registered where the auth inventory did not look) takes High and says so in the Evidence cell
(`references/report-format.md`). An untraced path, or a hash whose role cannot be read, is no finding at any level.

**Impact — how much the change is worth:** exposure reduced, cognitive burden reduced, surface affected. Contextual;
never derived from occurrence count. A rotated secret is High impact whatever its Severity (the leak is already in
history); a per-route middleware fix on one of forty routes is Low; a global body limit is High.

- **High** — substantial reduction on code read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the evidence bar but touches a small, rarely hit surface

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve the raw manifest.** Scope may be:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, untracked. Resolve it with
     `references/diff-scope.md`.
   - **Path**: specific files, folders, or packages — `SCOPE=$(git ls-files --cached --others --exclude-standard
     -- <paths>)`, which expands folders to files
   - **Codebase**: the entire project (default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot, treat `scope.txt` as a **file manifest only**
   (one path per line): `SCOPE=$(cat <snapshot>/scope.txt)`. Read run metadata (base SHA — `$MB` in diff mode —
   surface kind, counts) from `scope-meta.txt` when present. Use the manifest verbatim; the resolution
   above is for standalone runs only.

   **Persist run state.** Shell variables do not survive between tool calls, and `rg … --` with an empty variable
   searches the whole working directory. Create one run directory (`RUN=$(mktemp -d) && echo "$RUN"`) and use the
   printed path literally from then on. Every call starts at the repository root (`cd "$(git rev-parse
   --show-toplevel)"`), because every list holds root-relative paths. Write `$SCOPE` to `<run>/scope.txt` and, in diff mode, `$MB` to `<run>/mb`.
   A later call restores what it uses (`SCOPE=$(cat <run>/scope.txt)`); an empty restore is a STOP, never an empty
   result. If the resolved surface exceeds the context budget, report the file count and ask to narrow or chunk.

   **Record provenance.** Capture `git rev-parse --short HEAD` and whether the working tree is dirty
   (`git status --porcelain -- $SCOPE`); both go in the report's Scope section. On a dirty tree, line numbers match no
   commit — state that findings must be re-located by symbol name.

   The raw manifest is **immutable** and language-independent: on a mixed scope it stays whole, so every hunter in a
   party audits the same surface.

   **Whitespace in paths is unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell expansion
   word-splits on spaces; whitespace paths are a declared limitation.

2. **Detect languages** from file extensions alone: the manifest's, or in codebase mode those of
   `git ls-files --cached --others --exclude-standard` (Scope records only their counts; the language scans still
   search `.`):
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — gets no language scans. Record `excluded — no reference for .<ext>: {count} files` in Scope, naming
   each extension. The all-file scans (Phase 3) still read those files: a committed key in a `.js` file is found.

3. **Load references.** Read `references/security-common.md` in every run, then, for every detected language,
   `references/security-<lang>.md` from the directory this SKILL.md was read from (e.g. `references/security-go.md`).
   **Fail closed:** if a required reference cannot be read, **stop and report**.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules **plus
   the test-path exclusion** to that language's files. These subsets are then immutable. Record in Scope: raw
   manifest count, each per-language eligible subset, the all-file list count, exclusions with the test paths listed,
   and `References loaded: common{, go, python, typescript as present}`.

   Drop from eligibility only: vendored trees, lockfiles, Markdown-only inputs, test paths, and generated files
   identified by each reference's authoritative **in-file marker** — **never** by filename guessing.

   Write each subset to `<run>/<lang>.txt` (`go.txt`, `python.txt`, `typescript.txt`). Codebase mode: the single line
   `.`. Diff and path mode: the eligible files, one per line — `comm -12 <(rg --files --type <t> $EXCLUDE | sort)
   <(printf '%s\n' $SCOPE | sort)` with the loaded reference's `--type` and `$EXCLUDE`, minus files carrying a
   generated-code marker (`| while read -r f; do rg -q -m1 '<marker>' "$f" || echo "$f"; done`, the marker regex built
   from the reference's eligibility section); the reference's generated-file globs are the same scan approximation a
   codebase run uses. Filter before scanning: `rg` applies `--type` and `--glob` only while walking a folder and
   searches every file named on its command line. Each scan call restores its list first — `GO_FILES=$(cat
   <run>/go.txt)` (`PY_FILES`, `TS_FILES`) — and the reference blocks pass it as `rg -H … -- $GO_FILES`: given one file,
   `rg` prints no file name unless `-H` is set.

   The lists are `$GO_FILES`, `$PY_FILES`, and `$TS_FILES`. A language with no eligible file gets no `<lang>.txt`.

   **Write the all-file list** `<run>/all.txt` as `references/security-common.md` (All-file list) describes: every
   committed file in codebase mode, the manifest in diff and path mode, test paths included.

   If no language list exists and the all-file list is empty: write `Audit completed: 0 findings — no eligible source
   in scope` and stop before scanning. With no language list and a non-empty all-file list (a repository of YAML,
   Dockerfiles, and templates), no language reference is loaded and only `security-common.md` runs.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Files outside it, test files included, are *read* as **context** (the boundary, the middleware chain, the
   settings module, the deployment files, a lockfile). Diff and path scope narrow the manifest, never the context
   reading.

5. **Record the security context** per language (report-format.md says which Scope lines print):
   - **Language versions:** the `go` directive and any `//go:debug` directive; `requires-python`; the Node major from
     `engines.node` or `.nvmrc`, else `unknown`. Library versions are resolved in Phase 4, only for candidates that
     depend on them. A remedy is proposed only when the recorded version supports it; with a version `unknown`, a
     default is judged by the reference's stated default and the Action names the version the remedy needs.
   - **Boundaries** and **Auth:** the boundaries each loaded reference's Boundary inventory lists, found with its
     inventory scans, with counts and files; and how auth is applied to them (global, per route, a framework default,
     or none found), with the files that apply it.
   - **Deployment evidence:** the environment settings the repository shows in Dockerfiles, compose files, CI,
     `Procfile`, `fly.toml`, or `render.yaml`. Settings outside the repository are not searched.

     ```bash
     ALL_FILES=$(cat <run>/all.txt)
     rg -H -n '(DJANGO_SETTINGS_MODULE|NODE_ENV|GODEBUG|GOSUMDB|GONOSUMDB|GOPRIVATE|PIP_TRUSTED_HOST|NODE_TLS_REJECT_UNAUTHORIZED|GIN_MODE|FLASK_ENV)\s*[=:]' -- $ALL_FILES
     ```

6. **Read repository instructions** (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`) for a stated security policy: a
   trusted internal boundary, a sanctioned `text/template` use, an allowlisted outbound host list. A policy changes
   no Severity and deletes no row; `references/report-format.md` (Policy line) says how covered rows are marked. An
   allowlist or a sanctioned use is a claim Phase 4 verifies in the code. A network restriction the deployment
   evidence shows (an ingress or network-policy file that names the service) is a precondition, priced by the
   reachability rule at High; prose is not evidence.

### Phase 2: Run Detectors

Run each detector that `references/security-common.md` and each loaded language reference's Detectors section name,
under the condition that section states (for every detector: the project configures it), with the read-only command
the section gives and the project's own config, mutation flags stripped (`references/security-common.md`). Its
output nominates. Keep a secret
detector's hits whose file is in `<run>/all.txt`, test paths included. Keep a code detector's diagnostics whose file
is in the language's eligible list; in codebase mode, where the list is `.`, drop diagnostics on test paths and on
paths the reference's `$EXCLUDE` globs match. Record one entry per detector on the Scope's Detectors line:

- `ran — <command>`. A run that printed its diagnostics is `ran`, whatever its exit code.
- `ran — new issues only — <command>`, when the project config limits the run to new issues. Its silence is not
  coverage.
- `skipped — not configured`, `skipped — no security-relevant rules enabled`, `skipped — configured, not installed`,
  or a skip reason the detector's section names (`skipped — jq missing`, `skipped — invocation resolves packages`).
- `errored — <message>`, when the detector stopped before analysis (a config, load, or option error, or a CVE tool
  that could not reach its database). Its output is not used.

Done when every detector the loaded references name has its Detectors entry, and every kept hit is listed as a
candidate.

### Phase 3: Scan for Candidates

Run `references/security-common.md`'s all-file and manifest scans over `$ALL_FILES`, then, for each language that has
a `<run>/<lang>.txt`, the loaded reference's Phase 3 scan block over that list, each restored in the same call
(Phase 1 step 4). Every hit is a candidate. Diff mode nominates from the working tree of the manifest files, not from
added lines, so an untouched secret in a changed file is a candidate. A file under `Deleted in diff` (a deleted auth
middleware) is context for Phase 4, never a finding by itself.

**Boundary pass.** Every recorded boundary is also a candidate for Auth Gaps (`no-auth`) and for Unvalidated Boundary
Input, so a route with no regex hit is still compared with its peers and its fields are still followed.

Done when every scan in `security-common.md` and in each loaded reference's Phase 3 block has run, every recorded
boundary is listed, and every hit is listed as a candidate.

### Phase 4: Trace Each Candidate

- **A sink:** first check that a recorded boundary reaches the enclosing function at all (its callers, up to the
  handler); a sink no boundary reaches is closed without a trace. Then find the untrusted source (the boundary read),
  each hop between, and the content check if any; record the auth in front of the boundary.
- **A route:** list its middleware chain and its peers'.
- **A configuration value:** find the file the deployment loads.
- **A secret:** decide credential or placeholder from its format and its use.
- **A library-gated candidate:** resolve the library's version from the lockfile and record it for the Scope line.

Tracing reads beyond the manifest in every mode. A trace the context budget cuts short is counted on the Scope's
`Untraced:` line and is not a finding.

Done when every candidate is closed as unreachable, counted as untraced, or traced.

### Phase 5: Evaluate Each Candidate

For each candidate: apply the category's **Not a finding:** lines and the loaded reference's Not-a-finding list;
apply the within-skill routing (if it moved the candidate, apply the routed category's lines too); cross-reference a
candidate that an **Ownership:** note gives to another hunter; clear the category's evidence bar; apply repository
policy (Phase 1 step 6). Run the Phase 5 block of `security-common.md` and of each loaded reference.

Assign **Severity and Impact** to every finding. Nothing is held back; `Audit completed: N findings` counts every
reported finding.

Done when every traced candidate is a reported finding, dismissed by a named Not-a-finding case, or handed off to
its owning hunter.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-security-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or
return mode (e.g. a party-mode orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched. Every detector runs with its
  read-only flags, so `git status` shows only the report file after the run.
- **Evidence required.** Every finding cites `file:line` with the exact code, and the category's
  evidence cells, named in `references/report-format.md`, are filled from code read, never inferred.
- **Comments are claims; the code is evidence.** A justifying comment (`// internal only`, `# nosec: trusted input`)
  is checked against the code — here, the boundary and its auth — never trusted.
- **One site, one finding.** When two categories describe the same code, the within-skill routing picks one, and the
  other is cross-referenced.
- **Never install.** Run only tools the project already has; a tool that is configured but absent is `skipped`, never
  fetched.
- **No network.** The hunter calls no network service, tests no credential, and reads no git history. The only
  exceptions are a configured CVE tool run through the repository's own invocation (`govulncheck`, `pip-audit`,
  `npm audit`), which reaches its vulnerability database, and a configured semgrep registry config (`p/…`).
- **Secrets truncated** in every report cell (`references/report-format.md`); secret detectors run with redaction
  (`references/security-common.md`).
- **Warn about the transcript.** When the report has a Hardcoded Secrets row, the final reply says the session
  transcript holds those credential lines until they are rotated.
- **Hand off.** A candidate another hunter owns is cross-referenced to that hunter and not scored here.
