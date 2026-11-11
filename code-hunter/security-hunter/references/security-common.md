# Security Hunter — common reference

Contents: All-file list · Delegated to tools · Phase 2 — all-file and manifest scans · Phase 4 — every language

Read in every run, before any language reference: it holds the scans that do not depend on a language, so a
repository with no supported source still gets the connection-string and dependency scans.

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

## Delegated to tools

- gitleaks: a committed secret in a known key format (cloud, payment, and code-host tokens), a private key, a JWT, or a
  high-entropy quoted or `.env` value under a secret name (`generic-api-key`).
- OpenSSF Scorecard `Pinned-Dependencies`: a piped installer (`curl … | sh`) in a Dockerfile, a shell script, or a
  GitHub workflow (its `downloadThenRun` entries).

## Phase 2 — all-file and manifest scans

Every scan names its files, so no `--glob`, `--type`, or exclusion glob appears here: `rg` applies those only while
walking a folder. A subset is derived from the list first; an empty subset falls back to `/dev/null`, so a scan with
nothing to search searches nothing (`rg` with no path would search the working directory).

```bash
ALL_FILES=$(cat <run>/all.txt)

# Hardcoded Secrets: connection strings with a password (the user part may be empty: redis://:pw@host), git+https URLs with a token; Authorization literals (gitleaks has no rule for either)
rg -H -n --pcre2 '\b(postgres(ql)?|mysql|mongodb(\+srv)?|redis|amqp|mssql|https?)://[^/\s:@]*:[^@\s/]+@' -- $ALL_FILES
rg -H -n --pcre2 '(Authorization|authorization)["\x27]?\s*[:=]\s*["\x27`](Basic|Bearer) [A-Za-z0-9+/=._-]{16,}' -- $ALL_FILES

# Every scan below excludes test paths: only Hardcoded Secrets runs over tests
ALL_NONTEST=$(printf '%s\n' $ALL_FILES | rg -v '(^|/)(tests?|__tests__|testdata|fixtures|spec)/|(^|/)(test_[^/]*|conftest\.py)$|_test\.\w+$|\.(test|spec|e2e)\.\w+$' || echo /dev/null)
# Sensitive Data Exposure (public-env): a secret name under a bundler's public prefix, in env files and code
rg -H -n --pcre2 '\b(NEXT_PUBLIC|VITE|REACT_APP|EXPO_PUBLIC|NUXT_PUBLIC|PUBLIC)_\w*(SECRET|PRIVATE|PASSWORD|_KEY|TOKEN)\w*\s*[=:]' -- $ALL_NONTEST
# Dependency (checksum-bypass): the settings that skip the checksum database (GOFLAGS=-mod=mod is not scanned: go.sum is still verified)
rg -H -n --pcre2 '\b(GOSUMDB\s*[=:]\s*off|GONOSUMDB\s*[=:]|GOPRIVATE\s*[=:])' -- $ALL_NONTEST
# Dependency (remote-install): URL installs, an npx of an unpinned package (npx pkg@1.2.3 is pinned and does not match)
rg -H -n --pcre2 '\bpip3?\s+install\s+[^\n]*https?://|npx\s+(--?\w+\s+)*(?![\w./-]+@\d)[a-z@][\w./-]*(\s|$)' -- $ALL_NONTEST
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

Blind spots: a connection string split across lines or built by concatenation; a template with a custom filter that
disables escaping; a dependency range in `pyproject.toml` (judged only by the lockfile test); second-order injection
through data another tenant stored (no column inventory). Codebase mode lists tracked files only, so an untracked `.env`
is not scanned (correct: it is not committed).

## Phase 4 — every language

- For each credential literal: is the value a placeholder, a vendor's published example, or a credential? What does
  it unlock? Is it read from the environment on the next line?
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
