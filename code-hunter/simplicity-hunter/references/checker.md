# Checker

The session that started you splits one diff audit into reading scopes: the whole diff, or package areas. One or more
readers audited scope `<k>` with this hunter, each in its own report. You check every finding of every report under
this hunter's rules, in a fresh context. Your prompt names the repository root `<root>`, the scope number `<k>`, and
each report as `<report ID> <path>`.

## How you work

- Start every call at `<root>`.
- Read SKILL.md and each language reference that your prompt names.
- Of the Audit Workflow, run Phase 1 step 5 and Phase 5 only. Step 5 reads the repository instructions, when present:
  the exclusion **Complexity documented as intentional** uses them. Phase 5 takes the findings of every report as its
  candidates.
- Judge each finding as its report wrote it. Two reports can hold the same finding: give each copy its own verdict.
  The merge joins the copies.
- Open the code that each finding cites. Read any other file as context.
- Run each probe (a scratch build, a test run) in a folder from `mktemp -d`. Change no file under `<root>`. (A Codex
  checker can write only inside its job folder, where `TMPDIR` points.)
- Leave every source file as it is: **Report only.** (Operating Constraints).
- Work alone: start no agents, and ask nothing.
- Give the verdicts in your final reply, in the form under Reply, and write them to no file.

## Each finding, in this order

1. Try the exclusions that Phase 5 names.
2. Check the category's evidence bar in What to Hunt, and the **Reporting gate.** For a consolidation, check
   Duplication rule 2 in full: count the lines before and after the Action, count the concepts, and check for one
   stable behavior.
3. Check the finding's claim under the **Contracts:** clause of **Behavior parity**: every direct caller, tests
   included, defines the contract.
4. Run Phase 5 again on the Action as written. Open again each signature that it cites. Run the **Remedy check**
   (Reuses, Shared locals, Call sites, Lost callers), with one `rg` per name that the Action deletes or renames.
   Check **Behavior parity**. A parity clause marked **shown** must hold for the inputs it names. An output, error or
   value that changes and that the Action does not name is a flaw of the Action.

## Verdicts

Give each finding one verdict: `keep`, `drop` or `fix`.

- A drop names a rule as SKILL.md or the language reference names it, and cites `file:line` evidence. The merge
  judges every disagreement with the drop against that rule.
- A fix rewrites the Action only. Run item 4 of "Each finding, in this order" again on the new wording.
- When no wording of the Action keeps parity or names what changes, the **Behavior parity** rule applies: "the Action
  says what changes, or the finding is dropped".
- Add no finding, and widen no claim.
- When you are unsure, keep the finding.

## Reply

Your final reply is the lines of this block, without the fence, and nothing else:

```text
verify <k>: <kept> kept, <dropped> dropped, <fixed> fixed
<report ID> <Category> #<n>: keep
<report ID> <Category> #<n>: drop — <rule> — <file:line evidence>
<report ID> <Category> #<n>: fix — <evidence> — <new Action text>
```

Give one line per finding: the reports in the order of your prompt, and the findings of each report in its order.
`<Category>` is the text of the finding's `###` heading in its report, without the `###`, and `<n>` is its `#` cell.
The three counts add up to the findings of all the reports. Write the `<evidence>` of a fix without ` — `. The new
Action is the rest of its line, so it may hold ` — `.
