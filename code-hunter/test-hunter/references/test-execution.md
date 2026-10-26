# Test Hunter — test execution

Read only when the prompt asks for a test run (SKILL.md Phase 5). Each language reference's Test execution section
names the toolchain default command, the coverage flag, and the update flags.

## Choose the command

Run the project's own test command (a CI step, a Makefile target, the package `test` script); with none, the
toolchain default the language reference names; with neither, `skipped — no test command`. Before the run, read the
effective command, including the config it loads. An update flag or setting in it (the language reference lists each
runner's) → `skipped — command updates snapshots`.

## Run it unchanged, with two additions

The command runs as the project defines it: no added `-race`, no `-count` re-runs, never an added update flag. Two
additions only:

- Jest and Vitest only: set `CI=1`, so a missing snapshot fails instead of being written. Other runners keep the
  environment as it is, because the project's tests may read `CI`.
- Coverage output goes into the run directory, with the runner's own flag from the language reference, when the
  command passes it to the runner: directly, or after `--` through a package script. Through a Makefile target or a
  CI script, only redirect output the command already writes; add no flag.

## Record what the run changed

Git-ignored files (runner caches) are not compared: the project's own command writes them on every run.

Before the run, in its own call:

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
S=before; git status --porcelain --untracked-files=all > <run>/status-$S.txt || exit 1
cut -c4- <run>/status-$S.txt | while read -r f; do [ -f "$f" ] && echo "$(git hash-object -- "$f") $f"; done > <run>/hash-$S.txt
```

Then run the test command in its own call. After the run, the same block with `S=after`. Then compare:

```bash
diff <run>/status-before.txt <run>/status-after.txt; diff <run>/hash-before.txt <run>/hash-after.txt
```

Scope lists every path whose status or content changed; the hunter restores nothing and deletes nothing.

## Record the result

- A run that exceeds the tool's time limit is `errored — timed out`, and its output is not used.
- A run with failing tests is `ran — <command>: <n> failed`, and Scope lists the failed tests; they are not findings.
- Coverage data supports a Coverage Gap only as "no test executes this line": coverage files are aggregate and cannot
  show which test hit a line. A line that coverage shows executed is not a "no test drives it" gap; when Phase 3
  found no test for it, record `unresolved coverage`. A gap that rests on blind tests, or on a test that does not pin
  a change, stands: coverage shows execution, not detection.
- A zero count describes the recorded command, not the suite. It supports "no test executes this line" only when the
  command's coverage includes that file and the command runs every test Phase 3 counted: no filter, every tag (the
  language reference names its forms). Otherwise Phase 3's mapping stands alone, and Scope records
  `coverage profile not used: <reason>`.

Done when Scope has the Test execution line and, after a run, the paths it changed and the failed tests.
