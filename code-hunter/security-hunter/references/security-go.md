# Security Hunter — Go reference

Contents: Applicability · Generated-code and test-path eligibility · Language facts and version gates · Not a finding on these grounds alone — Go · Boundary inventory · Detectors · Phase 3 — security scans · Phase 5 — Go-specific evaluation

## Applicability

| Category | Applicable | Go note |
| -------- | ---------- | ------- |
| Hardcoded Secrets | **yes** | `security-common.md` scans; `var apiKey string = "…"` and `apiKey := "…"` included |
| Injection | **yes, no DOM sinks** | `database/sql` and builders, `exec.Command`, `os` file calls, `text/template` and `template.HTML`, `http.Get` / `NewRequest`, `http.Redirect`, response headers |
| Unvalidated Boundary Input | **yes** | a decoded body saved with no validation call; `copier.Copy` / `mapstructure.Decode` of a whole request; a CGO call fed by a boundary with no length or range check; `Status(n)` from a body |
| Insecure Configuration | **yes** | `InsecureSkipVerify`, `MinVersion` and the TLS default gate, CORS middleware, `http.Cookie`, `net/http/pprof` / `expvar`, octal file modes |
| Auth Gaps | **yes** | router middleware and groups, gRPC interceptors, golang-jwt parsing, webhook signatures, fail-open middleware |
| Sensitive Data Exposure | **yes** | log calls with credential words or a whole request; `err.Error()` and `debug.Stack()` in responses |
| Weak Cryptography | **yes** | `crypto/md5`, `crypto/sha1`, `crypto/des`, `crypto/rc4`, `math/rand`, `==` / `bytes.Equal` on a MAC, `bcrypt.MinCost` |
| Resource Exhaustion | **yes, no ReDoS** | `io.ReadAll(r.Body)`, multipart forms, decompression, goroutines in a loop, `ReadHeaderTimeout`, credential-endpoint limiters; `regexp` is RE2 |
| Dependency and Supply-Chain Risks | **yes** | `go.mod` / `go.work` `replace`, `go.sum`, `GOSUMDB` / `GONOSUMDB` / `GOPRIVATE`, configured `govulncheck` |

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. Scan globs such as `*.pb.go` /
`*_gen.go` / `*_generated.go` are approximations for scanning convenience; eligibility uses the marker.

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*_test.go`. Hardcoded Secrets still scans them
through the all-file list.

## Language facts and version gates

The version is the `go` directive in `go.mod`. A remedy is proposed only when that version supports it; a default is
judged by that version.

- Server default `MinVersion` is TLS 1.2 from Go 1.22; client default from Go 1.18.
- A lexical path check closes lexical traversal only. Under a base that can hold attacker-created entries (an upload
  or user-writable directory) a symlink defeats it: `filepath.IsLocal("link/data.txt")` is true and `os.Open`
  follows the link out of the base; `O_NOFOLLOW` does not stop an intermediate link; `os.Root.Open` refuses with
  "path escapes from parent" (Go 1.26).
- `filepath.IsLocal`: 1.20. `os.Root`: 1.24. `crypto/rand.Text`: 1.24. `http.MaxBytesHandler`: 1.18. `ServeMux`
  method patterns (`"GET /x"`): 1.22.
- `math/rand` is auto-seeded from 1.20 and is still not a CSPRNG.
- `regexp` is RE2: linear time in the input on every version. The parser's memory is capped at 256 MB since 1.19.2 /
  1.18.7 (GO-2022-1039), so no supported toolchain is exposed.

**Effective TLS default.** `tls10server` re-enables TLS 1.0 on a server when any source sets it and the toolchain that
builds the binary still knows the setting. Sources, in go.dev/doc/godebug precedence: `GODEBUG` in the deployment
evidence; `//go:debug` in the main package; `godebug` lines in `go.work` or the main module's `go.mod`
(`godebug tls10server=1`, or `godebug default=go1.21`, which selects the 1.21 defaults and so enables TLS 1.0 under a
`go 1.24` directive); else the `go` directive's defaults (TLS 1.0 on below 1.22). The build toolchain is the
`toolchain` directive, else the `golang:` image tag or `setup-go` version in the deployment evidence, else `unknown`;
a `go` directive ≥ 1.27 implies a toolchain ≥ 1.27. Go 1.27 removed `tls10server` (go.dev/doc/godebug), so on a
toolchain ≥ 1.27 every source is dead configuration; on 1.22–1.26 it is a `tls-version` finding. A value the gate
cannot establish is `unknown`; an `unknown` toolchain does not close a candidate whose other sources re-enable TLS
1.0. `security-common.md` nominates the `godebug`, `toolchain`, and `default=` lines and the
`GODEBUG` / `//go:debug` settings.

## Not a finding on these grounds alone — Go

- **A `tls.Config` with no `MinVersion`, or a `tls10server` source,** where the Effective TLS default (Language facts)
  is TLS 1.2.
- **`regexp.Compile` / `MustCompile` on input** as a denial of service (RE2). A user pattern where a literal match was
  intended (`regexp.QuoteMeta` missing) is a logic bug, not a finding here.
- **`text/template`** whose output is a config file, CLI output, or generated code, never an `http.ResponseWriter`.
- **`import "unsafe"`, `reflect`, `//go:linkname`, `//go:nosplit`** on sight: no exploit path.
- **`runtime/pprof`**: it writes profiles to a writer the code chooses and serves nothing.
- **`net/http/pprof` or `expvar`** when `http.DefaultServeMux` is served only on a listener bound to localhost, and
  the application's routes are on a separate mux.
- **`GOFLAGS=-mod=mod`**: `go.sum` is still verified.
- **A `replace` to a path inside the repository** (a monorepo module, a `go.work` member: tracked and reviewed like
  any other source), to a versioned fork, or in a module the repository never deploys (a tools module).
- **A `go.mod` with no requirements**, and so no `go.sum`.
- **`GOPRIVATE` / `GONOSUMDB` set to the organization's own namespace** that the module path shows: the expected
  configuration; a wider value is the finding.

## Boundary inventory

- **Routes:** `net/http` `ServeMux` (`Handle` / `HandleFunc`, 1.22 method patterns), gin (`r.GET`, `Use`, groups),
  echo, chi (`r.Route`, `r.Group`, `r.With`), gorilla/mux (`mux.Vars`), fiber, gRPC (`Register*Server`, unary and
  stream interceptors), connect-go.
- **Other boundaries:** `flag` / cobra CLIs; `os.Getenv` / viper loaders; queue consumers; CGO calls fed by any of
  them.
- **Auth:** middleware in the chain or the group (`r.Use(auth)`, `r.With(auth)`, `group.Use`); gRPC interceptors. The
  route scan nominates `Use`, `Group`, `Route`, and `Mount` so the chain can be read.

## Detectors

- **gosec**, standalone when a Makefile, CI step, or pre-commit hook runs it, or as golangci-lint's `gosec` linter
  when the project configures golangci-lint with it enabled. Add `-tests` only when the project's own invocation has
  it (test files are excluded here anyway).

  ```bash
  gosec -quiet -fmt=json -out <run>/gosec.json [-conf <project config>] ./...
  golangci-lint run --enable-only=gosec --fix=false --allow-serial-runners --uniq-by-line=false \
    --max-issues-per-linter=0 --max-same-issues=0 --output.text.path=stdout \
    <--output.<format>.path=/dev/null for every other format under output.formats> <package dirs>
  ```

  Hand-offs: G103 (`unsafe`) dropped; G104 (unchecked error) → exception-hunter; G115 (integer overflow in
  conversion) → invariant-hunter, cross-reference; G102 (bind `0.0.0.0`) dropped. Every other hit routes by its title.
- **govulncheck**, only when the repository's own Makefile, CI step, or hook invokes it: that invocation, with
  `-json` added when it accepts it. It needs `vuln.go.dev`; unreachable → `errored`. It reads the module graph and
  installs nothing. → Dependency and Supply-Chain Risks (`cve`), only for a finding whose `Trace` shows a reachable
  call (govulncheck's default output).
- `go vet` has no security analyzers; it is not run here.

## Phase 3 — security scans

`$GO_FILES` is this language's eligible list, restored from `<run>/go.txt` (SKILL.md Phase 1 step 4). Generated-code
globs in `$EXCLUDE` approximate the authoritative marker. Scans marked *inventory* feed the Boundaries and Auth lines
(SKILL.md Phase 1 step 5).

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Injection (sql): query text built by Sprintf, concatenation, a builder, or passed as a variable (then trace the operands)
rg -H -n --pcre2 '\.(Query|QueryRow|Exec|QueryContext|QueryRowContext|ExecContext|Raw|NamedQuery|NamedExec)\(\s*(ctx,\s*)?(fmt\.Sprintf\(|"[^"]*"\s*\+|`[^`]*`\s*\+|[a-z]\w*\s*(\+|[,)])|strings\.(Join|Builder))' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '(fmt\.Sprintf\(\s*["`][^"`]*|["`][^"`]*)\b(SELECT|INSERT|UPDATE|DELETE|WHERE|ORDER BY)\b[^"`]*["`]\s*\+' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 'fmt\.Sprintf\(\s*["`][^"`]*\b(SELECT|INSERT|UPDATE|DELETE|WHERE|ORDER BY)\b' --type go $EXCLUDE -- $GO_FILES
# Injection (command): every exec site (then read argv: a shell with input, or input as the program)
rg -H -n --pcre2 'exec\.Command(Context)?\(' --type go $EXCLUDE -- $GO_FILES
# Injection (path): file operations on a built or variable path (then look for IsLocal / os.Root / Clean + prefix)
rg -H -n --pcre2 '\b(os\.(Open|OpenFile|ReadFile|WriteFile|Create|Remove|RemoveAll|Stat|Mkdir(All)?|ReadDir)|http\.ServeFile|http\.Dir)\(\s*("[^"]*"\s*\+|[a-z]\w*|filepath\.(Join|Clean)\()' --type go $EXCLUDE -- $GO_FILES
# Injection (html): text/template in a package that serves HTTP; unsafe template casts (then read the operand)
rg -H -n --pcre2 '"text/template"|template\.(HTML|JS|URL|HTMLAttr|Srcset)\(' --type go $EXCLUDE -- $GO_FILES
# Injection (ssrf): request URL from a variable (then trace it)
rg -H -n --pcre2 '(http|client|c)\.(Get|Post|Head|Do|NewRequest(WithContext)?)\(\s*(ctx,\s*)?("[A-Z]+",\s*)?[a-z]\w*' --type go $EXCLUDE -- $GO_FILES
# Injection (header, redirect): response headers set from a variable; redirects
rg -H -n --pcre2 '\.Header\(\)\.(Set|Add)\(\s*"(Location|Set-Cookie|Content-Disposition|Access-Control-Allow-Origin)"\s*,\s*[a-z]|http\.Redirect\(\s*\w+,\s*\w+,\s*[a-z]' --type go $EXCLUDE -- $GO_FILES
# Boundary reads (inventory for Injection and Unvalidated Boundary Input; then follow each field)
rg -H -n --pcre2 '\br\.(URL\.Query\(\)|FormValue|PostFormValue|Body|Header\.Get|PathValue|MultipartForm|FormFile)(?!\w)|chi\.URLParam\(|mux\.Vars\(|c\.(Param|Query|PostForm|ShouldBind\w*|Bind\w*|GetHeader|FormFile)\(|json\.NewDecoder\(\s*r\.Body' --type go $EXCLUDE -- $GO_FILES
# Insecure Configuration: TLS, CORS, cookies, servers, diagnostics, permissions
rg -H -n --pcre2 'InsecureSkipVerify\s*:\s*true|MinVersion\s*:\s*tls\.VersionTLS1[01]\b|VersionSSL30|&?tls\.Config\{' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 'Access-Control-Allow-Origin|AllowedOrigins|AllowOrigins|AllowAllOrigins|AllowOriginFunc|AllowCredentials' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '&?http\.Cookie\{|SetCookie\(|sessions\.Options\{' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 'http\.ListenAndServe(TLS)?\(|&?http\.Server\{|fasthttp\.ListenAndServe' --type go $EXCLUDE -- $GO_FILES
rg -H -n '"net/http/pprof"|"expvar"' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '(WriteFile|OpenFile|Create|Chmod|Mkdir(All|Temp)?|CreateTemp)\([^\n]*\b0o?[0-7]?[0-7][4-7][4-7]\b|os\.ModePerm' --type go $EXCLUDE -- $GO_FILES
# Auth Gaps: route registrations (inventory; Go 1.22 method patterns; both quote forms), fail-open chains, client claims, JWT parsing, signature checks
rg -H -n --pcre2 '\.(Handle|HandleFunc|GET|POST|PUT|PATCH|DELETE|Get|Post|Put|Patch|Delete|Any|Group|Route|Mount|Use|Method|Add)\(\s*["`](/|(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) /)|Register\w+Server\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n -U --pcre2 'err\s*!=\s*nil\s*\{\s*\n\s*(next(\.ServeHTTP)?\(|h(\.ServeHTTP)?\(|c\.Next\(\)|return next)' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '\.(Role|Roles|IsAdmin|Admin|TenantID|OwnerID|UserID|OrgID|Permissions|Scopes|Verified)\s*=\s*(req|body|input|payload|p|in)\.|copier\.Copy\(|mapstructure\.Decode\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 'jwt\.(Parse|ParseWithClaims|ParseUnverified|NewParser)\(|WithoutClaimsValidation|SigningMethodNone|UnsafeAllowNoneSignatureType|jwt\.WithValidMethods' --type go $EXCLUDE -- $GO_FILES
rg -H -n -i --pcre2 'hmac\.(New|Equal)\(|subtle\.ConstantTimeCompare\(|x-hub-signature|stripe-signature|webhook' --type go $EXCLUDE -- $GO_FILES
# Sensitive Data Exposure: credential words in log calls; a whole request formatted with %+v; error text and stacks to clients
rg -H -n -i --pcre2 '\b(log|slog|logger|zap|logrus|zerolog|l)[\w.]*\.(Print\w*|Info\w*|Debug\w*|Warn\w*|Error\w*|Fatal\w*|Msg\w*|With)\([^\n]*\b(password|passwd|token|secret|authorization|cookie|api[_-]?key|ssn|card)' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 'http\.Error\(\s*\w+,\s*(err|e)\.Error\(\)|Write\(\[\]byte\((err|e)\.Error\(\)|debug\.Stack\(\)|%\+v"\s*,\s*(r|req)\b|c\.JSON\([^)]*err\.Error\(\)' --type go $EXCLUDE -- $GO_FILES
# Weak Cryptography: imports and primitives (then name the use); secret comparisons
rg -H -n --pcre2 '"crypto/(md5|sha1|des|rc4)"|"math/rand(/v2)?"|cipher\.NewCBCEncrypter|cipher\.NewECB|x509\.InsecureAlgorithm|bcrypt\.MinCost' --type go $EXCLUDE -- $GO_FILES
rg -H -n -i --pcre2 '\b\w*(token|secret|signature|sig|hmac|mac|digest)\w*\s*[!=]=\s*\w|\bbytes\.Equal\(\s*\w*(sig|mac|hash|digest)' --type go $EXCLUDE -- $GO_FILES
# Resource Exhaustion: unbounded body reads and their limits; goroutines in a loop (then: per request? bounded?); decompression; limiters
rg -H -n --pcre2 '(io|ioutil)\.ReadAll\(\s*(r|req)\.Body|http\.MaxBytesReader|MaxBytesHandler|ParseMultipartForm\(|FormFile\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n -U --pcre2 '^\s*for\b[^\n]*\{\n(?:[^\n]*\n){0,2}?\s*go\s+(func\b|[\w.]+\()' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '(gzip|zlib|flate|zip|tar)\.(NewReader|OpenReader)\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n -i --pcre2 'ratelimit|rate\.(NewLimiter|Limiter)|tollbooth|limiter' --type go $EXCLUDE -- $GO_FILES
```

Blind spots: a query built in one statement and executed in another (the variable form nominates the `Exec(q)`;
reading finds the build); `exec.Command` with a program from input in list form; routes registered through a
variable path or a table; `http.Get` through a wrapper client; a cookie built by a helper; `text/template` used by a
package that only generates files (reading closes it); `regexp.Compile(input)` is not scanned (RE2); a `go`
statement more than three lines into its loop body, or a goroutine per request started outside a loop (the loop form
is the nominator; a bare `go` is not, by design: every Go service has dozens); a fail-open chain whose error branch
spans several statements before `next`.

## Phase 5 — Go-specific evaluation

- For each `exec.Command`: is the program a literal? Does any argument reach `sh -c`, or a program that treats
  arguments as options?
- For each `text/template` import: is the output written to an `http.ResponseWriter`? Does the package serve HTTP at
  all?
- For each `http.Server` / `ListenAndServe`: is `ReadHeaderTimeout` set? Is the server behind a proxy the deployment
  evidence shows fronting this listener?
- For each server `tls.Config` with no `MinVersion` and each `tls10server` source: apply the Effective TLS default
  (Language facts).
- For each explicit mode: world-writable (`0666`, `0777`, `ModePerm`) → a finding on any file; group- or
  other-readable (`0644`, `0640`, `0755`) → a finding only when the file holds a secret, key, or token.
- For each `for … { go … }`: is the loop over a client-sized list, or per request? Is there a pool, a semaphore, or
  `errgroup.SetLimit`?
- For each fail-open chain: does the error branch reach `next` or the handler without writing a denial?
- For each `jwt.Parse`: does the key func check the signing method (`jwt.WithValidMethods`, or a `switch` on
  `token.Method`)? Is `ParseUnverified` output trusted?
- For each `net/http/pprof` or `expvar` import: is `http.DefaultServeMux` served, and with what auth?
- For each `replace` hit: does the target leave the repository, and is the module deployed?
