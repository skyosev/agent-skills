# Diff scope — resolution

Resolve fail-closed:

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1                     # git diff and git ls-files must agree on paths
BASE=$(git symbolic-ref -q refs/remotes/origin/HEAD | sed 's@^refs/remotes/@@')
git rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1 || BASE=
if [ -z "$BASE" ]; then
  for b in origin/main origin/master main master; do
    git rev-parse -q --verify "$b^{commit}" >/dev/null && BASE=$b && break
  done
fi
# BASE still empty: STOP and ask for an explicit base. Do not continue.
MB=$(git merge-base "$BASE" HEAD) || exit 1                        # STOP: no merge base
CHANGED=$(git diff --name-only --diff-filter=d "$MB") || exit 1    # STOP: diff failed
UNTRACKED=$(git ls-files --others --exclude-standard) || exit 1    # STOP: ls-files failed
DELETED=$(git diff --name-only --diff-filter=D "$MB") || exit 1    # STOP: diff failed
SCOPE=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u)
```

Every command that supplies audit data is checked; only the base-discovery probes may fail, because failure there
means "try the next candidate". One diff from the merge base to the working tree covers committed, staged, and
unstaged changes. A file that existed at the merge base and is gone from the working tree lands in `$DELETED`; a file
added after the merge base and deleted again appears nowhere. A failed command is never an empty scope.

If `$SCOPE` is empty, run no scans: write the report with "Audit completed: 0 findings — empty diff scope", listing
`$DELETED` under "Deleted in diff" if non-empty, and stop.
