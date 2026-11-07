#!/usr/bin/env bash
# One unattended hunter run on a fixed commit of a fixture repository.
#
#   code-hunter/pilot/pilot.sh <fixture-repo> <hunter> <out-dir> <prompt...>
#
# Default-mode prompt: "/pilot:<hunter> <scope>" (no scope = codebase). A hand-cut brief is passed as plain text.
# The hunter is loaded from this repository's working copy as plugin "pilot", so the installed copy and the
# fixture worktree stay untouched. Hooks are off; ~/.claude/CLAUDE.md still loads (the same for every run).
# Permissions: auto mode, as in an interactive session. Its classifier approves or denies each call. A denied call
# is listed in result.json (permission_denials); compare.py prints the count. A run with denials is not comparable.
#
# Env: PILOT_COMMIT (default: fixture HEAD), PILOT_MODEL (default: claude-opus-5-5), PILOT_BUDGET_USD (default: 25).
# Writes <out-dir>/report.md, result.json (cost, tokens, denials, session id), meta.txt.
set -euo pipefail

[ $# -ge 4 ] || { sed -n 2,13p "$0" >&2; exit 2; }
fixture=$(git -C "$1" rev-parse --show-toplevel)
hunter=$2
out=$3
shift 3
skill=$(cd "$(dirname "$0")/.." && pwd)/$hunter
[ -f "$skill/SKILL.md" ] || { echo "no such hunter: $hunter" >&2; exit 2; }
[ ! -e "$out/result.json" ] || { echo "run exists, not overwritten: $out" >&2; exit 2; }

commit=$(git -C "$fixture" rev-parse "${PILOT_COMMIT:-HEAD}")
model=${PILOT_MODEL:-claude-opus-5-5}
tmp=$(mktemp -d)
trap 'git -C "$fixture" worktree remove --force "$tmp/wt" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# The fixture's own hooks stay off: they can edit the checkout (abraxa_laytime's post-checkout swaps CLAUDE.md).
git -C "$fixture" -c core.hooksPath=/dev/null worktree add --detach --quiet "$tmp/wt" "$commit"
mkdir -p "$tmp/plugin/.claude-plugin" "$tmp/plugin/skills" "$out"
echo '{"name":"pilot"}' > "$tmp/plugin/.claude-plugin/plugin.json"
cp -r "$skill" "$tmp/plugin/skills/$hunter"
out=$(cd "$out" && pwd)

prompt="$*

Unattended run: nobody answers questions. Do not ask. Decide, and record each decision in the report's Scope section.
Save the report as $out/report.md."

{
  echo "fixture: $fixture"
  echo "commit: $commit"
  echo "hunter: $hunter"
  echo "skill: $(git -C "$skill" rev-parse --short HEAD)$([ -n "$(git -C "$skill" status --porcelain -- .)" ] && echo ' (dirty)')"
  echo "model: $model"
  echo "prompt: $*"
} > "$out/meta.txt"

cd "$tmp/wt"
claude -p "$prompt" --plugin-dir "$tmp/plugin" --model "$model" --settings '{"disableAllHooks":true}' \
  --permission-mode auto --add-dir "$out" --max-budget-usd "${PILOT_BUDGET_USD:-25}" --output-format json > "$out/result.json"
[ -s "$out/report.md" ] || { echo "no report written: $out" >&2; exit 1; }
