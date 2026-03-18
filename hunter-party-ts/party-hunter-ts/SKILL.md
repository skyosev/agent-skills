---
name: party-hunter-ts
description: |
  Run all 10 TypeScript code quality hunters in parallel as subagents and write each report
  to a timestamped reports folder. Covers boundary, doc, invariant, security, simplicity,
  slop, smell, solid, test, and type hunters.

  Use when: running a full TypeScript codebase audit, scanning all quality dimensions at
  once, preparing for a code review, or generating a comprehensive findings report.
---

# Party Hunter — TypeScript

Orchestrate a full audit of a TypeScript codebase by running all 10 hunter skills as
independent subagents, each producing a focused report. Results land in a single
timestamped folder for easy review and sharing.

## Execution Protocol

### 1. Ask for scope

If the user has not specified a target (file, module path, or directory), ask before
proceeding. Do not guess — the hunters need a concrete scope to be useful.

### 2. Create the reports folder

```
reports/party-hunter-ts/YYYY-MM-DDTHHMM/
```

Use the current timestamp. Create the folder before launching any subagents.

### 3. Launch all hunters as subagents

Run **all 10 subagents in parallel**. Pass the same target scope to each. Each subagent
must load its hunter skill and return findings as a Markdown report.

| Hunter       | Skill to load           | Output file       |
|--------------|-------------------------|-------------------|
| Boundary     | `boundary-hunter-ts`    | `boundary.md`     |
| Doc          | `doc-hunter-ts`         | `doc.md`          |
| Invariant    | `invariant-hunter-ts`   | `invariant.md`    |
| Security     | `security-hunter-ts`    | `security.md`     |
| Simplicity   | `simplicity-hunter-ts`  | `simplicity.md`   |
| Slop         | `slop-hunter-ts`        | `slop.md`         |
| Smell        | `smell-hunter-ts`       | `smell.md`        |
| SOLID        | `solid-hunter-ts`       | `solid.md`        |
| Test         | `test-hunter-ts`        | `test.md`         |
| Type         | `type-hunter-ts`        | `type.md`         |

**Subagent prompt template** (adapt per hunter):

```
Load and apply the {skill-name} skill to the TypeScript code at {target_scope}.
Produce a structured Markdown report with:
- An executive summary (2-3 sentences)
- Findings grouped by severity (Critical / High / Medium / Low)
- For each finding: location, description, and a concrete fix suggestion
Return only the Markdown report — no commentary outside the report.
```

### 4. Write report files

As each subagent completes, write its output to the corresponding file inside the
reports folder. Do not wait for all subagents before writing — write as results arrive.

### 5. Write summary

After all 10 subagents have finished, write `summary.md` to the same folder:

```markdown
# Party Hunter Report — TypeScript
**Target**: {target_scope}
**Date**: {timestamp}

## Hunter Results

| Hunter     | Critical | High | Medium | Low | Total |
|------------|----------|------|--------|-----|-------|
| Boundary   | …        | …    | …      | …   | …     |
| …          |          |      |        |     |       |

## Cross-cutting Themes
{2-4 recurring patterns observed across multiple hunters}

## Top 5 Priority Issues
{Ranked list of the most impactful findings regardless of hunter}
```

## Output Contract

Every report file must be valid Markdown. Finding counts in `summary.md` must match
the findings in individual reports. If a hunter finds nothing, write a one-line note
(`No findings.`) rather than an empty file.
