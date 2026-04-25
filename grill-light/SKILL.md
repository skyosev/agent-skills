---
name: grill-light
description: Clarify the user’s intent for vague, incomplete, or ambiguous clauses, statements, and requirements before modifying the code.
disable-model-invocation: true
---

# Brainstorm

Help turn unclear or vague ideas into fully formed execution plan through natural collaborative dialogue.

Start by understanding the current project context, then ask questions to refine the idea. 
Weak assumptions and underestimated risks are unacceptable—call them out or resolve them.

The goal of this session is a direct implementation plan that can be executed with minimal further clarification.

## Workflow

### 1 Parse the user intent

Extract:

- Primary user goal (what "success" looks like)
- Inputs/outputs
- Ambiguous terms and implied constraints
- Hidden subproblems or coupled concerns

### 2 Decide whether this is one task or multiple tasks

Assess if the request mixes multiple high-level concepts. If yes, propose usint the `grill-hard` skill to produce details
specification artefact. If the user insists on a single task, identify the main theme and defer other themes as "future work" or "out of scope" with clear rationale.

### 3 Challenge and validate ideas or proposals

- Does the potential solution solve the right problem, for the right user?
- Are terms unambiguous (add glossary if needed)?
- Are there contradictions or missing states (edge cases, error states)?
- Is the request actually a prerequisite problem (e.g., missing abstraction, missing data model)?
- Are constraints real or assumed? Flag weak assumptions explicitly.
- Are the proposed features or requirements justified by user value, or are they "nice to have" features that should be deferred?

### 4 Ground in codebase reality

- Identify the existing types, interfaces, and modules that the feature touches.
- Reference concrete method signatures and data structures—not vague module names.
- Note architectural constraints (layer boundaries, dependency direction) that shape what is achievable.
- Surface risks: missing abstractions, type gaps, invariants that may break.

### 5 Ask targeted questions

- Use AskUserQuestion tool to ask the smallest set of questions that materially affects behavior, scope boundaries, acceptance criteria, or feasibility
- Prefer multiple choice questions when possible, but open-ended is fine too
- Present options conversationally with your recommendation and rationale

## Principles

- **Be blunt**: explicitly state what is unclear or inconsistent.
- **Assume nothing**: if a term has multiple interpretations, define it or ask.
- **No weak assumptions**: if something "should probably work", verify it or flag it as a risk. Underestimated risks
  poison downstream plans.
- **YAGNI ruthlessly**: Remove unnecessary features from all designs
- **Focus**: Keep the conversation and artifacts anchored to the chosen initial theme. Do not expand scope or
  switch to adjacent concepts unless they are required to clarify, make feasible, or verify the proposed ideas.

After the interview, present the synthesized requirements to the user for implementation approval.
