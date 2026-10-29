# Security Hunter — common reference

Contents: All-file list · Detectors · Phase 3 — all-file and manifest scans · Phase 5 — every language

Read in every run, before any language reference: it holds the detectors and the scans that do not depend on a
language, so a repository with no supported source still gets the secrets and dependency scans.

## All-file list

SKILL.md Phase 1 step 4 writes `<run>/all.txt`: in codebase mode the output of `git ls-files` (tracked files,
hidden and `.gitignore`-listed ones included); in diff and path mode the manifest; in every mode minus vendored trees,
minified bundles, and source maps.

```bash
git ls-files | rg -v '(^|/)(vendor|node_modules)/|\.min\.js$|\.map$' > <run>/all.txt              # codebase
printf '%s\n' $SCOPE | rg -v '(^|/)(vendor|node_modules)/|\.min\.js$|\.map$' > <run>/all.txt      # diff, path
```

It is always a list of paths, never `.`: `rg` over a folder skips hidden files (`.env`, `.github/`) and files
`.gitignore` names even when they are tracked, and `--glob` filters only a folder walk, so the list is filtered when it
is built and every scan names its files. Tests, generated files, lockfiles, Markdown, YAML, `.env*`, Dockerfiles, and
CI files stay in it. Scans restore it as `ALL_FILES=$(cat <run>/all.txt)` and pass it as `rg -H -n … -- $ALL_FILES`.
Hardcoded Secrets scans it whole; every other scan here uses `$ALL_NONTEST` (the list minus test paths) or a subset
derived from it.

A list that exceeds the exec argument limit (about 2 MB of paths on Linux) is passed as `xargs -a <run>/all.txt rg -H
-n …` instead; a subset derived from it is written to its own file first. `xargs` exits 123 whenever one batch
matches nothing, so in that form an `rg` error shows only on stderr.

## Detectors

Each detector runs only when the project configures it, with the project's config, read-only, never installed, never
reconfigured. Its output nominates. A flag the installed version rejects makes the detector `errored`; it is never
retried with other flags.

**Mutation flags are stripped** from every configured invocation before it runs: `--fix` (pip-audit), `audit fix`
(npm), `--fix` on golangci-lint (pass `--fix=false`). A configured command is reused for its config and targets, not
run verbatim.

**No rule-id tables.** Rule ids shift between tool versions (gosec G403 is now "Ensure minimum RSA key length of 2048
bits", RULES.md). Each hit routes by the rule's own title and message to a category definition in SKILL.md during
Phase 4; each language reference lists only the hand-offs.

- **gitleaks**, when `.gitleaks.toml` exists or a pre-commit hook or CI step names it. Working tree only; `--redact`
  keeps secret values out of its output. Treat `<run>/` as holding secrets. → Hardcoded Secrets.

  ```bash
  gitleaks dir . --no-banner --redact --report-format json --report-path <run>/gitleaks.json            # gitleaks >= 8.19
  gitleaks detect --no-git --no-banner --redact --report-format json --report-path <run>/gitleaks.json  # older
  ```

- **trufflehog**, when a hook or CI step names it. `--no-verification` stops it from calling the credential's provider
  to test liveness (a network call that announces the leak). trufflehog has no redaction flag and its JSON carries
  the secret in `Raw` and `RawV2`, so its stdout is piped through `jq` before anything reads it; without `jq` the
  detector is `skipped — jq missing`. → Hardcoded Secrets.

  ```bash
  trufflehog filesystem . --json --no-update --no-verification | jq -c 'del(.Raw, .RawV2)' > <run>/trufflehog.json
  ```

- **semgrep**, only when a CI step or script runs it, with that config (a local `.semgrep.yml` / `.semgrep/`, or a
  registry config). A registry config (`p/…`) needs the network: unreachable → `errored`. semgrep's
  `metadata.category` is a string such as `security` plus CWE ids, not this hunter's categories: Phase 4 routes each
  hit by its CWE and message to a category definition, and drops what fits none.

  ```bash
  semgrep scan --config <project config> --json --metrics=off --output <run>/semgrep.json
  ```

**Outcome rule:** no secret detector configured → one Low recommendation to adopt gitleaks or trufflehog
(report-format.md, Recommendation-only entries).

## Phase 3 — all-file and manifest scans

Every scan names its files, so no `--glob`, `--type`, or exclusion glob appears here: `rg` applies those only while
walking a folder. A subset is derived from the list first; an empty subset falls back to `/dev/null`, so a scan with
nothing to search searches nothing (`rg` with no path would search the working directory).

```bash
ALL_FILES=$(cat <run>/all.txt)

# Hardcoded Secrets: known key formats and a three-part JWT (then judge: placeholder, published example, format-marked test key, or credential; truncate in the report)
rg -H -n --pcre2 '\b(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|sk_(live|test)_[0-9a-zA-Z]{10,}|rk_(live|test)_[0-9a-zA-Z]{10,}|ghp_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{20,}|gho_[0-9A-Za-z]{36}|xox[baprs]-[0-9A-Za-z-]{10,}|AIza[0-9A-Za-z_-]{35}|glpat-[0-9A-Za-z_-]{20}|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})' -- $ALL_FILES
# Hardcoded Secrets: PEM private keys (-e because the pattern starts with a dash)
rg -H -n --pcre2 -e '-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY' -- $ALL_FILES
# Hardcoded Secrets: a credential name (bare, prefixed, or a quoted key) assigned a quoted literal by =, :=, or :, with or without a type between (`: str`, Go `string`) (then judge the value)
rg -H -n -i --pcre2 '\b(\w*_)?(password|passwd|pwd|secret|api[_-]?key|apikey|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key|secret[_-]?key)\b["\x27]?(\s*:\s*[\w\[\],. ]+|\s+string)?\s*(:=|[:=])\s*["\x27][^"\x27]{6,}["\x27]' -- $ALL_FILES
# Hardcoded Secrets: the unquoted NAME=value form of .env, compose, and CI files (committed .env files are usually unquoted)
rg -H -n -i --pcre2 '^\s*(export\s+)?\w*(PASSWORD|PASSWD|SECRET|API_?KEY|TOKEN|PRIVATE_KEY)\w*\s*=\s*[^\s"\x27$#]{6,}\s*$' -- $ALL_FILES
# Hardcoded Secrets: connection strings with a password (the user part may be empty: redis://:pw@host), git+https URLs with a token; Authorization literals
rg -H -n --pcre2 '\b(postgres(ql)?|mysql|mongodb(\+srv)?|redis|amqp|mssql|https?)://[^/\s:@]*:[^@\s/]+@' -- $ALL_FILES
rg -H -n --pcre2 '(Authorization|authorization)["\x27]?\s*[:=]\s*["\x27`](Basic|Bearer) [A-Za-z0-9+/=._-]{16,}' -- $ALL_FILES
# Hardcoded Secrets: secret-bearing files committed (a name scan over the list itself)
printf '%s\n' $ALL_FILES | rg -n --pcre2 '(^|/)\.env(\.(?!example|sample|template|dist)\w+)?$|\.(pem|p12|pfx|key|jks)$|id_(rsa|ed25519)$'

# Every scan below excludes test paths: only Hardcoded Secrets runs over tests
ALL_NONTEST=$(printf '%s\n' $ALL_FILES | rg -v '(^|/)(tests?|__tests__|testdata|fixtures|spec)/|(^|/)(test_[^/]*|conftest\.py)$|_test\.\w+$|\.(test|spec|e2e)\.\w+$' || echo /dev/null)
# Sensitive Data Exposure (public-env): a secret name under a bundler's public prefix, in env files and code
rg -H -n --pcre2 '\b(NEXT_PUBLIC|VITE|REACT_APP|EXPO_PUBLIC|NUXT_PUBLIC|PUBLIC)_\w*(SECRET|PRIVATE|PASSWORD|_KEY|TOKEN)\w*\s*[=:]' -- $ALL_NONTEST
# Insecure Configuration (tls-verify) and Dependency (checksum-bypass): build-file switches and the TLS 1.0 re-enable (then read the file's role; GOFLAGS=-mod=mod is not scanned: go.sum is still verified)
rg -H -n --pcre2 '\b(GOSUMDB\s*[=:]\s*off|GONOSUMDB\s*[=:]|GOPRIVATE\s*[=:]|PIP_TRUSTED_HOST|--trusted-host|strict-ssl\s*(=|\s)\s*false|NODE_TLS_REJECT_UNAUTHORIZED\s*[=:]\s*["\x27]?0|GODEBUG\s*[=:][^\n]*tls10server=1)|^\s*//go:debug\s+tls10server=1' -- $ALL_NONTEST
# Dependency (remote-install): piped installers, URL installs, an npx of an unpinned package (npx pkg@1.2.3 is pinned and does not match)
rg -H -n --pcre2 '\b(curl|wget)\b[^\n|]*\|\s*(sudo\s+)?(sh|bash|python3?|node)\b|pip3?\s+install\s+[^\n]*https?://|npx\s+(--?\w+\s+)*(?![\w./-]+@\d)[a-z@][\w./-]*(\s|$)' -- $ALL_NONTEST
# Dependency (cdn-script) and Injection (html): the template subset, derived from the list (the language lists hold no template files)
ALL_TEMPLATES=$(printf '%s\n' $ALL_NONTEST | rg '\.(html|htm|ejs|hbs|handlebars|njk|jinja2?|j2|vue|pug|svelte|tsx|jsx)$' || echo /dev/null)
rg -H -n --pcre2 '<script[^>]*\bsrc\s*=\s*["\x27]https?://[^>]*>' -- $ALL_TEMPLATES
rg -H -n --pcre2 '\|\s*safe\b|autoescape\s+(false|off)|\{\{\{|<%-|v-html\s*=|\{@html\b|\{%\s*autoescape\s+false' -- $ALL_TEMPLATES

# Dependency manifests in the target scope (a manifest outside the scope is context, never an anchor)
ALL_GOMOD=$(printf '%s\n' $ALL_NONTEST | rg '(^|/)go\.(mod|work)$' || echo /dev/null)
ALL_REQS=$(printf '%s\n' $ALL_NONTEST | rg '(^|/)requirements[^/]*\.txt$' || echo /dev/null)
ALL_PKGJSON=$(printf '%s\n' $ALL_NONTEST | rg '(^|/)package\.json$' || echo /dev/null)
ALL_PYPROJECT=$(printf '%s\n' $ALL_NONTEST | rg '(^|/)pyproject\.toml$' || echo /dev/null)
# go.mod: replace to a local path, on one line or inside a replace ( … ) block (then: does the target leave the repository? is the module deployed?)
rg -H -n --pcre2 '^\s*(replace\s+)?\S+\s*=>\s*\.{0,2}/' -- $ALL_GOMOD
# Insecure Configuration: GODEBUG sources and the build toolchain in go.mod / go.work (the Go reference's TLS gate reads them)
rg -H -n --pcre2 '^\s*(godebug\b|toolchain\b|default=)' -- $ALL_GOMOD
# requirements*.txt: unpinned lines; VCS and URL sources (then: which file does the Dockerfile or CI install from?)
rg -H -n --pcre2 '^\s*[A-Za-z0-9][A-Za-z0-9._-]*\s*(\[[^\]]*\])?\s*(>=?[^=]|~=|$)' -- $ALL_REQS
rg -H -n --pcre2 '^\s*(-e\s+)?(git\+|https?://)' -- $ALL_REQS
# package.json: wide ranges, VCS and tarball sources, by value shape ("homepage": "https://…" is not a dependency and does not match)
rg -H -n --pcre2 '"[^"]+"\s*:\s*"(\*|latest|>=?\s*\d[^"]*|x|git\+[^"]*|github:[^"]*|file:[^"]*|https?://[^"]*\.(tgz|tar\.gz))"' -- $ALL_PKGJSON
# pyproject.toml: VCS and URL sources (ranges are judged by the lockfile test)
rg -H -n --pcre2 '\b(git|url)\s*=\s*"|@\s*(git\+|https?://)' -- $ALL_PYPROJECT
# Lockfile presence is a file test, not a scan: for each go.mod with a require block, go.sum beside it; for each
# package.json with dependencies, one of package-lock.json / npm-shrinkwrap.json / pnpm-lock.yaml / yarn.lock /
# bun.lock / bun.lockb (Bun >= 1.2 writes bun.lock) in the package or the workspace root; for each
# requirements*.txt / pyproject.toml with dependencies, the file the install step reads is pinned, or a
# poetry.lock / uv.lock / Pipfile.lock / pdm.lock that the install step uses.
```

Blind spots: high-entropy generic secrets with no recognizable name or format (gitleaks, trufflehog); secrets in git
history (out of scope); a credential split across lines or built by concatenation; base64-encoded credentials; a
template with a custom filter that disables escaping; a dependency range in `pyproject.toml` (judged only by the
lockfile test); second-order injection through data another tenant stored (no column inventory). Codebase mode lists
tracked files only, so an untracked `.env` is not scanned (correct: it is not committed).

## Phase 5 — every language

- For each secret candidate: is the value a placeholder, a public identifier, a vendor's published example, a
  format-marked test key, or a credential? What does it unlock? Is it read from the environment on the next line?
  Then the literal is a fallback default, and still a finding.
- For each traced sink: does the content check on the path establish the property the sink needs (SKILL.md Terms,
  Content check)?
- For each boundary field: does it reach a storing sink or a decision, or is it only compared, returned, or logged?
- For each route: is auth global? Is the route marked public on purpose? With no peer that has auth, does it perform
  a protected action?
- For each credential endpoint: does a peer route carry a limiter this one lacks? Does the repository apply a limiter
  anywhere, or show a gateway limiter in its deployment evidence?
- For each hash, RNG, or comparison: what is the value's role? A checksum, cache key, or shuffle → not a finding.
- For each body read, spawn, decompression, or regex: what bounds it, and what is the framework default at the
  recorded version?
- For each manifest hit: is the manifest in the target scope? Which file does the Dockerfile or CI install from, and
  is a lockfile committed beside it?
- For each `GOPRIVATE` / `GONOSUMDB` value: is it wider than the namespace the module path shows?
