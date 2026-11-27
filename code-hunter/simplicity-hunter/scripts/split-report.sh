#!/usr/bin/env bash
# Splits the merged report of a run with read areas into one file per area, when the report is too long to review.
#
#   bash split-report.sh <report> <run>
#   bash split-report.sh --selftest
#
# The gate: <run>/areas.txt has two or more areas, and <report> has more than MAX_LINES lines. Otherwise the report
# stays one file, and the script prints "one file: <report>".
#
# The split writes the folder <report> without its ".md". index.md holds the report's title, its Scope, the list of
# the area files, one line per finding in report order with a link to its file, and the rest of the report from the
# first "## " heading after the findings. area-<k>.md holds the findings of area k, each copied unchanged, in report
# order. A finding is a "### #<n> · " heading inside "## Findings", outside fenced code blocks, and the lines up to
# the next one. Its anchor is the first file:line of its **Location:** line. Its area is the k whose
# <run>/a<k>/scope.txt lists the anchor's path; a file that several areas list (a file that is not eligible) goes to
# the first of them. An area is labelled with its first and last unit from areas.txt. The script then checks that
# the area files hold every finding once and the folder every line of the report, removes <report>, and prints
# "split: <folder>/index.md, <m> area files".
#
# Exit 0: a line above. Exit 1: an anchor that no area lists, a finding without a file:line in its Location, a
# folder that exists already, or a failed check; <report> stays as it was. Exit 2: a usage error, or a file that
# cannot be read.
set -euo pipefail
MAX_LINES=800  # about 25 findings at 30 lines each

# Reads the area map ("<k> <path>" lines), areas.txt and the report; writes index.md and area-<k>.md into dir.
SPLIT='
  function err(s) { print s > "/dev/stderr"; bad = 1 }
  FILENAME == ARGV[1] { k = $1; p = substr($0, length(k) + 2); if (!(p in area)) area[p] = k; next }
  FILENAME == ARGV[2] {
    if (!match($0, /^[0-9]+: /)) next
    k = substr($0, 1, RLENGTH - 2) + 0; n = k
    units = substr($0, index($0, " — ") + length(" — "))
    c = split(units, u, ", ")
    label[k] = c == 1 ? "`" u[1] "`" : "`" u[1] "` … `" u[c] "`"
    next
  }
  {
    t = $0; sub(/^ +/, "", t); outside = fence == ""
    if (outside && part == "" && title == "" && /^# /) { title = $0; next }
    if (outside && part == "" && /^## Findings/) { part = "findings"; next }
    if (outside && part == "findings" && /^## /) part = "tail"
    if (outside && part == "findings" && /^### #[0-9]+ · /) {
      f++; body[f] = $0; h = $0; sub(/^### #/, "", h); split(h, hp, " · ")
      num[f] = hp[1]; sev[f] = hp[2]; imp[f] = hp[3]; cat[f] = hp[4]
      sub(/ severity$/, "", sev[f]); sub(/ impact$/, "", imp[f])
      next
    }
    if (outside && match(t, /^(```+|~~~+)/)) fence = substr(t, 1, RLENGTH)
    else if (!outside && match(t, /^(```+|~~~+)[ \t]*$/)) {
      m = t; sub(/[ \t]+$/, "", m)
      if (substr(m, 1, 1) == substr(fence, 1, 1) && length(m) >= length(fence)) fence = ""
    }
    if (part == "") scope = scope $0 "\n"
    else if (part == "tail") tail = tail $0 "\n"
    else if (f) { body[f] = body[f] "\n" $0; if (outside && loc[f] == "" && /^\*\*Location:\*\*/) loc[f] = $0 }
    else if ($0 != "") pre = pre $0 "\n"
  }
  END {
    if (part == "") { err("no ## Findings section"); exit 1 }
    for (i = 1; i <= f; i++) {
      l = loc[i]; gsub(/`/, "", l)
      if (!match(l, /[A-Za-z0-9_.\/@+-]+:[0-9]+/)) { err("no file:line in the Location of #" num[i]); continue }
      anchor[i] = substr(l, RSTART, RLENGTH); p = anchor[i]; sub(/:[0-9]+$/, "", p)
      if (!(p in area)) { err("anchor in no area: #" num[i] " " p); continue }
      a[i] = area[p]; count[a[i]]++
    }
    if (bad) exit 1
    for (k = 1; k <= n; k++) word[k] = count[k] == 1 ? "finding" : "findings"
    ix = dir "/index.md"
    printf "%s\n%s## Findings\n\n%s", title, scope, pre > ix
    if (pre != "") print "" > ix
    print "Files, one per read area. A finding has the same number in every file.\n" > ix
    for (k = 1; k <= n; k++) if (count[k])
      printf "- [area %d](area-%d.md): %d %s in %s\n", k, k, count[k], word[k], label[k] > ix
    print "\nEvery finding, by priority:\n" > ix
    for (i = 1; i <= f; i++)
      printf "- #%s · %s · %s · %s · `%s` → [area %d](area-%d.md)\n", \
        num[i], sev[i], imp[i], cat[i], anchor[i], a[i], a[i] > ix
    printf "\n%s", tail > ix
    for (k = 1; k <= n; k++) {
      if (!count[k]) continue
      af = dir "/area-" k ".md"
      printf "%s — area %d of %d\n\n", title, k, n > af
      printf "%d %s in %s. Scope, every finding by priority, and Tooling: [index](index.md).\n\n## Findings\n", \
        count[k], word[k], label[k] > af
      for (i = 1; i <= f; i++) if (a[i] == k) { b = body[i]; sub(/\n+$/, "", b); printf "\n%s\n", b > af }
      close(af)
    }
  }'

selftest() {
  local script tmp run run1 out rc
  script=$(realpath "${BASH_SOURCE[0]}")
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT
  fail() { echo "selftest FAIL: $*" >&2; exit 1; }
  eq() { [ "$1" = "$2" ] || fail "$3: got [$1], want [$2]"; }
  # A report of three findings. #2 holds a fenced heading and the padding; #3 cites a file that both areas list.
  mkreport() { # mkreport <file> <padding lines>
    {
      printf '# Simplicity Hunter Audit — 2026-01-01\n\n## Scope\n\n- Surface: codebase\n- Audit completed: 3 findings\n\n'
      printf '## Findings\n\n### #1 · Medium severity · High impact · Duplication\n\n'
      printf '**Location:** `src/b/y.ts:20`, `src/a/x.ts:5`\n\nTwo copies.\n\n'
      printf '### #2 · Low severity · Medium impact · Dead Code Paths\n\n**Location:** `src/a/x.ts:9`\n\n'
      printf '~~~md\n### #9 · Low severity · Low impact · Duplication\n## Recommendations (Priority Order)\n~~~\n\n'
      seq "$2" | sed 's/^/filler /'
      printf '\n**Action:** Delete it, as #1 does.\n\n'
      printf '### #3 · Low severity · Low impact · Reinvented Primitives\n\n'
      printf '**Location:** package.json:4\n\n**Action:** Drop it.\n\n'
      printf '## Recommendations (Priority Order)\n\n**Tooling.** This hunter does not check the classes below.\n'
    } > "$1"
  }
  run=$tmp/run; run1=$tmp/run1
  mkdir -p "$run/a1" "$run/a2" "$run1/a1"
  printf '%s\n' '1: 1 files, 100 bytes (100 production) — src/a' \
    '2: 1 files, 50 bytes (50 production) — src/b, src/c' > "$run/areas.txt"
  printf 'src/a/x.ts\npackage.json\n' > "$run/a1/scope.txt"
  printf 'src/b/y.ts\npackage.json\n' > "$run/a2/scope.txt"
  printf '1: 2 files, 150 bytes (150 production) — src/a, src/b\n' > "$run1/areas.txt"
  cp "$run/a1/scope.txt" "$run1/a1/scope.txt"

  mkreport "$tmp/r.md" 900
  cp "$tmp/r.md" "$tmp/r.orig"
  eq "$(bash "$script" "$tmp/r.md" "$run")" "split: $tmp/r/index.md, 2 area files" "case 1 output"
  [ ! -e "$tmp/r.md" ] || fail "case 1: the report must be removed"
  eq "$(grep '^- ' "$tmp/r/index.md" | grep -v '^- Surface\|^- Audit')" "- [area 1](area-1.md): 2 findings in \`src/a\`
- [area 2](area-2.md): 1 finding in \`src/b\` … \`src/c\`
- #1 · Medium · High · Duplication · \`src/b/y.ts:20\` → [area 2](area-2.md)
- #2 · Low · Medium · Dead Code Paths · \`src/a/x.ts:9\` → [area 1](area-1.md)
- #3 · Low · Low · Reinvented Primitives · \`package.json:4\` → [area 1](area-1.md)" "case 1 index lines"
  eq "$(tail -n 3 "$tmp/r/index.md")" "## Recommendations (Priority Order)

**Tooling.** This hunter does not check the classes below." "case 1 index tail"
  eq "$(cat "$tmp/r/area-2.md")" "# Simplicity Hunter Audit — 2026-01-01 — area 2 of 2

1 finding in \`src/b\` … \`src/c\`. Scope, every finding by priority, and Tooling: [index](index.md).

## Findings

### #1 · Medium severity · High impact · Duplication

**Location:** \`src/b/y.ts:20\`, \`src/a/x.ts:5\`

Two copies." "case 1 area 2"
  eq "$(grep -c '^### #[0-9]' "$tmp/r/area-1.md")" 3 "case 1 area 1 holds #2, its fenced heading, and #3"
  eq "$(LC_ALL=C comm -23 <(LC_ALL=C sort "$tmp/r.orig") <(cat "$tmp"/r/*.md | LC_ALL=C sort))" "" "case 1 lines kept"

  mkreport "$tmp/s.md" 10
  eq "$(bash "$script" "$tmp/s.md" "$run")" "one file: $tmp/s.md" "case 2, a short report"
  mkreport "$tmp/t.md" 900
  eq "$(bash "$script" "$tmp/t.md" "$run1")" "one file: $tmp/t.md" "case 3, one area"
  [ -e "$tmp/s.md" ] && [ -e "$tmp/t.md" ] && [ ! -e "$tmp/s" ] && [ ! -e "$tmp/t" ] || fail "cases 2 and 3 must keep one file"

  mkreport "$tmp/u.md" 900; sed -i 's|`src/a/x.ts:9`|`x.ts:9`|' "$tmp/u.md"
  rc=0; out=$(bash "$script" "$tmp/u.md" "$run" 2>&1) || rc=$?
  eq "$rc $out" "1 anchor in no area: #2 x.ts" "case 4, a bare file name"
  [ -e "$tmp/u.md" ] && [ ! -e "$tmp/u" ] || fail "case 4 must keep the report and write no folder"

  mkreport "$tmp/v.md" 900; mkdir "$tmp/v"
  rc=0; out=$(bash "$script" "$tmp/v.md" "$run" 2>&1) || rc=$?
  eq "$rc $out" "1 exists already: $tmp/v" "case 5, the folder exists"
  echo "selftest ok"
}
if [ "${1:-}" = --selftest ]; then selftest; exit 0; fi

[ $# -eq 2 ] || { echo "usage: split-report.sh <report> <run>" >&2; exit 2; }
report=$1 run=$2
for f in "$report" "$run/areas.txt"; do [ -r "$f" ] || { echo "cannot read: $f" >&2; exit 2; }; done
areas=$(grep -c '^[0-9]*: ' "$run/areas.txt" || true)
if [ "$areas" -lt 2 ] || [ "$(wc -l < "$report")" -le "$MAX_LINES" ]; then
  echo "one file: $report"
  exit 0
fi
dir=${report%.md}
[ ! -e "$dir" ] || { echo "exists already: $dir" >&2; exit 1; }
for k in $(seq 1 "$areas"); do
  [ -r "$run/a$k/scope.txt" ] || { echo "cannot read: $run/a$k/scope.txt" >&2; exit 2; }
done
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/out"
for k in $(seq 1 "$areas"); do sed "s/^/$k /" "$run/a$k/scope.txt"; done > "$tmp/map"
LC_ALL=C awk -v dir="$tmp/out" "$SPLIT" "$tmp/map" "$run/areas.txt" "$report" || exit 1

want=$(grep -c '^### #[0-9]* · ' "$report" || true)
got=$(cat "$tmp"/out/area-*.md | grep -c '^### #[0-9]* · ' || true)
[ "$got" = "$want" ] || { echo "check failed: the area files hold $got finding headings, the report $want" >&2; exit 1; }
lost=$(LC_ALL=C comm -23 <(LC_ALL=C sort "$report") <(cat "$tmp"/out/*.md | LC_ALL=C sort) | head -n 1)
[ -z "$lost" ] || { echo "check failed: a line of the report is in no file: $lost" >&2; exit 1; }
mv "$tmp/out" "$dir"
rm "$report"
echo "split: $dir/index.md, $(ls "$dir"/area-*.md | wc -l | tr -d ' ') area files"
