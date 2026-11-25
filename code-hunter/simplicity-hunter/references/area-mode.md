# Area mode

`scripts/split-areas.sh` split this diff into package areas. One agent audits each area with this whole hunter, and
this session, the orchestrator, merges their reports. For this scope, area mode replaces the budget sentence of
**Persist run state.**: the areas answer the context budget, so ask nothing about it. Phase 1 step 5 and Phases 2 to
5 run in the area agents.

## What the split wrote

- `<run>/a<k>/scope.txt`: the eligible files of area `<k>`, then every raw-manifest file that is not eligible. So each
  area sees the dependency manifests that the diff changes.
- `<run>/a<k>/scope-meta.txt`: `surface: diff`, `mb: <merge base>` and `files: <n>`.
- `<run>/areas.txt`: one line per area, `<k>: <files> files, <bytes> bytes (<production> production) — <units>`. A
  unit is one directory's eligible files, tests included.

## Spawn

Start one general-purpose agent per area, all in one message. Pass this session's model as the agent's model. A
sub-agent does not get the skill text that this session loaded, so its prompt carries absolute paths: `<skill>` is
the directory this SKILL.md was read from, `<root>` is the repository root, and `<run>` is the run directory. Give
each agent this prompt and nothing else:

```text
Read <skill>/references/area-agent.md, then <skill>/SKILL.md, and follow them.
Repository: <root>. Snapshot: <run>/a<k>. Report: <run>/a<k>/report.md. Area <k> of <n>.
```

## Merge

Merge when every agent has returned its `area <k>:` line or has ended. Read each `<run>/a<k>/report.md`. Phase 6
"Merging a split run" applies to every row, together with these steps.

1. **Status.** An area is `completed` when its report holds an `Audit completed` line. An agent that ended without one
   leaves its area `failed — not audited`, and its rows stay out of the merge. An agent that could not start leaves
   its area `not started`. Start no agent again.
2. **One row per finding.** Two locations are near when they are in the same file and at most 3 lines apart. Two rows
   from two areas are one finding, whatever their categories, when a location of one is near a location of the
   other, or when both name the same dependency. Phase 6's rule picks the claim, which brings its category and
   Action. When both claims clear the evidence bar, Within-skill precedence picks; where none of its rules applies,
   keep the row with more locations, then the row from the lower area number. The row note names the other row's
   claim in one clause. The kept row takes the higher Severity and the higher Impact of the two. When each row has a
   location with no near location in the other, the kept row lists the locations of both, and its Action covers
   them. Anchor the kept row at its location whose path sorts first.
3. **Two Actions on one function.** When rows from two areas change the same function, open the function and judge
   the two Actions together: one must not undo the other (Duplication, rule 2).
4. **A changed Action is checked again.** Every Action written or changed in steps 2 and 3 gets Phase 5's Remedy
   check and Behavior parity on its final wording.
5. **Layout.** Category sections in report-format.md order, with no empty section. Number each table from 1, and fix
   every `#<n>`.
6. **Count.** `Audit completed: <N> findings` counts the merged rows. For each area that is not `completed`, the line
   ends with `— partial: area <k> not audited` or `— partial: area <k> not started`.
7. **Scope**, in report-format.md order:
   - Your Phase 1 lines describe the whole diff. Leave out each area line of the same name.
   - `Duplication coverage` and `Added units` are each summed over the completed areas. A dependency counts once.
   - Every other line of a completed area, except `Audit completed`, is written once when every completed area gives
     the same text, else once per area as `<line> (area <k>)`. Every `not read in full` line is kept as it is.
   - `Read split: <n> agents by package area — merged by this session`, with one sub-line per area from
     `<run>/areas.txt`, its status after the number.
8. **Recommendations.** Write `## Recommendations (Priority Order)` over the merged rows, ending with one Tooling
   block (Phase 6, "Delegated to tools").
9. **Save** as Phase 6 says.
