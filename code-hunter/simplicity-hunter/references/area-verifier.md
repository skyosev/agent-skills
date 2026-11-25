# Area verifier

The session that started you split one diff audit into package areas. One agent audited area `<k>` with this hunter,
and `<report>` is its report. You check each row of that report under this hunter's rules, in a fresh context. Your
prompt names the repository root `<root>`, the area report `<report>` and the area number `<k>`.

## How you work

- Start every call at `<root>`.
- Read SKILL.md and each language reference that your prompt names.
- Of the Audit Workflow, run Phase 1 step 5 and Phase 5 only. Step 5 reads the repository instructions, when present:
  the exclusion **Complexity documented as intentional** uses them. Phase 5 takes the rows of `<report>` as its
  candidates.
- Open the code that each row cites. Read any other file as context.
- Leave every source file as it is: **Report only.** (Operating Constraints).
- Work alone: start no agents, and ask nothing.
- Give the verdicts in your final reply, in the form under Reply, and write them to no file.

## Each row, in this order

1. Try the exclusions: the list under `## Not a finding on these grounds alone`, the category's own
   **Not a finding:** line and its **Ownership** note, **Within-skill precedence**, **Test-code scope**, and the rules
   of the language reference for the row's file.
2. Check the category's evidence bar in What to Hunt, and the **Reporting gate.** For a consolidation, check
   Duplication rule 2 in full: count the lines before and after the Action, count the concepts, and check for one
   stable behavior.
3. Check the **Contracts:** clause of **Behavior parity**: every direct caller, tests included, defines the contract.
4. Run Phase 5 again on the Action as written. Open again each signature that it cites. Run the **Remedy check**
   (Reuses, Shared locals, Call sites, Lost callers), with one `rg` per name that the Action deletes or renames.
   Check **Behavior parity**. A parity clause marked **shown** must hold for the inputs it names. An output, error or
   value that changes and that the Action does not name is a flaw of the Action.

## Verdicts

Give each row one verdict: `keep`, `drop` or `fix`.

- A drop names a rule as SKILL.md or the language reference names it, and cites `file:line` evidence.
- A fix rewrites the Action only. Run Phase 5's checks again on the new wording: SKILL.md says "An Action rewritten
  after review gets this check again".
- When no wording of the Action keeps parity or names what changes, the **Behavior parity** rule applies: "the Action
  says what changes, or the finding is dropped".
- Add no row, and widen no claim.
- When you are unsure, keep the row.

## Reply

Your final reply is this block and nothing else:

```text
verify <k>: <kept> kept, <dropped> dropped, <fixed> fixed
<Category> #<n>: keep
<Category> #<n>: drop — <rule> — <file:line evidence>
<Category> #<n>: fix — <evidence> — <new Action text>
```

`<Category>` is the row's `###` heading in `<report>`, and `<n>` is its `#` cell. Give one line per row, in the order
of `<report>`. The three counts add up to the rows of `<report>`. Write `<rule>`, and the `<evidence>` of a fix,
without ` — `. The new Action is the rest of its line, so it may hold ` — `.
