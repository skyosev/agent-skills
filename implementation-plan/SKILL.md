---
name: implementation-plan
description: Turn a spec into a plan of as few task files as the work allows, under docs/process/specs; a fresh sub-agent then reviews it and enriches it with seams, test outlines and critical code. Reports omit empty sections — no placeholder headings, empty tables, or negative statements like "no issues found".
argument-hint: "<spec path> [instructions]"
disable-model-invocation: true
---

# Implementation Plan

Arguments: `$ARGUMENTS`. The request names the spec and may add instructions; an instruction in the request outranks this skill. When it names no spec, ask for one and suggest the newest file under `docs/process/specs/` and `docs/process/brainstorm/`.

Write the plan for an engineer who has seen neither this codebase nor the spec. They write idiomatic code in the project's language once they know the exact interface and the exact test, and they make a reasonable choice wherever the plan leaves one open. What they cannot know is what you decided: which files, which names and signatures, which values from the spec, which tests prove each task. The plan records those decisions. DRY. YAGNI. TDD.

## 1. Read

- The spec in full, and the documents it links that bear on the work (a handoff, an earlier plan).
- The code the spec touches, in every repository it touches: the types and signatures, the tests and their conventions, the lint limits, the test command.
- The current commit of each repository. Line numbers in the plan refer to it.

Reading is done when you can name, for each requirement of the spec, the file and symbol it changes. When the spec covers independent subsystems that each ship value alone, say so and suggest one plan per subsystem before you write anything.

## 2. Where the plan goes

- **Folder:** `docs/process/specs/<Y-m-d>-<name>/`: today's date, then kebab-case words that say what the plan delivers, in the style of the folders already there (a ticket id first, when the spec has one). A spec that already lives in `docs/process/specs/` and is named for what it delivers lends the folder its own name. When `docs/process/` does not exist, ask once where to write.
- **Task files:** `NN.<what-the-task-delivers>.md` — a two-digit number, a dot, then kebab-case words that say what the task delivers, e.g. `01.hub-cp-extract-takes-page-ranges.md`.
- **Index:** with more than one task, `00.plan.md` holds the plan header and the list of tasks. With one task, the task file is the index: `01.<name>.md` holds the header, then the task as `## Task 1: …` without the "Part of the plan" line.
- **Backlog:** follow-up work that this plan defers, but that is worth doing or at least investigating later, goes into `docs/process/BACKLOG.md` (create it when missing) under `## From <plan title> (<Y-m-d>)`, one `###` item each: what, why it waits, and what would start it. The items live only there; the plan links to the section. An idea the plan rejects for good belongs in the reason of the decision that rejects it.

## 3. Write the plan

Before you draw task boundaries, map the files the plan creates or changes and what each one is responsible for. Each file has one responsibility; files that change together live together; split by responsibility, not by layer. In existing code, follow its patterns, and split a file only when the plan's change would make it unwieldy.

Write as few tasks as the work allows: each task costs its own implementer, review and hand-off. A task ends where a fresh reviewer could reject it while approving its neighbour — usually at a merge request, a repository, or a deliverable that ships alone. Work smaller than that merges into the task whose deliverable needs it: setup, configuration, scaffolding, documentation and every small change. One task for the whole plan is a valid result, and often the right one.

Inside a task, each step is one action with a checkable result: write the failing tests, run them and watch them fail, implement, run them and watch them pass, commit.

### Plan header

The index starts with:

```markdown
# [Feature Name] — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence. When the spec gives a concrete case: what happens today, and what happens after.]

**Architecture:** [2–3 sentences, or one line per task]

**Tech Stack:** [Key technologies, the test framework, the linter]

**Spec:** [Relative link to the spec.] Read it first.

## Global Constraints

[The spec's project-wide requirements — version floors, dependency limits, naming and copy rules, platform requirements — and the commit that each repository's line numbers refer to. One line each, exact values copied from the spec.]

## Plan Decisions

[What the spec leaves open and more than one task relies on: one line each, with its reason. A decision that only one task uses lives in that task.]

## Review Focus

[The five input classes or failure modes the spec implies but no task's tests exercise that are most likely to bite a person using this software — one line each, naming the input and the behavior a reasonable person expects, most likely first. The spec's silence on an input is not permission for that input to break the program. For each line, add the test that pins it to the task that owns the code, and name that task here.]

## Tasks

1. [`01.<name>.md`](01.<name>.md): what it delivers, in one line.

## After this plan

[Link to the plan's section in `BACKLOG.md`.]
```

Keep the index short: the header and a map of the tasks, with each task's detail in its own file.

### Task file

````markdown
# Task N: [What it delivers]

> Part of [the plan](00.plan.md). Its Global Constraints, Plan Decisions and Review Focus apply here.

**Files:**
- Create: `exact/path/to/file.go`
- Modify: `exact/path/to/existing.go:123-145` (`symbol`)
- Test: `exact/path/to/file_test.go`

**Interfaces:**
- Consumes: [what this task uses from earlier tasks — exact signatures]
- Produces: [what later tasks rely on — exact names, parameter and return types. An implementer sees only their own task; this block is how they learn what the neighbouring tasks use.]

- [ ] **Step 1: Write the failing tests in `exact/path/to/file_test.go`**

  [The behaviors the tests prove, one line each, with the spec's exact values.]

- [ ] **Step 2: Run them and watch them fail**

  Run: `go test ./internal/x -run TestY`
  Expected: FAIL, [the failure that shows the test reaches the missing behavior]

- [ ] **Step 3: Implement `Y(in In) (Out, error)` in `exact/path/to/file.go`**

- [ ] **Step 4: Run them and watch them pass**

  Run: `go test ./internal/x -run TestY`
  Expected: PASS

- [ ] **Step 5: Commit**
````

### What a step contains

A step is done when the implementer can write exactly one reasonable thing from it: **unambiguous**, not complete.

- **A test step:** the test file and the behaviors its tests prove, with the spec's exact values. Enrichment turns them into test names with given → expect.
- **A code step:** the exact signature, the file it lives in, and the values the spec pins. The body is the implementer's; enrichment adds the decisions the signature and tests leave open, and the critical code.
- **A verification step:** the command, and the output that means it passed.
- **A reference to another task:** that task's Interfaces block.

More than that is a **transcript** of the code; less is a **placeholder**.

## 4. Review and enrich

Dispatch one fresh sub-agent with this brief:

- the absolute path of the spec, of the plan folder and of each file in it, and of `BACKLOG.md`;
- the absolute path of each repository the plan touches;
- the absolute path of the `enriching-plans` SKILL.md, in the `enriching-plans` directory beside this skill's own;
- the absolute path of `references/review-and-enrich.md` in this skill's directory, with "Read it and follow it".

The brief holds paths only. The sub-agent works from the plan, the spec and the code alone, so its review doubles as a test that the plan stands alone: a decision the plan does not carry is one the sub-agent cannot use, and neither can the implementer.

When the sub-agent returns, read `## Questions for Reviewer` at the end of the index. Answer each question that the spec or the plan already settles: edit the plan, and add **Ruling:** with its reason under the question. Leave the others for the user.

## 5. Hand off

Tell the user, in a few lines: the plan folder, the tasks, the fixes the review made, the open Questions for Reviewer, and which execution skill you recommend, with one reason from the plan:

- `superpowers:subagent-driven-development`: a fresh implementer and a fresh reviewer for each task. Fits tasks that depend on each other's interfaces, or a costly mistake.
- `superpowers:executing-plans`: you implement every task, then one review of the whole branch. Fits one or two tightly scoped tasks.

End your turn there: implementation starts after the user reviews the plan.

## No empty sections

Include only sections with content: a heading, list or block that would hold nothing is left out. A plan without deferred work has no "After this plan" section and adds nothing to the backlog.
