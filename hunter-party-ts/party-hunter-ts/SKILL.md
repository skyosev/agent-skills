---
name: party-hunter-ts
description: |
  Run all 12 TypeScript code quality hunters in parallel as subagents and write each report
  to a timestamped reports folder. Covers boundary, doc, error, invariant, perf, security,
  simplicity, slop, smell, solid, test, and type hunters.

  Use when: running a full TypeScript codebase audit, scanning all quality dimensions at
  once, preparing for a code review, or generating a comprehensive findings report.
---

# Party Hunter — TypeScript

Orchestrate a full audit of a TypeScript codebase by running all 12 hunter skills as
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

Run **all 12 subagents in parallel**. Pass the same target scope to each. Each subagent
must load its hunter skill and write its report to the `./hunters` subfolder inside the
reports directory.

| Hunter       | Skill to load           | Output file            |
|--------------|-------------------------|------------------------|
| Boundary     | `boundary-hunter-ts`    | `hunters/boundary.md`  |
| Doc          | `doc-hunter-ts`         | `hunters/doc.md`       |
| Error        | `error-hunter-ts`       | `hunters/error.md`     |
| Invariant    | `invariant-hunter-ts`   | `hunters/invariant.md` |
| Perf         | `perf-hunter-ts`        | `hunters/perf.md`      |
| Security     | `security-hunter-ts`    | `hunters/security.md`  |
| Simplicity   | `simplicity-hunter-ts`  | `hunters/simplicity.md`|
| Slop         | `slop-hunter-ts`        | `hunters/slop.md`      |
| Smell        | `smell-hunter-ts`       | `hunters/smell.md`     |
| SOLID        | `solid-hunter-ts`       | `hunters/solid.md`     |
| Test         | `test-hunter-ts`        | `hunters/test.md`      |
| Type         | `type-hunter-ts`        | `hunters/type.md`      |

**Subagent prompt template** (adapt per hunter):

```
Load and apply the {skill-name} skill to the TypeScript code at {target_scope}.
Write your report to ./hunters/{hunter-name}.md in the reports folder.

Your report must include:
- An executive summary (2-3 sentences)
- Findings grouped by severity (Critical / High / Medium / Low)
- For each finding: location, description, and a concrete fix suggestion with code examples where applicable

Return only the Markdown report — no commentary outside the report.
```

### 4. Write report files

Each subagent writes its output directly to the `hunters/` subfolder. Do not wait for
all subagents before writing — write as results arrive.

### 5. Write summary

After all 12 subagents have finished, write `summary.md` to the reports folder root.
The summary must be **fully self-sufficient**: anyone reading it should be able to
implement all suggestions without consulting the individual hunter reports.

```markdown
# Party Hunter Report — TypeScript
**Target**: {target_scope}
**Date**: {timestamp}

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
- Include **only actionable items** — omit sections entirely if a category has no findings
- Do **not** write "No issues found" or similar empty statements
- Every finding must include: file location, issue description, and a concrete fix suggestion
- Fix suggestions must be specific enough to implement without consulting hunter reports
- Aggregate duplicate findings from multiple hunters into a single actionable item
