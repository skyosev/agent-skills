#!/usr/bin/env bash
# Decides the status of a reader's report or of a checker's verdict list, so that the merge never judges one by eye.
#
#   bash check-replies.sh report <k> <report file>
#   bash check-replies.sh verdicts <k> <reply file> <report file>...
#   bash check-replies.sh --selftest
#
# Prints one line: "completed", or "failed — <what>" with the first problem in the order given below.
#
# A report's ID is its file name without .md. Its findings are the rows of its Findings tables: each line that starts
# with "|", whose first cell is a whole number, under a "### <Category>" heading inside "## Findings", and outside
# fenced code blocks. A finding is named "<report ID> <Category> #<n>".
#
# report: the report of scope k is completed when its first line is "area <k>: <N> findings" ("finding" also
# passes), it has exactly N findings, and it has an "Audit completed:" line. Its problems: "no header",
# "<m> rows, not <N>", "no Audit completed line".
#
# verdicts: the reply of the checker of scope k, against the reports that the checker got. Each line is read without
# a leading "- ", "*" and backticks. The header is the first line that is neither empty nor a code fence, and reads
# "verify <k>: <a> kept, <b> dropped, <c> fixed". A verdict line is one of
#   <finding>: keep
#   <finding>: drop — <rule> — <evidence>
#   <finding>: fix — <evidence> — <new Action text>
# Other lines are ignored. The list is completed when it gives exactly one verdict for each finding, a + b + c is the
# number of findings, and each drop and fix has both of its parts. Its problems: "no verify header", "header names
# area <j>", "no verdict for <finding>", "two verdicts for <finding>", "a verdict for unknown <finding>", "counts add
# up to <x> of <y> findings", "drop without a rule: <finding>", "fix without a new Action: <finding>". Within one
# kind of problem, the message names the first finding in report order (reports in argument order, rows in file
# order); for an unknown finding, the first such line of the reply.
#
# Exit 0: a status line, whatever the status. Exit 2: a usage error, or a file that cannot be read.
set -euo pipefail

# Prints "row<TAB><finding>" for each finding of a report, and "audit" for each Audit completed line.
scan() {
  LC_ALL=C awk -v id="$(basename "$1" .md)" '
    { t = $0; sub(/^[ \t]+/, "", t); mark = substr(t, 1, 3) }
    fence != "" { if (mark == fence) fence = ""; next }
    mark == "```" || mark == "~~~" { fence = mark; next }
    /^## / { in_findings = ($0 ~ /^## Findings[ \t\r]*$/); category = ""; next }
    /^### / {
      category = ""
      if (in_findings) { category = substr($0, 5); sub(/[ \t\r]+$/, "", category) }
      next
    }
    category != "" && /^\|/ {
      split($0, cell, "|"); n = cell[2]; gsub(/^[ \t]+|[ \t]+$/, "", n)
      if (n ~ /^[0-9]+$/) print "row\t" id " " category " #" n
      next
    }
    { gsub(/[*`]/, "", t); if (t ~ /^(- )?Audit completed:/) print "audit" }
  ' "$1"
}

report() {
  local k=$1 file=$2 header n rows audit
  header="^area $k: ([0-9]+) findings?[[:space:]]*$"
  if ! [[ $(head -n 1 "$file") =~ $header ]]; then echo "failed — no header"; return; fi
  n=${BASH_REMATCH[1]}
  read -r rows audit < <(scan "$file" | awk '/^row\t/ { r++ } $0 == "audit" { a = 1 } END { print r + 0, a + 0 }')
  if [ "$rows" -ne "$n" ]; then
    echo "failed — $rows rows, not $n"
  elif [ "$audit" = 0 ]; then
    echo "failed — no Audit completed line"
  else
    echo completed
  fi
}

verdicts() {
  local k=$1 reply=$2 f
  shift 2
  # The first file is the findings in report order, the second the reply.
  LC_ALL=C awk -v k="$k" -v sep=" — " '
    function plain(s) { gsub(/[*`]/, "", s); sub(/^- /, "", s); return s }
    function fail(what) { print "failed — " what; exit }
    # Whether the text after a drop or fix verdict is " — <part> — <part>", both parts not blank.
    function both_parts(rest,   i) {
      if (index(rest, sep) != 1) return 0
      rest = substr(rest, length(sep) + 1)
      i = index(rest, sep)
      return i > 0 && substr(rest, 1, i - 1) ~ /[^ \t]/ && substr(rest, i + length(sep)) ~ /[^ \t]/
    }
    FILENAME == ARGV[1] { if (sub(/^row\t/, "")) { want[++n] = $0; known[$0] = 1 }; next }
    { t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t\r]+$/, "", t); line = plain(t) }
    !started && t != "" && substr(t, 1, 3) != "```" && substr(t, 1, 3) != "~~~" {
      started = 1
      if (line ~ /^verify [0-9]+: [0-9]+ kept, [0-9]+ dropped, [0-9]+ fixed([^A-Za-z0-9_]|$)/) {
        split(line, w, /[ :,]+/); header = 1; area = w[2]; counted = w[3] + w[5] + w[7]
      }
      next
    }
    match(line, / #[0-9]+: (keep|drop|fix)/) {
      head = substr(line, 1, RSTART - 1); tail = substr(line, RSTART, RLENGTH); rest = substr(line, RSTART + RLENGTH)
      if (head !~ /^[^ ]+ [^ ]/ || rest ~ /^[A-Za-z0-9_]/) next
      i = index(tail, ": "); finding = head substr(tail, 1, i - 1); verdict = substr(tail, i + 2)
      if (!(finding in known)) { if (unknown == "") unknown = finding; next }
      verdicts[finding]++
      if (verdict != "keep" && !both_parts(rest)) incomplete[finding] = verdict
    }
    END {
      if (!header) fail("no verify header")
      if (area + 0 != k + 0) fail("header names area " area)
      for (i = 1; i <= n; i++) if (!verdicts[want[i]]) fail("no verdict for " want[i])
      for (i = 1; i <= n; i++) if (verdicts[want[i]] > 1) fail("two verdicts for " want[i])
      if (unknown != "") fail("a verdict for unknown " unknown)
      if (counted != n) fail("counts add up to " counted " of " (n + 0) " findings")
      for (i = 1; i <= n; i++) if (incomplete[want[i]] == "drop") fail("drop without a rule: " want[i])
      for (i = 1; i <= n; i++) if (incomplete[want[i]] == "fix") fail("fix without a new Action: " want[i])
      print "completed"
    }
  ' <(for f in "$@"; do scan "$f"; done) "$reply"
}

selftest() {
  local self tmp rc
  self=$(realpath "${BASH_SOURCE[0]}")
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT
  cd "$tmp"
  fail() { echo "selftest FAIL: $*" >&2; exit 1; }
  # check <want> <argument>...: the script prints the status line <want> for these arguments.
  check() {
    local want=$1 got
    shift
    got=$(bash "$self" "$@") || fail "$*: exit $?"
    [ "$got" = "$want" ] || fail "$*: got [$got], want [$want]"
  }
  # reply <want>: the verdict list on stdin has the status <want> against r1.md and r2.md.
  reply() { cat > v.md; check "$1" verdicts 2 v.md r1.md r2.md; }

  # The fenced row note holds a line that would be a row, and the table under Recommendations is outside Findings.
  cat > r1.md <<'EOF'
area 2: 3 findings

## Scope

- Audit completed: 3 findings

## Findings

### Duplication

| # | Locations | Action |
| - | - | - |
| 1 | `a.go:1` | Share it |
| 2 | `a.go:9` | Share it |

#1
```go
| 9 | a | fenced |
```

### Channel & Goroutine Overuse

| # | Location | Action |
|---|---|---|
| 1 | `b.go:3` | Use a mutex |

## Recommendations (Priority Order)

### Later

| 1 | not a finding |
EOF
  cat > r2.md <<'EOF'
area 2: 1 finding

## Scope

- **Audit completed:** 1 finding

## Findings

### Dead Code Paths

| # | Location | Action |
| - | - | - |
| 1 | `c.go:5` | Delete |
EOF
  cat > reply.md <<'EOF'

```text
verify 2: 2 kept, 1 dropped, 1 fixed
- r1 Duplication #1: keep
**r1 Duplication #2**: drop — Duplication rule 2 — a.go:9 has the same loop
r1 Channel & Goroutine Overuse #1: fix — b.go:3 starts one goroutine — Use a mutex — not a channel
`r2 Dead Code Paths #1`: keep
```
EOF

  check completed report 2 r1.md
  check completed report 2 r2.md
  check "failed — no header" report 1 r1.md
  sed '1s/3 findings/4 findings/' r1.md > rows.md
  check "failed — 3 rows, not 4" report 2 rows.md
  grep -v 'Audit completed' r1.md > audit.md
  check "failed — no Audit completed line" report 2 audit.md

  reply completed < reply.md
  reply "failed — no verify header" < <(echo "Verdicts:"; cat reply.md)
  reply "failed — no verify header" < <(sed 's/^verify 2: .*/verify 2: 4 kept/' reply.md)
  reply "failed — header names area 3" < <(sed 's/^verify 2:/verify 3:/' reply.md)
  reply "failed — no verdict for r1 Duplication #2" < <(grep -v 'r1 Duplication #2' reply.md)
  reply "failed — two verdicts for r1 Duplication #1" < <(cat reply.md; echo "r1 Duplication #1: keep")
  reply "failed — a verdict for unknown r3 Duplication #1" \
    < <(cat reply.md; echo "r3 Duplication #1: keep"; echo "r1 Duplication #7: keep")
  reply "failed — counts add up to 5 of 4 findings" < <(sed 's/1 fixed/2 fixed/' reply.md)
  reply "failed — drop without a rule: r1 Duplication #2" < <(sed 's/ — a.go:9 has the same loop//' reply.md)
  reply "failed — fix without a new Action: r1 Channel & Goroutine Overuse #1" \
    < <(sed 's/ — Use a mutex — not a channel//' reply.md)

  rc=0
  bash "$self" verdicts 2 reply.md none.md > /dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "a missing report: exit $rc, want 2"
  echo "selftest ok"
}

usage() {
  echo "usage: check-replies.sh report <k> <report file> | verdicts <k> <reply file> <report file>... | --selftest" >&2
  exit 2
}
readable() {
  local f
  for f in "$@"; do
    [ -f "$f" ] && [ -r "$f" ] || { echo "cannot read: $f" >&2; exit 2; }
  done
}

case ${1:-} in
  --selftest) selftest ;;
  report) [ $# -eq 3 ] && [[ $2 =~ ^[0-9]+$ ]] || usage; readable "$3"; report "$2" "$3" ;;
  verdicts) [ $# -ge 4 ] && [[ $2 =~ ^[0-9]+$ ]] || usage; readable "${@:3}"; verdicts "${@:2}" ;;
  *) usage ;;
esac
