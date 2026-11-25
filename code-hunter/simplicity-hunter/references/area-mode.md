# Area mode

Contents: What the split wrote · Spawn · Save and verify · Merge

`scripts/split-areas.sh` split this diff into package areas. One agent audits each area with this whole hunter, a
verifier checks the rows of each area, and this session, the orchestrator, merges their reports. For this scope, area
mode replaces the budget sentence of **Persist run state.**: the areas answer the context budget, so ask nothing about
it. Phase 1 step 5 and Phases 2 to 5 run in the area agents. Phase 5 runs again in the verifiers.

## What the split wrote

- `<run>/a<k>/scope.txt`: the eligible files of area `<k>`, then every raw-manifest file that is not eligible. So each
  area sees the dependency manifests that the diff changes.
- `<run>/a<k>/scope-meta.txt`: `surface: diff`, `mb: <merge base>` and `files: <n>`.
- `<run>/areas.txt`: one line per area, `<k>: <files> files, <bytes> bytes (<production> production) — <units>`. A
  unit is one directory's eligible files, tests included.

## Spawn

Start one general-purpose agent per area, all in one message. Pass each agent `model`, the alias of this session's LLM
family (`opus` in an Opus session), and `effort: xhigh`. The Agent call takes an alias, not a full ID, and an alias in
this session's family runs on this session's version. Without them, a sub-agent setting exported for other work, such
as `CLAUDE_CODE_SUBAGENT_EFFORT`, would choose the readers. A sub-agent does not get the skill text that this session
loaded, so its prompt carries absolute paths: `<skill>` is the directory this SKILL.md was read from, `<root>` is the
repository root, and `<run>` is the run directory. Give each agent this prompt and nothing else:

```text
Read <skill>/references/area-agent.md, then <skill>/SKILL.md, and follow them.
Repository: <root>. Snapshot: <run>/a<k>. Area <k> of <n>.
```

## Save and verify

Agents run in the background, so each reply arrives when its agent ends. When a reply holds an `Audit completed` line
and at least one row, write the reply verbatim to `<run>/a<k>/report.md`. Claude Code refuses a report file from a
sub-agent, so this session writes it. Then start that area's verifier: a general-purpose agent with the same `model`
and `effort`, and this prompt and nothing else. Give one `references/simplicity-<lang>.md` path for each language
reference that this session loaded:

```text
Read <skill>/references/area-verifier.md, then <skill>/SKILL.md and <skill>/references/simplicity-<lang>.md, and follow them.
Repository: <root>. Area report: <run>/a<k>/report.md. Area <k>.
```

A verifier starts only after its area agent ends, so the agents that run at once never outnumber the areas (at most
20). An area with 0 rows, or a failed area, gets no file and no verifier. Its notes still count in the merge. Start no
verifier again.

## Merge

Merge when every area agent and every verifier has ended. Each area agent's final reply is its area report. Phase 6
"Merging a split run" applies to every row, together with these steps. Copy each row's cells and row note as its area
wrote them, and read code only where steps 3, 5 and 6 ask for it.

1. **Status.** An area is `completed` when its reply holds an `Audit completed` line. An area agent that ended without
   one leaves its area `failed — not audited`, and its rows stay out of the merge. An area agent that could not start
   leaves its area `not started`. Start no agent again. A completed area also gets a verifier status:
   - `verified` when its verifier's reply is complete: it starts with
     `verify <k>: <kept> kept, <dropped> dropped, <fixed> fixed`, gives exactly one verdict for each row of the area,
     and its three counts add up to the area's rows;
   - `0 rows` when the area has none;
   - `verifier failed` when the reply is not complete;
   - `verifier not started` when the verifier could not start.

   The rows of an area with `verifier failed` or `verifier not started` stay in the merge unchecked.
2. **Verdicts.** Apply the verdicts of each `verified` area. A `drop` row leaves the tables and gets its
   `dropped (verifier)` Scope line. A `fix` row takes the new Action, and its row note says in one clause what the
   verifier changed. A `keep` row stays as its area wrote it.
3. **Disagreement.** When an area's `dropped:` line or another Scope note drops a candidate with a reason, and another
   area reports that candidate as a row, open the code that the row cites and judge the row against that reason. Drop
   the row when the reason holds under a named rule of SKILL.md or the language reference, and write its
   `dropped (disagreement)` Scope line. Otherwise the row stays, and its row note names the other area's reason in one
   clause.
4. **One row per finding.** This step and the next two take the rows that steps 2 and 3 keep. Two locations are near
   when they are in the same file and at most 3 lines apart. Two rows from two areas are one finding, whatever their
   categories, when a location of one is near a location of the other, or when both name the same dependency. Phase 6's
   rule picks the claim, which brings its category and Action. When both claims clear the evidence bar, Within-skill
   precedence picks; where none of its rules applies, keep the row with more locations, then the row from the lower area
   number. The row note names the other row's claim in one clause. The kept row takes the higher Severity and the higher
   Impact of the two. When each row has a location with no near location in the other, the kept row lists the locations
   of both, and its Action covers them. Anchor the kept row at its location whose path sorts first.
5. **Two Actions on one function.** When rows from two areas change the same function, open the function and judge
   the two Actions together: one must not undo the other (Duplication, rule 2).
6. **A changed Action is checked again.** Every Action written or changed in steps 4 and 5 gets Phase 5's Remedy
   check and Behavior parity on its final wording.
7. **Layout.** Category sections in report-format.md order, with no empty section. Number each table from 1, and fix
   every `#<n>`.
8. **Count.** `Audit completed: <N> findings` counts the merged rows. For each area that is not `completed`, the line
   ends with `— partial: area <k> not audited` or `— partial: area <k> not started`. For each area whose verifier
   status is `verifier failed` or `verifier not started`, add `— partial: area <k> not verified`.
9. **Scope**, in report-format.md order:
   - Your Phase 1 lines describe the whole diff. Leave out each area line of the same name.
   - `Duplication coverage` and `Added units` are each summed over the completed areas. A dependency counts once.
   - Every other line of a completed area, except `Audit completed`, is written once when every completed area gives
     the same text, else once per area as `<line> (area <k>)`. Every `not read in full` line is kept as it is.
   - One line per row that step 2 or 3 drops:
     `dropped (verifier): <location> — <claim in one clause> — <rule> — <evidence>` or
     `dropped (disagreement): <location> — <claim in one clause> — <rule> — <evidence>`.
   - `Read split: <n> agents by package area — merged by this session`, with one sub-line per area from
     `<run>/areas.txt`, its status after the number. The sub-line of a completed area ends with ` — verified`,
     ` — 0 rows`, ` — verifier failed` or ` — verifier not started`.
10. **Recommendations.** Write `## Recommendations (Priority Order)` over the merged rows, ending with one Tooling
    block (Phase 6, "Delegated to tools").
11. **Save** as Phase 6 says.
