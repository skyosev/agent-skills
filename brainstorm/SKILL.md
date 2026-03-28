---
name: brainstorm
description: Transform vague, ambiguous, or incomplete requests into precise, codebase-grounded technical descriptions. Explore user intent, requirements, and design before modifying the code.
---

# Brainstorm

Help turn unclear or vague ideas into fully formed designs and specs through natural collaborative dialogue.

Start by understanding the current project context, then ask questions to refine the idea. Once you understand what you're building, present the design and get user approval.
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it.

The output is a **brainstorm session document**, not an implementation plan. However, details must be concrete enough to avoid ambiguity. 
Weak assumptions and underestimated risks are unacceptable—call them out or resolve them.

## What belongs in problem description vs. implementation plan
 
| Problem Description (this skill)                            | Implementation plan (separate step)            |
| ----------------------------------------------------------- | ---------------------------------------------- |
| _What_ the system must do and _why_                         | _How_ to build it (file changes, task order)   |
| References to existing types, interfaces, method signatures | Actual code diffs and new file scaffolds       |
| Pseudo-code or data-flow sketches clarifying behavior       | Step-by-step implementation instructions       |
| Constraints, invariants, edge cases                         | Detailed test plans with exact assertions      |
| High-level acceptance criteria                              | CI commands, deployment steps                  |

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

Rules:

- Prefer the smallest slice that provides user-visible or measurable value.
- Do not "boil the ocean".

### 3 Challenge and validate ideas or proposals

- Does the potential solution solve the right problem, for the right user?
- Are terms unambiguous (add glossary if needed)?
- Are there contradictions or missing states (edge cases, error states)?
- Is the request actually a prerequisite problem (e.g., missing abstraction, missing data model)?
- Are constraints real or assumed? Flag weak assumptions explicitly.

### 4 Ground in codebase reality

- Identify the existing types, interfaces, and modules that the feature touches.
- Reference concrete method signatures and data structures—not vague module names.
- Note architectural constraints (layer boundaries, dependency direction) that shape what is achievable.
- Surface risks: missing abstractions, type gaps, invariants that may break.

### 5 Ask targeted questions

- Use AskUserQuestion tool to ask the smallest set of questions that materially affects behavior, scope boundaries, acceptance criteria, or feasibility
- Prefer multiple choice questions when possible, but open-ended is fine too
- Present options conversationally with your recommendation and reasoning

### 6 Synthesize artifact

Produce `docs/brainstorm/{Y-m-d-session-name}.md` — containing the result of the brainstorming session.
This document serves as the **input** for a future precise requirements or implementation plan.

## Principles

- **Be blunt**: explicitly state what is unclear or inconsistent.
- **Assume nothing**: if a term has multiple interpretations, define it or ask.
- **No weak assumptions**: if something "should probably work", verify it or flag it as a risk. Underestimated risks
  poison downstream plans.
- **YAGNI ruthlessly**: Remove unnecessary features from all designs
- **Focus**: Keep the conversation and artifacts anchored to the chosen initial theme. Do not expand scope or
  switch to adjacent concepts unless they are required to clarify, make feasible, or verify the proposed ideas.

## Output Template (you might change or expand this as needed)

### {Y-m-d-session-name}.md

```md
# [Feature Name]

## Session Summary

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

### Open Questions

- Q1: ...
- Q2: ...
```

**IMPORTANT** ensure that the artifact you produced is present in the correct directory. No need to display it in the
output.
