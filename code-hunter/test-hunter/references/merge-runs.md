# Test Hunter — merging runs

Read only when one report merges several runs (for example, one run per folder).

1. Copy each run's reproduction input, expected value and commit as the run wrote them. Change one only after you
   check it against the code, and then check the row's evidence bar again.
2. When the runs record different commits, or HEAD has moved since the runs, keep each run's commit and say so in
   Scope. The commit is where the evidence was read, not where the merge ran.
3. Judge each construct once. When two runs judge it differently (a cast as a double, and as data), decide once and
   apply the decision to both rows.
