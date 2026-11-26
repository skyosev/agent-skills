# Orchestrator

Contents: Words · Shape · Approval · The run plan · Readers · Checkers · Merge

This session reads the request's words, chooses the shape, shows the run plan when the approval rules say so, starts
the readers and the checkers, and merges their reports. A reader audits one reading scope with this whole hunter: the
whole diff, or one package area. A checker judges every finding of every report of one scope again, in a fresh
context. With more than one reader, Phase 1 step 5 and Phases 2 to 5 run in the readers, and Phase 1 step 5 and
Phase 5 run again in the checkers. This session judges disputes and joins duplicates, so it writes none of the
reports: it reads no code for findings, and opens code only where a merge step asks. The readers answer the context
budget, so ask nothing about it. With one reader, this session is the reader: today's run, as SKILL.md describes it.
`<skill>` is the directory that SKILL.md was read from, `<root>` is the repository root, and `<run>` is the run
directory of **Persist run state.**

## Words

The words are plain words in the request; there is no flag parser.

| Word | Effect |
|---|---|
| `single` | one reading scope: the whole diff |
| `areas N` | split into N areas, also on a diff of up to 160 KB |
| `readers N` | N readers of each LLM for each reading scope (default 1). With Codex, `readers 2` means 2 Claude and 2 Codex readers per scope |
| `no codex` | no Codex readers or checker, as when Codex is not available: today's run on the whole diff, and Claude readers with the Claude checker on areas |
| `no agents` | today's run: this session reads alone, with no sub-agents, no Codex and no checkers. This also holds when the budget sentence would otherwise split the reading over sub-agents |
| `confirm`, `unattended` | wait for "go" even with one reader; never wait |

- A word sets up the run only when the request uses it to set up the run. "Check the 2 areas I changed" is not
  `areas 2`.
- `no agents` overrides the words that set readers, areas and Codex. `confirm` and `unattended` still apply to it.
- When other words contradict each other (`single` with `areas N`, or `confirm` with `unattended`), ask which one
  holds. With nobody to answer (Approval), return the question as the final reply and stop. An `areas N` or
  `readers N` whose N is not a whole number of 1 or more is a contradiction too, settled before any split.

## Shape

1. `no agents`: one reader. Go to Approval.
2. Run `bash <skill>/scripts/split-areas.sh <run>`, with ` 1` added for `single` and ` <N>` for `areas N`. It prints
   one line per area, `<k>: <files> files, <bytes> bytes (<production> production) — <units>`, then
   `areas: <n>, <bytes> eligible bytes`. A unit is one directory's eligible files, tests included. One area is the
   whole diff. On a non-zero exit, add the Scope line `Run modes: split failed — <its message>`, and go to Approval
   with one reader.
3. Codex is available when `command -v codex >/dev/null && codex login status 2>&1` succeeds. With `no codex`, skip
   the check: Codex does not run. When Codex is not available, add the Scope line
   `Codex: not available — <the last line of the output, or "codex is not on PATH">`. The plan shows the same reason.
4. Each scope gets `readers N` Claude readers (default 1), and as many Codex readers when Codex runs. One reader in
   all is today's run.
5. The Claude readers start at once: the areas times N. Above 20, refuse before any plan: give the count, and the
   words that reduce it (`readers 1`, `areas <M>`, `single`, `no agents`). The checkers start after the readers end,
   one Claude checker per area at most.

Steps 2 to 4 give the automatic shape, when the request has no word that sets the shape:

| Eligible changed code | Codex available | Codex not available |
|---|---|---|
| up to 160 KB, or the split gives one area | whole diff: 1 Claude and 1 Codex reader; a Claude and a Codex checker | today's run |
| above 160 KB, 2 to 20 areas | areas: 1 Claude and 1 Codex reader per area; both checkers per area | areas: 1 Claude reader and the Claude checker per area |
| more than 20 areas | packed into 20 areas, as `areas 20` | the same, Claude only |

## Approval

- A run with more than one reader shows its plan and waits for "go". `unattended` skips the wait.
- A run with one reader starts at once, unless the request says `confirm`.
- When a run would wait and nobody can answer, it returns its plan as its final reply and stops. This holds for the
  default wait and for `confirm`. Nobody can answer when another skill or agent started this hunter, or when the
  request says that nobody answers. A caller that has approved the spend adds `unattended`.
- A reply with words makes a new plan, shows it, and waits for "go" again. A word of the reply replaces each word of
  the request that sets the same thing: `single` replaces `areas 4`. Run Shape again on the same `<run>`; the split
  first removes every `<run>/a<k>/`.
- After "go", or at once when the run does not wait, a run with one reader continues SKILL.md as written, from
  Phase 1 step 5. Under `no agents`, where the budget sentence of **Persist run state.** offers a split over
  sub-agents, read alone instead. A run with more than one reader goes on to Readers.

## The run plan

`[…]` is shown only when it applies:

```text
simplicity-hunter plan: diff <merge base>..<HEAD> (<eligible KB> KB eligible, <files> files)

Shape      <whole diff | <n> areas by package> (<automatic | requested: <the words>>)
Readers    per <scope>: <N> Claude (<LLM family>, xhigh)[ + <N> Codex (gpt-6.2-sol, high)] = <total> readers
             <k>  <units>   <files> files, <KB> KB
Checkers   per <scope>: 1 Claude[ + 1 Codex]; each checks every finding of every reader of its scope
Merge      this session: applies both verdicts; judges each dispute against the rule
           that the dropping checker named; joins duplicates across readers and areas
Estimate   Claude readers ~$<a>, Claude checkers ~$<b>; merge and reply writing not measured.
           [Codex uses your plan's quota.]
[Codex     not available — <why>]
[Warning   each reader reads only part of a diff above 160 KB]

Reply "go", or change the run with: no codex, single, areas N, readers N, no agents
```

- `<merge base>` and `<HEAD>` are the short SHAs of `<run>/mb` and of `HEAD`.
- `<eligible KB>` is the eligible bytes of the split's `areas:` line divided by 1000, and `<files>` is the sum of the
  files of its area lines. Without a split (`no agents`, or a failed split), the eligible bytes are the sizes of the
  files in Phase 1's eligible lists, and `<files>` is their count.
- `<scope>` is `area` when the shape has areas, else `scope`. `<LLM family>` is this session's, as `Opus`. `<total>`
  counts the readers of every scope.
- `requested:` names the words of the request that set up the run, other than `confirm` and `unattended`. With none,
  the shape is `automatic`.
- The area lines come from the split's output, one per area, with each area's bytes in KB.
- `<a>` is N × the eligible KB × $3.40 / 100. `<b>` is the number of reports (scopes × N × the LLMs) × $1.60. Round
  both to whole dollars.
- The warning shows when the shape is the whole diff, the diff is above 160 KB, and it has more than one reader.
- A plan with one reader (shown under `confirm`) has the line
  `Readers    this session reads the diff alone (today's run); no checkers` in place of Readers, Checkers and
  Merge, and `Estimate   this session ~$<a>` with N = 1.

## Readers

The run folder:

```text
<run>/areas.txt                        the split: one line per scope, "<k>: <files> files, <bytes> bytes (<prod> production) — <units>"
<run>/a<k>/scope.txt, scope-meta.txt   the snapshot of scope k; the whole diff is a1
<run>/a<k>/r<i>.md                     report r<i> of scope k
<run>/codex/a<k>-r<i>/                 the Codex reader job of report r<i>: prompt.md, reply.md, log.txt, tmp/
<run>/codex/a<k>-check/                the Codex checker job of scope k
```

Report IDs are per scope, in the order Claude 1, Codex 1, Claude 2, Codex 2, …, over the LLMs that run. With
`no codex` and `readers 2`, `r1` is Claude 1 and `r2` is Claude 2. `Claude 1` and `Codex 1` are reader positions. The
checkers see report IDs only, so that no checker knows which LLM wrote a report; this session keeps the mapping.

Start every reader in one message:

- **Claude readers.** One general-purpose agent per Claude reader, in the background. Pass each agent `model`, the
  alias of this session's LLM family (`opus` in an Opus session), and `effort: xhigh`. The Agent call takes an alias,
  not a full ID, and an alias in this session's family runs on this session's version. Without them, a sub-agent
  setting exported for other work, such as `CLAUDE_CODE_SUBAGENT_EFFORT`, would choose the readers. A sub-agent does
  not get the skill text that this session loaded, so its prompt carries absolute paths. Give each agent this prompt
  and nothing else:

  ```text
  Read <skill>/references/reader.md, then <skill>/SKILL.md, and follow them.
  Repository: <root>. Snapshot: <run>/a<k>. Area <k> of <n>.
  ```

- **Codex readers.** One Bash command for all of them, in the background, with the Bash tool's `timeout: 3720000`. It
  writes the same prompt to `<run>/codex/a<k>-r<i>/prompt.md` for each Codex reader, then runs
  `bash <skill>/scripts/codex-jobs.sh <job>...` on those job folders. The launcher prints one line per job:
  `<job>: ok`, or `<job>: failed — <why>`. Without the timeout, `claude -p` stops a background command after
  10 minutes, and the launcher can run for an hour: its cap of 3600 s, 60 s to kill a job, and 60 s spare.

Each reply arrives when its reader ends. Write each Claude reader's reply verbatim to `<run>/a<k>/r<i>.md`: Claude
Code refuses a report file from a sub-agent, so this session writes it. When the launcher ends, copy the `reply.md`
of each `ok` job to `<run>/a<k>/r<i>.md`. So the checkers' paths do not name the LLM.

A report is `completed` when it starts with `area <k>: <N> findings` for its own scope, its Findings tables hold
exactly N rows, and it has an `Audit completed` line. Else its reader is `failed — <what>`: the launcher's status
(`timed out`, `exit <n>`, `empty reply`), or the first of these that fails: `no header`, `<m> rows, not <N>`,
`no Audit completed line`. A reader whose agent could not start, or whose job has no status line, is `not started`.
Start no reader again. The findings of a failed report are neither checked nor merged.

## Checkers

Start the checkers when every reader has ended. A scope gets checkers only when its completed reports hold a finding,
and the prompt lists only the reports with findings. Each such scope gets one Claude checker, and one Codex checker
when Codex readers ran. Start them all in one message:

- each Claude checker as a general-purpose agent in the background, with the same `model` and `effort` as the
  readers;
- every Codex checker in one background Bash command, with `timeout: 3720000`. It writes each prompt to
  `<run>/codex/a<k>-check/prompt.md`, then runs the launcher on those job folders.

The prompt is the same for both. It names one `<skill>/references/simplicity-<lang>.md` for each language reference
that this session loaded:

```text
Read <skill>/references/checker.md, then <skill>/SKILL.md and <skill>/references/simplicity-<lang>.md, and follow them.
Repository: <root>. Scope <k>. Reports: r1 <run>/a<k>/r1.md, r2 <run>/a<k>/r2.md.
```

A checker's reply is its verdict list. A Codex checker's reply is its job's `reply.md`.

```text
verify <k>: <kept> kept, <dropped> dropped, <fixed> fixed
<report ID> <Category> #<n>: keep
<report ID> <Category> #<n>: drop — <rule> — <file:line evidence>
<report ID> <Category> #<n>: fix — <evidence> — <new Action text>
```

Read each line without a leading `- `, `*` and backticks. A verdict list is complete when its first line that is not
a code fence starts with `verify <k>:` for its own scope, it gives exactly one verdict for each finding of each report
that the checker got, its three counts add up to those findings, each `drop` names a rule and evidence, and each
`fix` has new Action text after its second ` — `. A verdict repeated in place of another finding's leaves that
finding without one.

A checker is `completed` when its verdict list is complete. Else it is `failed — <what>`: the launcher's status, or
the first problem of `no verify header`, `header names area <j>`, `no verdict for <finding>`, `two verdicts for
<finding>`, `a verdict for unknown <finding>`, `counts add up to <x> of <y> findings`, `drop without a rule:
<finding>` and `fix without a new Action: <finding>`. A checker that could not start is `not started`. In a scope
without findings, each checker is `no findings`. Start no checker again.

## Merge

Merge when every checker has ended. Phase 6 "Merging a split run" applies to every finding. Within its scope, a
finding is `<report ID> <Category> #<n>`, so two reports of one scope can both hold a `Duplication #1`. Its key is
`area <k> r<i> <Category> #<n>`: its scope, its report, its `###` heading and its `#` cell. The whole diff is area 1.
Copy each row's cells and row note as its reader wrote them.

1. **Verdicts.** Only complete verdict lists count. A verdict applies only to its own report's finding: another
   report's copy of the same finding keeps its own verdicts, and step 4 joins the copies. For each finding:

   | Claude checker | Codex checker | Result |
   |---|---|---|
   | keep | keep | keep |
   | drop | drop | drop, with a Scope line `dropped (checkers)` |
   | drop | keep (or the reverse) | a dispute (step 2) |
   | drop | fix (or the reverse) | a dispute (step 2). When the finding stays, the fix applies |
   | fix | keep (or the reverse) | the fix applies |
   | fix | fix | pick one of the two Actions, or merge them |
   | one checker failed or did not start | — | the other checker's verdict applies alone; Scope records the failed checker |
   | both checkers failed | — | the scope's findings stay unchecked, and `Audit completed` ends with `— partial: <scope> not verified` |

   Without Codex readers, the Claude checker's verdict applies alone. A kept finding stays as its reader wrote it. A
   fixed finding takes the new Action, all the text after the second ` — `, and its row-note line gets the
   `Action changed:` clause. A dropped finding leaves the tables. Of two fixes, take one Action word for word, unless
   each covers a site or a condition that the other lacks: then merge them.
2. **Disputes.** Open the code, and judge the finding against the rule that the dropping checker named. When the
   rule holds, drop the finding with its `dropped (dispute)` line. Otherwise keep it, and its row-note line gets the
   `dispute:` clause. Both name the checker that dropped, so real runs show whether this session overrules one
   checker's drops more often than the other's.
3. **Disagreement**, between readers of different areas only: within one scope, the checkers have judged every
   finding. When a report's `dropped:` line or another Scope note drops a candidate with a reason, and a report of
   another area holds that candidate as a finding that steps 1 and 2 keep, open the code that the finding cites and
   judge it against that reason. Drop it when the reason holds under a named rule of SKILL.md or the language
   reference, with its `dropped (disagreement)` line. Otherwise it stays, and its row-note line gets the clause
   `another area dropped it: <reason>`.
4. **One finding per defect.** This step takes every finding of the completed reports, the dropped ones included.
   Two locations are near when they are in the same file, and within 3 lines of each other or in the same function.
   Two findings from two reports are candidates for one when a location of one is near a location of the other, or
   when both name the same dependency (a Replaceable dependency finding can anchor at imports in different files).
   Join them only when they name the same defect: two findings in one function can be separate. The copies of one
   defect share one place, the kept copy's row or one dropped line that names them all:
   - Every copy dropped: one dropped line, of the kind that dropped the copy that the tie-break would keep.
   - Some copies dropped and others surviving: a dispute. Open the code, and judge a surviving copy against the
     dropped copy's rule. When the rule holds for the defect itself, drop the defect with one `dropped (dispute)`
     line. When the rule held only for the dropped copy's claim or Action, the surviving copies stay, and the row's
     `dispute:` clause names that rule.
   - Surviving copies: one row. Phase 6's rule picks the claim, which brings its category and Action. When both
     claims clear the evidence bar, Within-skill precedence picks. Where none of its rules applies, keep the copy
     with more locations, then the copy from the lower area number, then the one with the lower report ID. The row
     takes the higher Severity and the higher Impact of the copies. When each copy has a location with no near
     location in the other, the row lists the locations of all, and its Action covers them. Anchor the row at its
     location whose path sorts first.

   A dropped line of several copies takes its location and claim from the copy that the tie-break would keep, and
   its rule, evidence and checker from the drop that it records.
   `Found by:` names every reader LLM whose report held a copy, dropped copies included.
5. **Keys.** Each row's `from:` and each dropped line's `from:` name the keys of the copies that they hold, the kept
   copy first, separated by `; `. Before Layout, check that every finding of every completed report has its key in
   exactly one place.
6. **Two Actions on one function.** When rows from any two reports change the same function, open the function and
   judge the two Actions together: one must not undo the other (Duplication, rule 2).
7. **A changed Action is checked again.** Run Phase 5's Remedy check and Behavior parity on the final wording of each
   Action that this session writes or changes: a merge of two fixes, a joined finding, step 6, a fix extended to
   another site. A checker's fix taken word for word is not checked again: its checker has run both. The
   `Action changed:` clause names a checker when the Action is that checker's new Action word for word, and
   `this session` when the merge wrote it.
8. **Layout.** Category sections in report-format.md order, with no empty section. Number each table from 1, and
   fix every `#<n>`.
9. **Count.** `Audit completed: <N> findings` counts the rows. Add one ending per case:
   - `— partial: <scope> not audited`: no reader of the scope completed;
   - `— partial: <scope> <position> not audited` or `— partial: <scope> <position> not started`: one reader of a
     scope that another reader completed;
   - `— partial: <scope> not verified`: the scope has findings, and no checker of it completed.

   `<scope>` is `area <k>` or `whole diff`. `<position>` is `Claude <n>` or `Codex <n>`.
10. **Scope**, in report-format.md order:
    - The Phase 1 lines, once: they describe the whole diff. Leave out each report's line of the same name.
    - `Codex: not available — <why>`, when Shape added it, before the coverage lines.
    - `Duplication coverage (<position>): <searched> of <total> seed functions searched` and
      `Added units (<position>): <n> listed`, one each per reader position, summed over the areas. A dependency
      counts once. Never sum two readers of one scope: nobody knows how far their seeds overlap.
    - Every other line of a completed report, except `Audit completed`: once when every completed report gives the
      same text, else once per report as `<line> (area <k>, <position>)`. Every `not read in full` line gets
      ` (area <k>, <position>)`.
    - The dropped lines of steps 1 to 4, one per defect. `<location>` is its anchor, one `file:line`. `<checker>` is
      `the Claude checker`, `the Codex checker` or `both checkers`.

      ```text
      dropped (checkers): <location> — <claim in one clause> — <rule> — <evidence> — by <checker> — from: <keys>
      dropped (dispute): <location> — <claim in one clause> — <rule> — <evidence> — by <checker> — from: <keys>
      dropped (disagreement): <location> — <claim in one clause> — <rule> — <evidence> — from: <keys>
      ```

    - The `Run:` line and its sub-lines. `<alias>` is the `model` that the Claude readers got. A scope's sub-line is
      its `areas.txt` line with `area <k>:` in place of `<k>:`, or `whole diff:` in a whole-diff run. Under it come
      its readers in report-ID order, then its checkers. The Codex checker line appears only when Codex readers ran.

      ```md
      - Run: <whole diff | <n> areas by package>, <automatic | requested: <the words>> — per <area | scope> <N> Claude reader(s) (<alias>, xhigh)[ and <N> Codex reader(s) (gpt-6.2-sol, high)] — <Claude checker | Claude and Codex checkers> — <waited for "go" | unattended> — merged by this session
        - area <k>: <files> files, <bytes> bytes (<production> production) — <units>
          - r<i> (<position>): <completed | failed — <what> | not started>
          - Claude checker: <completed | failed — <what> | not started | no findings>
          - Codex checker: <completed | failed — <what> | not started | no findings>
      ```

11. **Row notes.** Each note starts with the row-note line of report-format.md (**Row notes.**), which holds every
    clause that the merge adds. Each checker clause gives that checker's verdict on the kept copy, or `failed` or
    `not started`. The Codex checker clause appears only when Codex readers ran. When no checker of the scope
    completed, the line ends `— not verified` in their place. The reader's note follows on the next lines, unchanged,
    except that its first line loses its `#<n> — ` head.
12. **Recommendations.** Write `## Recommendations (Priority Order)` over the merged rows, ending with one Tooling
    block (Phase 6, "Delegated to tools").
13. **Save** as Phase 6 says.
