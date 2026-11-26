#!/usr/bin/env bash
# Packs a diff scope's eligible files into reading areas, one snapshot per area.
#
#   bash split-areas.sh <run> [<areas>]
#   bash split-areas.sh --selftest
#
# Reads what Phase 1 wrote: <run>/scope.txt, <run>/mb and the eligible lists <run>/{go,python,typescript}.txt.
# A unit is the eligible files of one directory, tests included. Units are packed in path order; a unit that would
# take its area above the limit starts a new area, and a unit is never cut.
#
# Without <areas>, the limit is AREA_SIZE bytes. If that gives more than MAX_AREAS areas, the split packs as for
# <areas> = MAX_AREAS. With <areas> = N, it packs with the smallest limit that gives at most N areas. Then, while
# there are fewer than N areas, it splits the largest area that holds two or more units before its last unit. So
# the result has N areas, or one per unit when the diff has fewer than N units. One area is the whole diff.
#
# Exit 0: removes the <run>/a<k>/ of an earlier call, writes <run>/a<k>/scope.txt and scope-meta.txt, and prints one
# line per area (also saved to <run>/areas.txt), then "areas: <n>, <bytes> eligible bytes" and "run: <absolute run>".
# Exit 1: an input is missing, <areas> is not a positive whole number, no file is eligible, or the areas do not hold
# every eligible file exactly once.
set -euo pipefail
# Cases for the split. Each makes a git repository of Go files of given sizes, plus a go.mod that is not eligible.
selftest() {
  local script tmp repo run out k
  script=$(realpath "${BASH_SOURCE[0]}")
  tmp=$(realpath "$(mktemp -d)")
  trap "rm -rf '$tmp'" EXIT
  fail() { echo "selftest FAIL: $*" >&2; exit 1; }
  eq() { [ "$1" = "$2" ] || fail "$3: got [$1], want [$2]"; }
  mk() { # mk <name> <path:bytes>...
    local spec p name=$1; shift
    repo=$tmp/$name; run=$tmp/$name-run
    mkdir -p "$repo" "$run"; git -C "$repo" init -q
    echo module > "$repo/go.mod"; echo go.mod > "$run/scope.txt"; : > "$run/go.txt"; echo abc123 > "$run/mb"
    for spec in "$@"; do
      p=${spec%:*}; mkdir -p "$repo/$(dirname "$p")"
      head -c "${spec#*:}" /dev/zero | tr '\0' x > "$repo/$p"
      echo "$p" | tee -a "$run/go.txt" >> "$run/scope.txt"
    done
  }
  split() { (cd "$repo" && bash "$script" "$@"); }
  shape() { sed 's/^[0-9]*: [0-9]* files, \([0-9]*\) bytes.* — /\1 /' "$run/areas.txt"; }
  once() { cat "$run"/a[0-9]*/scope.txt | grep -Fx -f "$run/go.txt" | LC_ALL=C sort | cmp -s - <(LC_ALL=C sort "$run/go.txt") \
    || fail "$1: a Go file is not in exactly one area"; }
  four=(d1/f.go:4000 d1/f_test.go:2322 d2/f.go:5003 d3/f.go:10262 d4/f.go:30495)

  mk c1 "${four[@]}"
  out=$(split "$run")
  eq "$out" "1: 5 files, 52082 bytes (49760 production) — d1, d2, d3, d4
areas: 1, 52082 eligible bytes
run: $run" "case 1 output"
  eq "$(LC_ALL=C sort "$run/a1/scope.txt" | tr '\n' ' ')" "d1/f.go d1/f_test.go d2/f.go d3/f.go d4/f.go go.mod " "case 1 scope"
  eq "$(cat "$run/a1/scope-meta.txt")" "surface: diff
mb: abc123
files: 6" "case 1 meta"
  once 1

  split "$run" 3 > /dev/null; eq "$(shape)" "11325 d1, d2
10262 d3
30495 d4" "case 2"; once 2
  split "$run" 2 > /dev/null; eq "$(shape)" "21587 d1, d2, d3
30495 d4" "case 3"; once 3
  split "$run" 9 > /dev/null; eq "$(shape | wc -l)" 4 "case 4, 9 areas"; once 4
  split "$run" 1 > /dev/null; eq "$(shape | wc -l)" 1 "case 4, 1 area"; once 4

  specs=(); for k in $(seq -w 1 21); do specs+=("d$k/f.go:150000"); done
  mk c5 "${specs[@]}"
  eq "$(split "$run" | grep -c '^areas: 20, 3150000 eligible bytes$')" 1 "case 5 count"
  eq "$(shape | grep -c '^300000 ')" 1 "case 5 big area"
  eq "$(shape | grep -c '^150000 ')" 19 "case 5 small areas"; once 5

  mk c6 "${four[@]}"
  for k in 0 x; do ! split "$run" "$k" > /dev/null 2>&1 || fail "case 6: areas $k must exit 1"; done

  mk c7 "${four[@]}"
  split "$run" 4 > /dev/null; split "$run" 2 > /dev/null
  eq "$(cd "$run" && echo a[0-9]*)" "a1 a2" "case 7 areas"; once 7

  mk c8 "${four[@]}"
  out=$(cd "$repo" && bash "$script" ../c8-run)
  eq "$(tail -n 1 <<< "$out")" "run: $run" "case 8 last line"
  eq "$(head -n 1 <<< "$out")" "1: 5 files, 52082 bytes (49760 production) — d1, d2, d3, d4" "case 8 area line"; once 8
  echo "selftest ok"
}
if [ "${1:-}" = --selftest ]; then selftest; exit 0; fi

run=$(realpath -m "${1:?usage: split-areas.sh <run> [<areas>]}")
areas=${2:-0}
AREA_SIZE=160000  # packing limit of one area when the caller does not ask for a number of areas
MAX_AREAS=20      # the hunter's cap: Claude Code runs at most 20 Claude agents at once
if ! [[ $areas =~ ^[0-9]+$ ]] || { [ $# -ge 2 ] && [ "$areas" -lt 1 ]; }; then
  echo "<areas> must be a positive whole number: $2" >&2
  exit 1
fi
cd "$(git rev-parse --show-toplevel)"
for f in scope.txt mb; do
  [ -s "$run/$f" ] || { echo "missing or empty: $run/$f" >&2; exit 1; }
done
rm -rf "$run"/a[0-9]*/

# One line per eligible file: directory, bytes, prod|test, path. The test paths are each reference's Phase 3 seeds.
for lang in go python typescript; do
  [ -f "$run/$lang.txt" ] || continue
  case $lang in
    go) tests='_test\.go$' ;;
    python) tests='(^|/)(test_[^/]*|[^/]*_test|conftest)\.py$|(^|/)tests/' ;;
    typescript) tests='\.(test|spec|e2e)\.[^/]*$|(^|/)__tests__/' ;;
  esac
  while read -r f; do
    kind=prod
    if printf '%s\n' "$f" | grep -Eq "$tests"; then kind=test; fi
    printf '%s %s %s %s\n' "$(dirname "$f")" "$(wc -c < "$f" | tr -d ' ')" "$kind" "$f"
  done < "$run/$lang.txt"
done | LC_ALL=C sort -k1,1 -k4,4 > "$run/eligible.txt"

total=$(awk '{ t += $2 } END { print t + 0 }' "$run/eligible.txt")
if [ ! -s "$run/eligible.txt" ]; then
  echo "no eligible file in $run" >&2
  exit 1
fi

# Prefix each line with its area number. The areas are runs of consecutive directories: cut[i] marks the
# directory that starts one.
awk -v size="$AREA_SIZE" -v max="$MAX_AREAS" -v want="$areas" -v total="$total" '
  function count(limit,   i, k, bytes) {
    for (i = 1; i <= dirs; i++) { if (k == 0 || bytes + dbytes[i] > limit) { k++; bytes = 0 } bytes += dbytes[i] }
    return k
  }
  function pack(limit,   i, k, bytes) {
    for (i = 1; i <= dirs; i++) {
      cut[i] = (k == 0 || bytes + dbytes[i] > limit)
      if (cut[i]) { k++; bytes = 0 }
      bytes += dbytes[i]
    }
    return k
  }
  $1 != last { dirs++; last = $1 }
  { dbytes[dirs] += $2; line[NR] = $0; dir[NR] = dirs }
  END {
    if (want == 0 && count(size) <= max) { n = pack(size) }
    else {
      if (want == 0) want = max
      lo = 1; hi = total
      while (lo < hi) { mid = int((lo + hi) / 2); if (count(mid) <= want) hi = mid; else lo = mid + 1 }
      n = pack(lo)
      while (n < want) {
        found = 0
        for (i = 1; i <= dirs; i = j + 1) {
          bytes = dbytes[i]
          for (j = i; j < dirs && !cut[j + 1]; ) { j++; bytes += dbytes[j] }
          if (j > i && (!found || bytes > best)) { found = 1; best = bytes; last_dir = j }
        }
        if (!found) break
        cut[last_dir] = 1; n++
      }
    }
    for (i = 1; i <= NR; i++) {
      while (dir[i] > seen) { seen++; if (cut[seen]) k++ }
      print k, line[i]
    }
  }' "$run/eligible.txt" > "$run/split.txt"

n=$(tail -n 1 "$run/split.txt" | cut -d' ' -f1)
# Each area gets its eligible files plus every raw-manifest file that is not eligible (dependency manifests too).
cut -d' ' -f5 "$run/split.txt" | LC_ALL=C sort > "$run/eligible-files.txt"
LC_ALL=C sort "$run/scope.txt" | LC_ALL=C comm -23 - "$run/eligible-files.txt" > "$run/not-eligible.txt"
for k in $(seq 1 "$n"); do
  mkdir -p "$run/a$k"
  { awk -v k="$k" '$1 == k { print $5 }' "$run/split.txt"; cat "$run/not-eligible.txt"; } > "$run/a$k/scope.txt"
  printf 'surface: diff\nmb: %s\nfiles: %s\n' "$(cat "$run/mb")" "$(wc -l < "$run/a$k/scope.txt" | tr -d ' ')" \
    > "$run/a$k/scope-meta.txt"
done

if ! cat "$run"/a*/scope.txt | grep -Fx -f "$run/eligible-files.txt" | LC_ALL=C sort \
    | cmp -s - "$run/eligible-files.txt"; then
  echo "split check failed: the areas in $run/a*/ do not hold every eligible file exactly once" >&2
  exit 1
fi

awk '
  { f[$1]++; b[$1] += $3; if ($4 == "prod") p[$1] += $3
    if (!(($1, $2) in seen)) { seen[$1, $2]; u[$1] = u[$1] (u[$1] == "" ? "" : ", ") $2 } }
  END { for (k = 1; k in f; k++) printf "%d: %d files, %d bytes (%d production) — %s\n", k, f[k], b[k], p[k], u[k] }
' "$run/split.txt" | tee "$run/areas.txt"
echo "areas: $n, $total eligible bytes"
echo "run: $run"
