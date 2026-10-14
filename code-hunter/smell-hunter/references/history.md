# Shotgun Surgery — git-history pipeline

Read at Phase 4. Run each block as written; replace `<run>` with the run directory printed in Phase 1. Each block
restores what it uses, so the blocks may run in separate tool calls.

```bash
# 1. Commits that touch at least one manifest file. The commits are in scope; their file lists are not — a
#    finding anchors only at an in-scope file (evidence rule). Codebase mode (scope.txt is `.`): every commit.
SCOPE=$(cat <run>/scope.txt); [ -n "$SCOPE" ] || exit 1             # STOP: empty restore
COMMITS=$(git log --pretty=format:'%h' -200 -- $SCOPE) || exit 1     # STOP: git log failed
for c in $COMMITS; do
  # 2. Keep hash, subject, and the commit's FULL file list — evidence must survive to the report.
  git show --pretty=format:'@@@ %h %s' --name-only "$c" || exit 1    # STOP: git show failed
done > <run>/commits.txt

# 3. Count area PAIRS, not whole sets, so partially overlapping commits still co-occur. An area is the folder
#    holding the file. Commits touching BULK or more areas are bulk changes and are skipped.
awk -v BULK=15 '
  function flush(   n, i, j, t, k, p) {
    n = 0; for (p in dirs) k[++n] = p
    if (n < BULK) {
      for (i = 1; i < n; i++) for (j = i + 1; j <= n; j++)
        if (k[j] < k[i]) { t = k[i]; k[i] = k[j]; k[j] = t }
      for (i = 1; i < n; i++) for (j = i + 1; j <= n; j++) print k[i] " <-> " k[j]
    }
    delete dirs
  }
  /^@@@ / { flush(); next }
  NF { d = $0; if (d ~ /\//) sub(/\/[^\/]*$/, "", d); else d = "."; dirs[d] = 1 }
  END { flush() }
' <run>/commits.txt | sort | uniq -c | sort -rn | head -30

# 4. Nominate commits touching 4 to BULK-1 areas, hash and subject intact.
awk -v BULK=15 '
  function flush(   n, p) {
    if (hdr != "") { n = 0; for (p in dirs) n++; if (n >= 4 && n < BULK) print n "\t" hdr }
    delete dirs; hdr = ""
  }
  /^@@@ / { flush(); hdr = substr($0, 5); next }
  NF { d = $0; if (d ~ /\//) sub(/\/[^\/]*$/, "", d); else d = "."; dirs[d] = 1 }
  END { flush() }
' <run>/commits.txt | sort -rn | head -20
```

A commit touching 15 or more areas is a rename, a formatting pass, or a dependency bump: it says nothing about one
concept, and its pairs would swamp the counts. Merge commits list no files under `git show --name-only` and drop out
too.

For each nominated commit ask: one logical change scattered across unrelated areas, or a legitimate cross-cutting
concern? A recurring area pair across multiple commits is the structural-coupling signal; a single commit is not a
pattern.
