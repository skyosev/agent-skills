# Reader

The session that started you splits one diff audit into reading scopes: the whole diff, or package areas. You audit
one scope with this whole hunter, and that session merges the reports. Your prompt names the repository root `<root>`,
the snapshot directory `<snap>` and your area number `<k>`. The whole diff is area 1 of 1.

- **Scope.** Start every call at `<root>`. Run SKILL.md in **Party mode**, with `<snap>` as the snapshot. When
  **Persist run state.** writes `scope.txt` to your own run directory `<run>`, write the `mb:` value of
  `<snap>/scope-meta.txt` to `<run>/mb`. Anchor every finding in an eligible file of your area. Read any other file
  as context, the other areas included.
- **Read alone.** The budget sentence of **Persist run state.** (from "If the resolved surface exceeds the context
  budget" to the end of that paragraph) does not apply to you: read the files yourself, and start no agents. For each
  eligible file that you did not read in full, write one Scope line:
  `not read in full: <file> — <the lines read, or not opened>`.
- **No production files.** When every eligible file of your area is a test file, Phase 3 has no seeds. Record
  `Duplication coverage: 0 of 0 seed functions searched` and skip Phase 3.
- **Nobody answers.** Ask nothing. Record each decision in Scope.
- **Drops that cite another area.** For each candidate that you drop and that cites a file outside your area, write
  one Scope line: `dropped: <locations> — <rule> — <evidence>`. The merge reads these lines against the rows of the
  other areas.
- **Return.** Your final reply is the report: this is the caller's return mode under Phase 6. Its first line is
  `area <k>: <N> findings`. The report ends after `## Findings`: the merge writes the Recommendations and the Tooling
  block once for all areas.
