# Blocks

Trimmed from html-plan's `references/blocks.md` (anthropics/claude-plugins-community, commit 163301d, Apache-2.0, see `../runtime/LICENSE`). It keeps only the blocks that pr-explain uses.

Two kinds of content:

- **Source text** (a `doc-flow`, or a `doc-code` with pasted lines) goes in `<script type="text/plain">…</script>` as the block's first child. Inside it `<`, `>` and generics are safe. Without it the first stray `<` cuts the block short, and pack reports an error.
- **HTML** (a `doc-quote`, a `doc-note`) goes directly inside the block. A `<script>` there hides the text, and pack does not warn.

One convention runs through the line-based blocks: start a line with **`+`** for added, **`-`** for removed, **`~`** for changed.

Everything the reader can see is a comment target: code lines, arrows, `data-ref` elements in mockups, quotes, notes, list items. You write nothing for that.

## `doc-shot` and `doc-mock` — a picture, scaled to fit

```html
<doc-shot src="shot-head.png" caption="After, at 1b9d235: one entry per reason."></doc-shot>

<doc-mock frame="none" w="420" caption="Before. Drawn from the code at f0e5ba1; not a screenshot."><template>
<div class="ui">
  <div class="ft"><span class="btn pri">Send</span><span class="btn" data-ref="later">Send later ▾</span></div>
</div></template>
  <doc-pin ref="later" title="New button">Send is unchanged.</doc-pin>
</doc-mock>
```

- `doc-shot src="x.png"` shows a screenshot. Pack inlines the image.
- `doc-mock` is real HTML in a frame. `frame="none|browser|phone|desktop|terminal"`. `w` is the width you design at. The mock renders at that width in a shadow root and scales down to the column. `h` clips the height. `url` and `title` fill the chrome. `label` sits above, `caption` below.
- **Draw the smallest region that makes the point**: one card, one menu, one row, at `w` ≤ 480 with `frame="none"`. It then stays readable on a phone.
- Write real markup with inline styles or a `<style>` in the template. Several mocks of one app share CSS through one page-level `<style data-mock-shared>…</style>`.
- The terminal frame is a dark mono surface with helpers: `<b>`, `.dim .g .r .y .b .m .o .inv .box`. Keep it to `w` ≤ 480, about 55 columns.
- `data-ref="name"` makes an element a comment target. `<doc-pin ref="name" title="…">` puts a numbered pin on its corner (`anchor="tr|tl|br|bl|r|l|c"`, `offset="dx,dy"`). `at="x%,y%"` places a pin with no element. A pin is a description only: the reader taps the number and reads the title and one sentence. Give two pins on neighbours different anchors.
- **A behaviour whose output is text** (a CLI, a log, a generated file) is a `frame="terminal"` mock, or a `doc-code` of the output.

## `doc-code` — a slice of code, with pins

```html
<doc-code src="server/src/mail/send.ts" lines="20-34" ref="<full sha>" hl="27">
  <doc-pin line="27" tone="warn" title="Throws on a refused address">The worker must catch this.</doc-pin>
</doc-code>

<doc-code src="hunks/send.diff" lines="12-30" diff lang="ts" file="server/src/mail/send.ts"></doc-code>
```

- **Code at a commit:** `src` + `lines="a-b"` (`lines="40"` is one line) + `ref="<sha>"`. Pack reads the file from git under `--root`.
- **A hunk:** `src` points at a patch file from `git diff`, `lines` is the hunk's range in that file, `diff` marks it as a diff, `lang` (the file extension) turns on syntax colours, and `file="path"` names the source file. The `@@ -a,b +c,d @@` header numbers the gutter. One file per block. Never cut lines out of the middle of a hunk.
- `doc-pin line="N"` uses the number shown in the gutter (`old="N"` for a removed line). `tone="info|warn|risk|ok"`. A pin says what the line is, in a clause.
- 10 to 25 lines. A hunk over 25 lines: cite it whole and add `collapsed`. `hl="4-5,9"` highlights. `wrap` soft-wraps long lines. `caption` adds a line under the header. `collapsed` starts it closed.

## `doc-quote` — who asked, in their words

```html
<details class="thread"><summary>Why · LAY-1141</summary>
  <doc-quote via="linear" from="dana" at="2026-03-02" href="https://…">…</doc-quote>
</details>
```

`via` names where the words come from: `linear`, `github`, `slack`, `doc`, `email`, `meeting`. `from` is a bare name or handle. `where` names the place: a file and its section, a channel, a meeting. Quote, do not paraphrase. Trim with `…`.

## `doc-note`

`<doc-note tone="info|warn|risk|ok|idea"><strong>Risk</strong> One or two sentences.</doc-note>`. Use it under an exhibit for a risk the reader must weigh.

## `doc-flow` — parts and how they connect

```html
<doc-flow marks="new,removed,changed" caption="Tap a box to go to its step.">
<script type="text/plain">
api  = API / routes.ts
db   = scheduled_messages [db]
+ wk = Worker / worker.ts [#step-2]
group "Server": api, wk
| api | db |
| .   | wk |
api -> db : insert
wk -> db : claim
</script>
</doc-flow>
```

- `id = Title / subtitle`. `[db]` sets a shape; `[#id]` links the box to an element on the page. An indented line under a box adds detail.
- `+`, `-` and `~` mark a box or an arrow as new, removed or changed. `marks` sets the three legend words.
- `group "Name": a, b` draws a frame around boxes.
- The `| a | b |` rows place the boxes, like ASCII art; `.` is an empty cell. Keep to 12 boxes or fewer, in 2 or 3 columns.
- `a -> b : label` is an arrow. Keep labels to two or three words.

### A flowchart: a decision path, with a note on each box

```html
<doc-flow marks="new,removed,changed" dashed="refused" caption="Each dropped file, at 1b9d235. Tap a box for its note.">
<script type="text/plain">
in = A dropped file [pill]
ty = Allowed type? [diamond]
~ sz = Total ≤ 25 MB? [diamond]
  Before: checked after the count.
ok = Queued [pill green]
rt = Refused: type [red]
rs = Refused: size [red]
| in | .  |
| ty | rt |
| sz | rs |
| ok | .  |
in -> ty
ty --> rt : no
ty -> sz : yes
sz --> rs : no
sz -> ok : yes
</script>
</doc-flow>
```

- A decision is a `[diamond]` with a short question. Each arrow out of it has a label: `yes`, `no`, or the value.
- The start and the end are `[pill]`. `[green]` colours the good end, `[red]` a refusal or an error. Shapes: `box pill diamond db circle note hex actor`. Tones: `accent green amber red blue purple muted ink`.
- `-->` is a dashed arrow. `dashed="…"` names it in the legend.
- The indented line is the note. The box shows "…", and the reader taps it to read the note. On a `~` box, the note says what was true at BASE.
- Put the main path in one column, from top to bottom, and the refusals in the column to its right.

For a few cards side by side, use `<div class="cols"><div class="card"><h4>Before</h4><p>…</p></div>…</div>`.

## pack.mjs

```
node runtime/pack.mjs page.html [--root <repo>]… [-o out.html] [--lint-only] [--artifact] [--quiet]
```

- Lints every block with the same parsers the browser uses.
- Fills `src=` blocks from `--root` (or from git with `ref=`). With several `--root`s it looks in each in order, then beside the page. It reads nothing outside those folders, refuses files that look like they hold a secret, and ends by listing every file whose code is now inside the page. Check that list before you publish or share.
- Inlines the runtime and local images. Writes `page.packed.html`.
- `--artifact` also writes `page.artifact.html`, the page without its own `<html>` and `<body>`, for a host that adds them.
- Errors stop the write. Warnings are budgets for words and phone width.
