# Review and enrich an implementation plan

You review a lean implementation plan against its spec and fix it, then enrich every task. Your brief gives the paths of the spec, the plan folder and each plan file in it, `BACKLOG.md`, each repository the plan touches, and the `enriching-plans` SKILL.md. That skill is user-invoked only, so the Skill tool cannot load it: read the file.

The plan's **index** is `00.plan.md`; a one-task plan has no `00.plan.md`, and its task file is the index.

Read the spec, every plan file, and the code the plan touches before you change anything.

## 1. Review

Run this checklist with the spec open, and fix what you find in place; there is no second review.

1. **Spec coverage:** each requirement in the spec maps to a task. Add a task for a gap.
2. **Placeholders:** scan for lines that decide nothing — "TBD", "handle edge cases", "add appropriate validation", "write tests for the above", a type no task defines — and replace each with the decision it stands for.
3. **Transcripts:** a plan several times longer than its spec holds code. Replace bodies with signatures, test names and assertions.
4. **Type consistency:** names, signatures and fields match across tasks. `clearLayers()` in Task 3 and `clearFullLayers()` in Task 7 is a bug.
5. **Review Focus:** each line of the index's Review Focus has its test in the task it names.
6. **Task count:** a task too small for a reviewer to judge on its own merges into the task it serves. When you merge, renumber the files and update the index.
7. **Backlog:** every follow-up the plan defers, and every "later" in it, has its item in the plan's section of `BACKLOG.md`, in the form of the items already there.

The review is done when every item holds for every task.

## 2. Enrich

Apply the `enriching-plans` rules to every task. The plan you reviewed is now fixed: from here its paths, names, task boundaries and step order stand, as that skill says. Layout for a plan of several files:

- Edit each plan file in place.
- `## Enrichment Decisions` goes at the end of the task file it concerns.
- `## Questions for Reviewer` goes at the end of the index, and each item names its task.
- Add each section only when it has content.

## 3. Report

Return the fixes the review made, one line each, and the number of Questions for Reviewer you left.
