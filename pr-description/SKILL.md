---
name: pr-description
description: Rewrite a PR description so it is focused, easy to scan, and free of abstract or vague statements. Opens with a TL;DR: a general problem (cause, then what the user sees) and solution, then one Before / After example.
disable-model-invocation: true
---

# PR Description

Rewrite the description of the PR named in the arguments. With no argument, use the current branch's PR (`gh pr view --json title,body`). If the PR has no description yet, write one from the diff and the commits.

## Reader

Write for a reader who has not read the ticket, the spec, the brainstorm, or this conversation.

- Do not reuse ticket titles or spec phrases as if the reader knows them. Say what they mean.
- Define a term the first time it appears, or replace it with plain words. When a PR needs more than two new terms, add a short **Terms** section after the TL;DR.
- Use one term for one thing, everywhere. Do not switch between synonyms: pick "working hours" or "working time", and never use both for the same thing.

## Rules

1. **State every problem as an observable outcome.** Say what the user sees, where they see it, what they expected, and what they got. Use real values: times, names, amounts, claim or fixture names.
   - Bad: "An exclusion row reports a period that its own rule does not define."
   - Good: "The holiday row ends at Sat 10:43, the next SOF event. The holiday ends at Sat 08:00."
2. **No abstract nouns without a referent.** "Rule", "period", "behaviour", "semantics", "logic", "handles", "defines", "edge case": for each one, say which one it is and what it does.
3. **No figurative language.** Replace a metaphor with the literal claim it stands for.
4. **ASD-STE100 where it fits.** Active voice, one idea per sentence, sentences under 25 words.
5. **Zinsser.** Simplicity, brevity, clarity, humanity. Cut every sentence that does not change what the reader knows or does.
6. **Structure over prose.** When the content is structural, use a nested list, a table, or a small `diff` block instead of a paragraph. Lead each section with its answer.
7. **Keep the repo's conventions.** Keep the title format and the required sections (for example, laytime-agent needs a `[LAY-NNN]` title, a `## Why` section, and a section stating that no calculated value changed). Keep every fact from the old description unless it is wrong.

Ideas from `/show-me`, `/i-have-adhd` and `/wait-what` are welcome where they make a point clearer or shorter.

## TL;DR

Put it first, before everything else:

1. **Problem:** a short, general statement in one or two sentences: the cause in plain words, then what the user sees because of it. Not a single case.
   - Good: "The hub checked CP clauses against its own list, not the calculator's, so it dropped clauses about 12 stoppages the calculator knows."
2. **Solution:** a short, general statement of what changes, in one or two sentences. Put technical detail in the sections below it.
3. **Example:** one concrete case with real values, as Before / After (a list or a before/after `diff` of what the user sees).

The Problem and Solution alone must tell the reader the purpose of the PR; the Example only makes it concrete.

## Vagueness check

Before you finish, read the draft as the reader above. List each sentence that the reader could not picture or act on, and rewrite it. Check these first:

- every sentence in the TL;DR and the Why section;
- every sentence that paraphrases a ticket or spec;
- every sentence with a word from Rule 2.

## Output

1. Write the draft to a file in the scratchpad.
2. Show the user:
   - the vagueness list, one line per sentence (**before → after**);
   - any fact you corrected or could not verify;
   - the path to the draft.
3. Update the PR (`gh pr edit <n> --body-file <draft>`) only when the user says so. Do not change the title unless the user asks.
