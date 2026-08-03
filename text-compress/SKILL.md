---
name: text-compress
description: |
  Use when an LLM-facing document — a prompt, skill file, spec, or instruction set — is verbose and
  must fit a tighter token budget. Not for user-facing copy, legal text, changelogs, or quoted
  material.
disable-model-invocation: true
---

# Text Compress

Remove words from LLM-facing text without removing meaning. Every instruction, constraint, number, and named entity in
the input must survive in the output.

## When NOT to use

- User-facing copy, human documentation, marketing text
- Contracts, licenses, compliance text
- Changelogs, commit messages, quoted excerpts — anything attributed to someone
- Text where exact wording is the point: error-message catalogues, test fixtures, translations

## Output contract

Produce exactly one of these:

1. **A target file is named** → rewrite it in place. Then report original word count → new word count, and every
   requirement you judged redundant and merged.
2. **Text is supplied inline, or no target is named** → return the compressed text alone. No preamble, no summary of
   what changed.

Never both. Never add content. Never reorder sections. Never drop a requirement — compression removes words, not rules.

## Never modify

Copy these through byte for byte:

- Fenced code blocks (``` ... ```) — including comments, blank lines, line order, and command length
- Inline code (`` `...` ``)
- URLs, links, file paths, environment variables
- Technical terms: library, API, protocol, algorithm, and product names
- Numbers, versions, thresholds, identifiers

Code blocks are read-only regions. Compress the prose around them; do not merge sections across them.

## Compress

- Delete filler: just, really, basically, actually, simply, essentially, generally
- Delete pleasantries: "sure", "certainly", "of course", "happy to", "I'd recommend"
- Delete connective fluff: however, furthermore, additionally, in addition
- Delete articles (a, an, the) where the referent stays unambiguous
- Drop "you should", "make sure to", "remember to" — state the action
- Short synonyms: "big" not "extensive", "use" not "utilize", "fix" not "implement a solution for"
- "in order to" → "to"; "the reason is because" → "because"
- Fragments are fine: "Run tests before commit"
- Merge bullets that state one rule twice; keep one example where several show one pattern
- Delete implied context and duplicate semantics across lines

## Compress with care

Two rules invert meaning when applied mechanically:

- **Hedges.** Drop hedging around an assertion: "it might be worth running the tests" → "run the tests". Keep the modal
  where it grants permission or marks a real option: "you may skip the lint step" stays.
- **Negatives.** Convert to affirmative only when the affirmative states the same requirement: "do not forget to lock"
  → "lock". Keep the negative for prohibitions: "never edit files in place" stays — an affirmative restatement weakens
  it.

## Verify before returning

Read the original and the compressed text side by side. Confirm every instruction, constraint, number, named entity,
and code region survived. Restore words wherever meaning thinned. Compression that loses a rule is a failed
compression, not a tighter one.

## Examples

**Prose**

Original:

> You should always make sure to run the test suite before pushing any changes to the main branch. This is important
> because it helps catch bugs early and prevents broken builds from being deployed to production.

Compressed:

> Run tests before pushing to main. Catches bugs early, prevents broken production deploys.

**Prose around code** — the surrounding text compresses, the block does not.

Original:

Before you get started, you'll want to make sure that you have installed all of the project dependencies. You can do
this by simply running the following command in your terminal:

```bash
# install everything, including dev dependencies
npm install --include=dev
```

If that fails, it might be worth checking your Node version first.

Compressed:

Install dependencies:

```bash
# install everything, including dev dependencies
npm install --include=dev
```

On failure, check Node version.
