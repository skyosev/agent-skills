---
name: sum-up
description: Sum up a long ticket, spec, PR or discussion thread in a few lines that state its purpose, so a reader who never opens it can predict what it decides. Use when the user says "sum up", "sum-up", "in a few lines", "what does this ticket actually decide", "TL;DR of <ticket>", or points at an issue, doc or thread that has grown to hundreds of lines of cause analysis, side effects, replays and rulings. Use it even when the user only pastes a ticket link and asks what it is about.
---

# Sum-up

A long ticket collects everything: cause, provenance, history, side effects, replays, rulings. A reader who wants to know what it decides has to dig. A sum-up gives them the decision in a few lines, and nothing else.

## An example

This sum-up, by the product owner, closed a ~150-line chartering ticket with five comment threads:

> To sum up - we always prefer the Layer (recap > proforma) for values even when the recap's value might be on a "broader" scope:
>
> * Voyage `currency` on a *Recap* > a Port `currency` on a *Proforma*
>
> And also, when everything else is the same (Layer and Scope), the tie-breaker is:
>
> * which portcall happened first

It is one good sum-up, not a template. Copy what makes it work, not its wording or its length:

- **One general rule first**, in the team's own words (Layer, Scope, recap, proforma). A reader can apply it to a case the ticket never lists.
- **The surprise is attached to the rule.** "even when the recap's value might be on a broader scope" names the one place a reader would guess wrong. The rest of the rule needs no comment.
- **One instance, in compact `A > B` form.** It shows the surprise with real field names, not an abstract restatement.
- **The secondary rule carries its condition.** "when everything else is the same (Layer and Scope)" tells the reader when the tie-breaker applies, and so implies the order of the criteria.
- **Nothing else.** No cause, no history, no evidence, no file paths, no ticket links, no counts.

## Steps

### 1. Read everything, the latest ruling last

Fetch the description and every comment with its thread, oldest first (for Linear: `get_issue`, then `list_comments` with `orderBy: createdAt`). A ruling in a comment overrides the description. A reply such as "Agreed" makes the comment it answers binding. If someone has already posted a sum-up, check it (step 4) rather than write a second one, unless the user asks for a new one.

### 2. Find the decision

Ask: after this ticket ships, what does the system (or the team) do differently, and by what rule? The purpose of a ticket is that rule, not the bug report that opened it. A bug ticket's purpose is the correct behaviour, stated generally. It is not the one case that showed the bug.

Tickets come in two common kinds:
- **A rule ticket** decides how the system chooses between things (which value wins, when a claim stops). Its sum-up is the rule: the main criterion, the case where it surprises, and what decides when it does not (tie-breaker, fallback, limit). The example above is one.
- **A feature ticket** makes the system keep, show or do something new. Its sum-up says what the system now does and why, in one sentence, then only the parts a builder would get wrong. Acceptance criteria that follow from that sentence stay in the ticket.

Do not invent a part to fill a shape. A ticket with no surprise has no surprise line.

### 3. Write it

- Lead with the general statement, in one sentence.
- Name the surprise, if there is one, where it belongs. Use "even when" only when the sentence reads naturally with it.
- Give an instance only when it shows the surprise, as a bullet in `A > B` or `A → B` form with the real field and document names. An instance of the obvious part adds nothing.
- Add the secondary rule with its condition ("when X and Y are the same, ...").
- Use the words the team uses in the ticket and its comments. A reader will search for them.
- Give each concept one name and keep it. "Written first in the document", "position" and "document order" for one idea make the reader wonder whether they are three ideas. Define the name once, in parentheses, where it first appears.
- Write a change as a change. "The LLM writes both facts" reads as today's behaviour; "The LLM now writes both facts" says it is new.
- Make it as short as the decision allows, and no shorter. There is no word limit, but every line must tell the reader something they cannot derive from the other lines. When it grows, check whether a line restates another, describes evidence or history, or lists a case the general sentence already decides.
- Do not wrap it in Problem / Solution / Example sections. The sum-up is already the short form.
- Do not repeat yourself in other words. Before you hand it over, read each sentence and ask whether an earlier sentence, or a term already used, says or implies it. If so, cut it. Typical repeats:
  - a sentence that restates the rule just stated ("Only position counts" after "the pick is the fact written first");
  - a sentence that brings back the rule under a new name ("Document order is the default" after the rule itself); keep only what it adds ("for every field");
  - a clause that spells out what a term already means ("until the user picks" after "provisional pick").

Strunk's rules that matter most here: positive form ("prefer the recap", not "do not prefer the pro-forma"), definite and concrete words (`currency`, not "values of this kind"), similar form for similar clauses, and the emphatic word at the end of the sentence.

### 4. Test it against the ticket

A sum-up is right when a reader can use it to predict outcomes. Take every concrete case the ticket lists (acceptance criteria, side effects, examples, rulings) and apply only your sum-up to it.

- If the sum-up predicts the ticket's outcome, it holds.
- If it predicts a different outcome, the sum-up misses a clause, or the ticket contradicts itself. Add the clause if the ticket's latest ruling supports it. If the ticket contradicts itself, say so to the user, quote both lines, and do not choose.
- A case the sum-up cannot decide at all is fine when it is out of the ticket's scope. Otherwise, add the missing clause.

### 5. Hand it over

Show the user:
1. The sum-up, ready to paste.
2. The cases you checked in step 4, one line each: case → predicted outcome = ticket's outcome. List each disagreement first.

Post it to the tracker only when the user asks. In Linear text, write each issue reference as `[ABC-123](<https://linear.app/<workspace>/issue/ABC-123>)`. A bare `ABC-123` or a slugged URL renders as a chip that shows the full title.
