# Doc Hunter — diff mode

Read with `references/diff-scope.md`, before Phase 1 step 1, whenever the scope is a diff.

## Deleted source files

The call that resolves the scope (step 1) also writes `$DELETED` to `<run>/deleted.txt`; in party mode, write the
deleted-in-diff list from `scope-meta.txt` there. With no deletions the file is empty: an empty list, not a STOP.
Step 2 detects languages from it as well as from the manifest, so a deleted Python module is seen in a Go-only diff.
Deleted paths never enter `scope.txt` or a `<lang>.txt`, so no scan runs against them; Phase 3 reads their
declarations at the merge base (Removed and renamed symbols). A language detected only from `deleted.txt` loads its
reference, for the declaration patterns, and gets no `<lang>.txt`: steps 4 and 5 and Phase 2 skip it.

## Deletions-only run

No eligible file in scope and at least one deleted source path. A diff that only deletes a file is the case where
comments elsewhere become false, so it is an exception to both shared empty-scope stops. When `$SCOPE` is empty, the
stop in `references/diff-scope.md` does not apply yet: drop the deleted paths that are test paths, generated (the
reference's in-file marker, read at the merge base), or not in a supported language. If none remain, that stop
applies unchanged ("Audit completed: 0 findings — empty diff scope"). Otherwise the run continues: later calls restore
`<run>/deleted.txt` instead of `<run>/scope.txt`, and an empty restore of it is the STOP. Steps 4 and 5 and Phase 2 do
not run; Phase 3 runs only the removed-symbol search. The only possible finding is Misleading Comments and Names
(`stale`), at `<path> (deleted)`.

## Phase 3 in diff mode

Hunks and removed lines come from the merge base:

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
MB=$(cat <run>/mb); [ -n "$MB" ] || exit 1                                    # STOP: empty restore
FILES=$(cat <run>/go.txt <run>/python.txt <run>/typescript.txt 2>/dev/null)  # none in a deletions-only run
[ -z "$FILES" ] || git diff -U0 "$MB" -- $FILES                               # changed hunks and removed lines
[ -z "$FILES" ] || git ls-files --others --exclude-standard -- $FILES         # untracked: new in full
git show "$MB:<deleted path>"                                                 # once per path in <run>/deleted.txt
```

- **Changed-line restriction.** Unexplained Business Rules, Magic Numbers, Non-Obvious Algorithms, and Unexplained
  Workarounds report only lines that the change added or modified. Untracked files are new in full. Undocumented
  Contracts and Missing Public Docs report only declarations that the change added, or whose signature or body it
  modified. Misleading Comments and Names reports text on changed lines, plus the two nominations below.
- **Stale-text nominations** (Misleading Comments and Names), for every declaration whose signature or body the
  change modified:
  - its doc comment, when the change left the comment untouched.
  - every comment inside it that the change left untouched, whatever the comment's age: a claim is checked, never
    trusted (the comment standard).
  - its name. `git diff -U0` omits the `func GetRate` line when only the body changed.

## Removed and renamed symbols

- Collect the declarations that the change removed: removed lines (`^-`) that match the reference's declaration
  patterns, plus the declarations of each path in `<run>/deleted.txt` at the merge base (`git show "$MB:<path>"`).
- A declaration is removed when its package no longer declares it (Go: the directory; Python: the module; TypeScript:
  the file), and a method when its type no longer does (identity `Type.Method`). A same name declared elsewhere does
  not hide the removal.
- Search the whole repository's comments for references to each removed name, with the reference's removed-name scan.
  A hit counts in reference syntax: a Go doc link (`[Name]`, `[pkg.Name]`, `[Type.Method]`), a backtick span in Go or
  TypeScript, a Python Sphinx role, a TypeScript `{@link}` or `@see`. A bare word counts only when the name is not a
  plain word: it has an inner capital, an underscore, or a digit (`handleLegacy`, `parse_rate`). A removed `Close`
  never matches "Close the body".
- Read each hit. It counts only when it refers to the removed declaration: same package, or qualified by it.
- A stale reference in the target scope is anchored at the comment. Stale references outside the scope produce one
  finding at the in-scope removal site — `file:line (removed: <name>)`, or `<path> (deleted)` for a deleted file —
  whose Contradicted At cell lists them. Findings still anchor only in the target scope.

Done when every removed declaration has its removed-name search and every hit is read.
