---
name: party-hunter-ts
description: |
  Run all 12 TypeScript code quality hunters in parallel as subagents and write each report
  to a timestamped reports folder. Covers boundary, doc, error, invariant, perf, security,
  simplicity, slop, smell, solid, test, and type hunters.

  Use when: running a full TypeScript codebase audit, scanning all quality dimensions at
  once, preparing for a code review, or generating a comprehensive findings report.
disable-model-invocation: true
---

# Party Hunter — TypeScript

Orchestrate a full audit of a TypeScript codebase by running all 12 hunter skills as
independent subagents, each producing a focused report. Results land in a single
timestamped folder for easy review and sharing.

## Severity Levels

Every hunter report and the summary use the same four levels, for per-finding labels and
for recommendation grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

## Execution Protocol

### 1. Ask for scope

If the user has not specified a target (diff, file, module path, or directory), ask before
proceeding. Do not guess. Hunters run standalone default to the whole codebase; a party
run deliberately does not — a wrong guess here produces twelve subagents' worth of noise,
so an explicit target is required.

### 2. Resolve the scope snapshot — before creating any files

Resolve the audit surface **exactly once, before the reports folder or any other file is
created**, and pass the frozen result to every hunter. Hunters must not re-resolve scope
in a party run: with working-tree diff semantics, later hunters would pick up earlier
hunters' freshly written reports as untracked input, and the twelve surfaces would not be
identical.

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
- Deleted files cannot be scanned but must not vanish: carry `$DELETED` into the summary's
  Scope section as "Deleted in diff: …".

For a **path or codebase** scope, expand it to a concrete file list the same way
(for example `git ls-files -- <paths>`).

Record the base SHA (diff scope) and the resolved file list — both go into `scope.txt`
and the Run Status section.

If the resolved surface exceeds what can be read within the context budget, report the
file count and ask to narrow or chunk before launching.

### 3. Create the reports folder

```
reports/party-hunter-ts/YYYY-MM-DDTHHMM/
reports/party-hunter-ts/YYYY-MM-DDTHHMM/hunters/
```

Use the current timestamp. Create **both** folders before launching any subagents, then
write the scope snapshot to `scope.txt` in the reports folder root: the base SHA (for
diff scopes) on the first line, followed by one file path per line, and a
`Deleted in diff:` list if applicable.

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

| Hunter       | SKILL.md to read                                     | Output file            |
|--------------|------------------------------------------------------|------------------------|
| Boundary     | `${CLAUDE_SKILL_DIR}/../boundary-hunter-ts/SKILL.md`   | `hunters/boundary.md`  |
| Doc          | `${CLAUDE_SKILL_DIR}/../doc-hunter-ts/SKILL.md`        | `hunters/doc.md`       |
| Error        | `${CLAUDE_SKILL_DIR}/../error-hunter-ts/SKILL.md`      | `hunters/error.md`     |
| Invariant    | `${CLAUDE_SKILL_DIR}/../invariant-hunter-ts/SKILL.md`  | `hunters/invariant.md` |
| Perf         | `${CLAUDE_SKILL_DIR}/../perf-hunter-ts/SKILL.md`       | `hunters/perf.md`      |
| Security     | `${CLAUDE_SKILL_DIR}/../security-hunter-ts/SKILL.md`   | `hunters/security.md`  |
| Simplicity   | `${CLAUDE_SKILL_DIR}/../simplicity-hunter-ts/SKILL.md` | `hunters/simplicity.md`|
| Slop         | `${CLAUDE_SKILL_DIR}/../slop-hunter-ts/SKILL.md`       | `hunters/slop.md`      |
| Smell        | `${CLAUDE_SKILL_DIR}/../smell-hunter-ts/SKILL.md`      | `hunters/smell.md`     |
| SOLID        | `${CLAUDE_SKILL_DIR}/../solid-hunter-ts/SKILL.md`      | `hunters/solid.md`     |
| Test         | `${CLAUDE_SKILL_DIR}/../test-hunter-ts/SKILL.md`       | `hunters/test.md`      |
| Type         | `${CLAUDE_SKILL_DIR}/../type-hunter-ts/SKILL.md`       | `hunters/type.md`      |

Before launching any subagent, verify that all 12 SKILL.md files exist at the resolved
paths. If any are missing, **stop and report the missing paths** — do not launch a
partial party over a packaging error.

### 5. Launch all hunters as subagents

Run **all 12 subagents in parallel**. Each subagent writes its own report file and
returns only a one-line status.

**Subagent prompt template** (adapt per hunter):

```
Read {resolved absolute path to the hunter's SKILL.md} and follow its instructions
exactly, with these overrides:

- Scope: audit exactly the files listed in {reports_folder}/scope.txt — an immutable
  snapshot resolved by the orchestrator. Do not re-resolve the scope.
- Output: write your report to {reports_folder}/hunters/{hunter-name}.md
  (absolute path — this overrides the skill's default output location).

Your report must include:
- An executive summary (2-3 sentences)
- Findings grouped by severity (Critical / High / Medium / Low) as defined in the skill
- For each finding: location, description, and a concrete fix suggestion with code
  examples where applicable
- Omitted severity groups and finding categories when they have zero items
- The "Audit completed: N findings" line in its Scope section

After writing the file, return exactly one status line:
{hunter-name}: completed — N findings   (or: {hunter-name}: failed — {reason})
```

### 6. Write summary

After all 12 subagents have finished, write `summary.md` to the reports folder root.
The summary must be **fully self-sufficient**: anyone reading it should be able to
implement all suggestions without consulting the individual hunter reports.

```markdown
# Party Hunter Report — TypeScript
**Target**: {target_scope}
**Date**: {timestamp}

## Run Status

| Hunter | Status | Findings |
|--------|--------|----------|
| {each of the 12 hunters} | completed / failed / skipped | {N} |

**Base**: {base SHA, or "codebase"} · **Scope**: {N files} (snapshot: `scope.txt`)
{Deleted in diff: {list} — only when non-empty}

## Executive Summary
{2-3 sentences summarizing the overall code quality state and most critical areas needing attention}

## All Actionable Findings

### Security Issues
{All security-related findings with location, description, and concrete fix}

### Type Safety Issues
{All type-related findings with location, description, and concrete fix}

### Error Handling Issues
{All error handling findings with location, description, and concrete fix}

### Code Quality Issues
{All smell, slop, simplicity, and SOLID findings with location, description, and concrete fix}

### Documentation Issues
{All documentation findings with location, description, and concrete fix}

### Testing Issues
{All testing findings with location, description, and concrete fix}

### Architecture & Boundary Issues
{All boundary and invariant findings with location, description, and concrete fix}

### Performance Issues
{All performance findings with location, description, and concrete fix}

## Priority Action Items
{Ranked list of the top 5-10 most impactful fixes, each with:
- What to fix (location + issue)
- Why it matters (impact/risk)
- How to fix (concrete steps or code example)}
```

**Summary requirements:**
- The **Run Status** section is mandatory and always complete: one row per hunter with
  status and finding count. A hunter that returned no status line or wrote no report is
  recorded as `failed`. Execution status is not a finding — this section is exempt from
  the no-empty-sections rule.
- Include **only actionable items** in the findings sections — omit a category's section
  entirely if it has no findings
- Do **not** include empty tables, placeholder headings, or negative statements ("no dead
  exports", "no issues found", etc.) in the findings sections
- Every finding must include: file location, issue description, and a concrete fix suggestion
- Fix suggestions must be specific enough to implement without consulting hunter reports
- Aggregate duplicate findings from multiple hunters into a single actionable item
- When two hunters give opposing recommendations for the same code, present both with the
  trade-off — do not pick one silently

## Operating Constraints

- **No empty finding sections.** Include only finding categories that have findings. Omit
  a heading, table, or list entirely when it would contain zero items — do not include
  empty tables, placeholder subsections, or negative statements like "no dead exports",
  "none found", or "no issues". This rule applies to *findings only*: the Run Status
  section and per-hunter "Audit completed: N findings" lines are execution status, always
  present, and never treated as empty-section violations.
