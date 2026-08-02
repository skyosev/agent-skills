---
name: party-hunter-go
description: |
  Run all 10 Go code quality hunters in parallel as subagents and write each report to a
  timestamped reports folder. Covers boundary, doc, invariant, security, simplicity, slop,
  smell, solid, test, and type hunters.

  Use when: running a full Go codebase audit, scanning all quality dimensions at once,
  preparing for a code review, or generating a comprehensive findings report.
disable-model-invocation: true
---

# Party Hunter — Go

Orchestrate a full audit of a Go codebase by running all 10 hunter skills as independent
subagents, each producing a focused report. Results land in a single timestamped folder
for easy review and sharing.

## Severity Levels

Every hunter report and the summary use the same four levels, for per-finding labels and
for recommendation grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

## Cost

A full party run launches ten specialized subagents over the same scope — inherently
token-expensive; that is the price of ten focused lenses. Two distinct controls, not to
be confused:

- **Bounded batches** (e.g. 3–4 hunters at a time) reduce peak concurrency and
  rate-limit pressure. They do **not** reduce total token cost — the same work runs
  either way.
- **Actual cost control** means doing less work: run a selected subset of hunters, stage
  the run and stop early when the first batch answers the question, or narrow the scope.

Default remains all ten in parallel; offer these controls when the user raises cost or
rate limits.

## Execution Protocol

### 1. Ask for scope

If the user has not specified a target (diff, file, package path, or directory), ask
before proceeding. Do not guess. Hunters run standalone default to the whole codebase; a
party run deliberately does not — a wrong guess here produces ten subagents' worth of
noise, so an explicit target is required.

### 2. Resolve the scope snapshot — before creating any files

Resolve the audit surface **exactly once, before the reports folder or any other file is
created**, and pass the frozen result to every hunter. Hunters must not re-resolve scope
in a party run: with working-tree diff semantics, later hunters would pick up earlier
hunters' freshly written reports as untracked input, and the ten surfaces would not be
identical. (Trade-off, stated: a snapshot intentionally excludes edits made after
resolution — mid-audit changes wait for the next run.)

For a **diff** scope ("audit my changes"), diff means committed + working tree — staged,
unstaged, and untracked files. Resolve fail-closed:

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
if [ -z "$BASE" ]; then
  for b in origin/main origin/master main master; do
    git rev-parse -q --verify "$b" >/dev/null && BASE=$b && break
  done
fi
# If BASE is still empty: STOP. Ask for an explicit base. Do not continue.

SCOPE=$( { git diff --name-only --diff-filter=d "$BASE"...HEAD;
           git diff --name-only --diff-filter=d HEAD;
           git ls-files --others --exclude-standard; } | sort -u )
DELETED=$( { git diff --name-only --diff-filter=D "$BASE"...HEAD;
             git diff --name-only --diff-filter=D HEAD; } | sort -u )
```

- If no base branch resolves: **stop and ask for an explicit base.** Do not fall through
  to a guessed base and do not widen to a codebase audit.
- If `$SCOPE` is empty: **do not launch any hunters.** Write a summary whose Run Status
  reads "Audit completed: 0 findings — empty diff scope", listing `$DELETED` as context
  if non-empty, and finish.
- Deleted files cannot be scanned but must not vanish: carry `$DELETED` into the
  summary's Scope section as "Deleted in diff: …".

For a **path or codebase** scope, expand it to a concrete file list the same way
(for example `git ls-files -- <paths>`).

Record the resolved file list (manifest) and the non-path metadata separately — both are
written in step 3 and referenced from the Run Status section. **Filenames containing
whitespace are unsupported:** the newline-delimited manifest plus shell expansion of
`$SCOPE` word-splits on spaces; do not include such paths in the snapshot.

If the resolved surface exceeds what can be read within the context budget, report the
file count and ask to narrow or chunk before launching.

### 3. Create the reports folder

```
reports/party-hunter-go/YYYY-MM-DDTHHMM/
```

Use the current timestamp. Create the folder before launching any subagents, then write
the scope snapshot as two files in the folder:

- `scope.txt` — **file manifest only**: one path per line. No base SHA, no Deleted list.
- `scope-meta.txt` — metadata: base SHA (diff scope), surface type (diff / path /
  codebase), deleted-in-diff list (if any), file count, and any other non-path metadata.

Reports are **ephemeral artifacts, not part of the audited codebase** — do not commit
them. If `reports/` is not already ignored, add it to `.gitignore` (this also keeps
report files out of any future untracked-file scope resolution).

### 4. Validate the hunter skill files

Subagents cannot load the hunter skills by name: every hunter carries
`disable-model-invocation: true`, which also prevents preloading into subagents. Each
subagent instead **reads its hunter's SKILL.md directly**. The hunters ship as sibling
directories of this skill, so the files resolve as
`${CLAUDE_SKILL_DIR}/../{hunter-dir}/SKILL.md` — that sibling layout is a packaging
contract, and this step enforces it.

| Hunter       | SKILL.md to read                                       | Output file       |
|--------------|--------------------------------------------------------|-------------------|
| Boundary     | `${CLAUDE_SKILL_DIR}/../boundary-hunter-go/SKILL.md`   | `boundary.md`     |
| Doc          | `${CLAUDE_SKILL_DIR}/../doc-hunter-go/SKILL.md`        | `doc.md`          |
| Invariant    | `${CLAUDE_SKILL_DIR}/../invariant-hunter-go/SKILL.md`  | `invariant.md`    |
| Security     | `${CLAUDE_SKILL_DIR}/../security-hunter-go/SKILL.md`   | `security.md`     |
| Simplicity   | `${CLAUDE_SKILL_DIR}/../simplicity-hunter-go/SKILL.md` | `simplicity.md`   |
| Slop         | `${CLAUDE_SKILL_DIR}/../slop-hunter-go/SKILL.md`       | `slop.md`         |
| Smell        | `${CLAUDE_SKILL_DIR}/../smell-hunter-go/SKILL.md`      | `smell.md`        |
| SOLID        | `${CLAUDE_SKILL_DIR}/../solid-hunter-go/SKILL.md`      | `solid.md`        |
| Test         | `${CLAUDE_SKILL_DIR}/../test-hunter-go/SKILL.md`       | `test.md`         |
| Type         | `${CLAUDE_SKILL_DIR}/../type-hunter-go/SKILL.md`       | `type.md`         |

Before launching any subagent, verify that all 10 SKILL.md files exist at the resolved
paths. If any are missing, **stop and report the missing paths** — do not launch a
partial party over a packaging error.

### 5. Launch all hunters as subagents

Run **all 10 subagents in parallel** (see Cost above for batching and cost controls).
Each subagent returns its report; the parent writes the files.

**Subagent prompt template** (adapt per hunter):

```
Read {resolved absolute path to the hunter's SKILL.md} and follow its instructions
exactly, with these overrides:

- Scope: audit exactly the files listed in {reports_folder}/scope.txt — an immutable
  file-manifest snapshot resolved by the orchestrator. Do not re-resolve the scope.
  Non-path metadata (base SHA, surface type, deleted-in-diff, file count) is in
  {reports_folder}/scope-meta.txt if needed — do not treat that file as audit input.
- Output: return the Markdown report as your final message — do not write any files
  (this overrides the skill's default output location).

Your report must include:
- An executive summary (2-3 sentences)
- Findings grouped by severity (Critical / High / Medium / Low) as defined in the skill
- For each finding: location, description, and a concrete fix suggestion
- Omitted severity groups and finding categories when they have zero items — no empty
  tables, placeholder headings, or negative statements like "no issues found"
- The "Audit completed: N findings" line in its Scope section

Return only the Markdown report — no commentary outside the report.
```

### 6. Write report files

As each subagent completes, write its output to the corresponding file inside the
reports folder. Do not wait for all subagents before writing — write as results arrive.
If a hunter finds nothing across all categories, write the one-line completion marker
`No findings.` rather than an empty file (see Output Contract for why this does not
violate the no-negative-statements rule).

### 7. Write summary

After all 10 subagents have finished, write `summary.md` to the same folder:

```markdown
# Party Hunter Report — Go
**Target**: {target_scope}
**Date**: {timestamp}

## Run Status

| Hunter | Status | Findings |
|--------|--------|----------|
| {each of the 10 hunters} | completed / failed / skipped | {N} |

**Base**: {base SHA, or "codebase"} · **Scope**: {N files} (manifest: `scope.txt`, meta: `scope-meta.txt`)
{Deleted in diff: {list} — only when non-empty}

## Cross-cutting Themes
{2-4 recurring patterns observed across multiple hunters}

## Top 5 Priority Issues
{Ranked list of the most impactful findings regardless of hunter}
```

**Summary requirements:**

- The **Run Status** section is mandatory and always complete: one row per hunter with
  status and finding count. A hunter that returned no report is recorded as `failed` —
  a missing report must be distinguishable from a never-launched or empty hunter.
  Execution status is not a finding — this section is exempt from the no-empty-sections
  rule.
- Aggregate duplicate findings from multiple hunters into a single actionable item.
- When two hunters give opposing recommendations for the same code, present both with
  the trade-off — do not pick one silently.

## Output Contract

Every report file must be valid Markdown. Finding counts in `summary.md` must match the
findings in individual reports. If a hunter finds nothing across all categories, write a
one-line note (`No findings.`) rather than an empty file — this completion marker is
**execution status, not a finding statement**, and is the explicit exception to the
no-negative-statements rule below.

## Operating Constraints

- **No empty finding sections.** Include only categories with findings. Omit a heading,
  table, or list entirely when it would contain zero items — do not include empty
  tables, placeholder subsections, or negative statements like "no dead exports", "none
  found", or "no issues". This rule applies to *findings only*: the Run Status section,
  per-hunter "Audit completed: N findings" lines, and the `No findings.` completion
  marker are execution status, always present, and never treated as empty-section
  violations.
