---
name: refining-requirements
description: Transforms vague feature ideas into precise, codebase-grounded technical requirements. Use when requirements are ambiguous/incomplete, the user struggles to describe behavior, terminology is unclear, or multiple concepts are mixed. Output is a requirements spec—NOT an implementation plan.
disable-model-invocation: true
---

# Refining Requirements

Turn unclear or vague requests into precise, codebase-grounded, testable _thin-slice_ **technical requirements**.

The output is a **requirements document**, not an implementation plan. However, requirements must be concrete enough that
an implementor can derive an implementation plan from them without guessing. Weak assumptions and underestimated risks are
unacceptable—call them out or resolve them.

## What belongs in requirements vs. implementation plan

| Requirements (this skill)                                   | Implementation plan (separate step)            |
| ----------------------------------------------------------- | ---------------------------------------------- |
| _What_ the system must do and _why_                         | _How_ to build it (file changes, task order)   |
| References to existing types, interfaces, method signatures | Actual code diffs and new file scaffolds       |
| Pseudo-code or data-flow sketches clarifying behavior       | Step-by-step implementation instructions       |
| Constraints, invariants, edge cases                         | Detailed test plans with exact assertions      |
| Acceptance criteria (black-box, testable)                   | CI commands, deployment steps                  |

## Workflow

### 1 Parse the user intent

Extract:

- Primary user goal (what "success" looks like)
- Inputs/outputs
- Ambiguous terms and implied constraints
- Hidden subproblems or coupled concerns

### 2 Decide whether this is one task or multiple tasks

Assess if the request mixes multiple high-level concepts. If yes, split into units:

- **Independent units**: can be implemented and verified separately (prefer this split)
- **Sequential units**: require an earlier prerequisite slice

Outcome of this step MUST be:

- A named list of units
- A recommended ordering
- A chosen **thin slice** initial requirements: the _smallest useful_ unit that is testable end-to-end

Rules:

- Prefer the smallest slice that provides user-visible or measurable value.
- Do not "boil the ocean".
- Anything not required for the initial requirements goes to the "Next (Deferred)" section.

### 3 Challenge and validate the initial requirements

- Are the initial requirements solving the right problem, for the right user?
- Are terms unambiguous (add glossary if needed)?
- Are there contradictions or missing states (edge cases, error states)?
- Is the request actually a prerequisite problem (e.g., missing abstraction, missing data model)?
- Are constraints real or assumed? Flag weak assumptions explicitly.

### 4 Ground in codebase reality

- Identify the existing types, interfaces, and modules that the feature touches.
- Reference concrete method signatures and data structures—not vague module names.
- Note architectural constraints (layer boundaries, dependency direction) that shape what is achievable.
- Surface risks: missing abstractions, type gaps, invariants that may break.

### 5 Ask targeted questions (only those that unblock the initial requirements)

Use AskUserQuestion tool to ask the smallest set of questions that materially affects:

- behavior, scope boundaries, acceptance criteria, or feasibility

Do NOT ask questions that only affect deferred scope; put those in the "Next (Deferred)" section as "Open questions".

### 6 Synthesize artifact

Produce one artifact:

1. `docs/dev-specs/{Y-m-d-requirements-name}.md` — containing the technical requirements and optional deferred scope.
   This document serves as the **input** for a future implementation plan.

## Principles

- **Thin-slice first**: define the smallest end-to-end unit that can be tested unambiguously.
- **Separate "now" vs "later"**: requirements must not be polluted with follow-ups or nice-to-haves.
- **Be blunt**: explicitly state what is unclear or inconsistent.
- **Assume nothing**: if a term has multiple interpretations, define it or ask.
- **One default path**: present alternatives only when requirements truly differ.
- **Grounded, not vague**: every requirement must be traceable to existing code constructs or clearly mark what is new.
  Do not leave the implementor guessing which module, type, or interface is involved.
- **No weak assumptions**: if something "should probably work", verify it or flag it as a risk. Underestimated risks
  poison downstream plans.
- **Focus**: Keep the conversation and artifacts anchored to the chosen initial requirements. Do not expand scope or
  switch to adjacent concepts unless they are required to clarify, make feasible, or verify the initial requirements.
  Capture tangents as deferred items in the "Next (Deferred)" section and return to the initial requirements.

## Output Template

### {Y-m-d-requirements-name}.md

```md
# [Feature Name]

## Requirements

### Problem Statement

- ...

### Glossary

- ...

### Expected Behavior

Describe behavior as observable outcomes.

- Primary flow:
- Alternate flows:
- Error/invalid states:

### Scope

...

#### Includes

- ...

### Integration Points & Constraints

Relevant types and interfaces, affected modules and their boundaries, architectural constraints, a brief data-flow sketch or 
pseudo-code if it clarifies behavior, and any risks or unknowns.

- ...

### Acceptance Criteria

Write as testable conditions (black-box where possible).

- AC1: ...
- AC2: ...

#### Excludes (deferred) `optional`

- ...

### Open Questions

- Q1: ...
- Q2: ...
```

**IMPORTANT** ensure that the artifact you produced is present in the correct directory. No need to display it in the
output.
