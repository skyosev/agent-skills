#!/usr/bin/env bash
# Area mode's split: packs a diff scope's eligible files into package areas, one snapshot per area.
#
#   bash split-areas.sh <run>
#
# Reads what Phase 1 wrote: <run>/scope.txt, <run>/mb and the eligible lists <run>/{go,python,typescript}.txt.
# A unit is the eligible files of one directory, tests included. Units are packed in path order; a unit that would
# take its area above AREA_SIZE starts a new area, and a unit is never cut.
#
# Exit 0: writes <run>/a<k>/scope.txt and scope-meta.txt, and prints one line per area, also saved to <run>/areas.txt.
# Exit 2: area mode does not apply, and the line printed says why.
# Exit 1: an input is missing, or the areas do not hold every eligible file exactly once.
set -euo pipefail
run=${1:?usage: split-areas.sh <run>}
SWITCH=160000     # area mode runs above this many eligible bytes
AREA_SIZE=160000  # packing limit of one area; kept apart from SWITCH so that moving the switch keeps the split
MAX_AREAS=20      # Claude Code runs at most 20 sub-agents at once; a 21st spawn fails
cd "$(git rev-parse --show-toplevel)"
for f in scope.txt mb; do
  [ -s "$run/$f" ] || { echo "missing or empty: $run/$f" >&2; exit 1; }
done

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
if [ "$total" -le "$SWITCH" ]; then
  echo "no area mode: $total eligible bytes, switch $SWITCH"
  exit 2
fi

# Prefix each line with its area number.
awk -v size="$AREA_SIZE" '
  NR == FNR { unit[$1] += $2; next }
  $1 != dir { dir = $1; if (k == 0 || bytes + unit[dir] > size) { k++; bytes = 0 } bytes += unit[dir] }
  { print k, $0 }' "$run/eligible.txt" "$run/eligible.txt" > "$run/split.txt"

n=$(tail -n 1 "$run/split.txt" | cut -d' ' -f1)
if [ "$n" -lt 2 ] || [ "$n" -gt "$MAX_AREAS" ]; then
  echo "no area mode: $n areas, $total eligible bytes (area mode needs 2 to $MAX_AREAS areas)"
  exit 2
fi

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
