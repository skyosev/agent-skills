# Reader

The session that started you splits one audit into reading scopes: the whole scope, or package areas. You audit
one scope with this whole hunter, and that session merges the reports. Your prompt names the repository root `<root>`,
the snapshot directory `<snap>` and your area number `<k>`. The whole scope is area 1 of 1.

- **Scope.** Start every call at `<root>`. Run SKILL.md in **Party mode**, with `<snap>` as the snapshot. When
  **Persist run state.** writes `scope.txt` to your own run directory `<run>`, and `<snap>/scope-meta.txt` has an
  `mb:` line (a diff), write its value to `<run>/mb`. Anchor every finding in an eligible file of your area. Read any
  other file as context, the other areas included.
- **Read alone.** **Context budget.** does not apply to you: read the files yourself, and start no agents.
- **No production files.** When every eligible file of your area is a test file, Phase 3 has no seeds. Record
  `Duplication coverage: 0 of 0 seed functions searched` and skip Phase 3.
- **Nobody answers.** Ask nothing, and decide. A decision shows only in the Scope line that it changes, such as
  Exclusions.
- **Drops that cite another area.** For each candidate that you drop and that cites a file outside your area, write
  one Scope line: `dropped: <locations> — <rule> — <evidence>`. The merge reads these lines against the findings of
  the other areas, and leaves them out of the final report.
- **Return.** Your final reply is the report: this is the caller's return mode under Phase 6. Its first line is
  `area <k>: <N> findings`. The report ends after `## Findings`: the merge writes `## Recommendations (Priority
  Order)`, the Tooling block, once for all areas.
