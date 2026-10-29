"""Keep the eleven code-hunter skills consistent.

    python3 code-hunter/check.py                         # report drift and lint problems; exit 1 if any
    python3 code-hunter/check.py --sync-from smell-hunter

Each hunter must stay self-contained (it is installed alone), so shared text is copied, not linked. To change a
shared block, edit it in one hunter and run --sync-from that hunter. That copies every SHARED block to the other
hunters and refreshes each reference's Contents line, then runs the checks.
"""
import argparse, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent
HUNTERS = sorted(d.name for d in ROOT.glob("*-hunter"))
NOT_SLOP = [h for h in HUNTERS if h != "slop-hunter"]  # slop's step 1 differs on purpose: diff is its default scope
COMMENT_RULE = ["doc-hunter", "slop-hunter", "smell-hunter"]

# (file, first-line prefix, end-line prefix or None for "next blank line", hunters)
SHARED = [
    ("references/diff-scope.md", None, None, HUNTERS),
    ("SKILL.md", "1. **Resolve the raw manifest.**", "2. **Detect languages**", NOT_SLOP),
    ("SKILL.md", "**Party mode:**", None, HUNTERS),
    ("SKILL.md", "**Record provenance.**", None, NOT_SLOP),
    ("SKILL.md", "**Persist run state.**", None, HUNTERS),
    ("SKILL.md", "The raw manifest is **immutable**", None, HUNTERS),
    ("SKILL.md", "**Whitespace in paths is unsupported.**", None, HUNTERS),
    ("SKILL.md", "2. **Detect languages**", None, HUNTERS),  # the extension list; the next paragraph is per hunter
    ("SKILL.md", "Write each subset to `<run>/<lang>.txt`", None, NOT_SLOP),
    ("SKILL.md", "Hunter names are unsuffixed.", None, HUNTERS),
    ("references/report-format.md", "The report is, in order:", None, HUNTERS),
    ("SKILL.md", "- Comment contradicts the code it describes", None, COMMENT_RULE),
    ("SKILL.md", "*Trivial* code is one statement", None, COMMENT_RULE),
]

# Definitions copied from their owner, mid-paragraph or with different wrapping, so compared as normalized text:
# check only, never synced. (owner, start text, end text, hunters holding a copy)
COPIED = [
    ("boundary-hunter", "**Any evidence of documented import use opens the set**",
     "No release workflows or tags are read.", ["invariant-hunter", "simplicity-hunter", "type-hunter"]),
    ("test-hunter", "**Critical code**", "Generated code is never critical.", ["doc-hunter"]),
]

problems = []


def span(lines, start, end):
    """Line range of one shared block, or None. Errors unless the start prefix occurs exactly once."""
    hits = [i for i, l in enumerate(lines) if l.lstrip().startswith(start)]
    if len(hits) != 1:
        return None
    i = j = hits[0]
    if end is None:
        while j < len(lines) and lines[j].strip():
            j += 1
    else:
        j += 1
        while j < len(lines) and not lines[j].lstrip().startswith(end):
            j += 1
    return i, j


def block(hunter, file, start, end):
    path = ROOT / hunter / file
    if not path.exists():
        problems.append(f"{hunter}/{file}: missing")
        return None, None
    lines = path.read_text().split("\n")
    if start is None:
        return lines, (0, len(lines))
    r = span(lines, start, end)
    if r is None:
        problems.append(f"{hunter}/{file}: shared block '{start}' not found exactly once")
    return lines, r


def sync(source):
    for file, start, end, hunters in SHARED:
        if source not in hunters:
            continue
        src_lines, r = block(source, file, start, end)
        if r is None:
            continue
        text = src_lines[r[0]:r[1]]
        for h in hunters:
            lines, t = block(h, file, start, end)
            if t is not None and lines[t[0]:t[1]] != text:
                lines[t[0]:t[1]] = text
                (ROOT / h / file).write_text("\n".join(lines))
                print(f"synced {h}/{file}: {start or 'whole file'}")


def h2s(lines):
    fenced, out = False, []
    for line in lines:
        if line.startswith("```"):
            fenced = not fenced
        elif not fenced and line.startswith("## "):
            out.append(line[3:].strip())
    return out


def toc(text):
    """Expected Contents line for a reference, or None when it needs none (≤100 lines or <3 sections)."""
    body = re.sub(r"^Contents: .*\n\n", "", text, count=1, flags=re.M)
    lines = body.splitlines()
    heads = h2s(lines)
    if len(lines) <= 100 or len(heads) < 3 or not lines[0].startswith("# "):
        return None
    return "Contents: " + " · ".join(heads)


def refresh_tocs():
    for f in sorted(ROOT.glob("*/references/*.md")):
        text = f.read_text()
        want = toc(text)
        body = re.sub(r"^Contents: .*\n\n", "", text, count=1, flags=re.M)
        h1, rest = body.split("\n", 1)
        new = f"{h1}\n\n{want}\n{rest}" if want else body
        if new != text:
            f.write_text(new)
            print(f"refreshed Contents: {f.relative_to(ROOT)}")


def norm(s):
    return " ".join(s.split()).lower()


def check():
    for file, start, end, hunters in SHARED:
        variants = {}
        for h in hunters:
            lines, r = block(h, file, start, end)
            if r is not None:
                variants.setdefault("\n".join(lines[r[0]:r[1]]), []).append(h)
        if len(variants) > 1:
            groups = " | ".join(", ".join(v) for v in variants.values())
            problems.append(f"shared block '{start or file}' differs: {groups}")

    for owner, start, end, copies in COPIED:
        t = norm((ROOT / owner / "SKILL.md").read_text())
        m = re.search(re.escape(norm(start)) + ".*?" + re.escape(norm(end)), t)
        if not m:
            problems.append(f"{owner}: copied definition '{start}' not found")
            continue
        for h in copies:
            if m.group(0) not in norm((ROOT / h / "SKILL.md").read_text()):
                problems.append(f"{h}: copy of {owner}'s '{start}' differs")

    for h in HUNTERS:
        d = ROOT / h
        skill = (d / "SKILL.md").read_text()
        fm = re.match(r"---\n(.*?)\n---\n", skill, re.S)
        if not fm or not re.search(rf"^name: {h}$", fm.group(1), re.M):
            problems.append(f"{h}: frontmatter missing or name mismatch")
        for ref in set(re.findall(r"`(references/[\w.-]+\.md)`", skill)):
            if not (d / ref).exists():
                problems.append(f"{h}: SKILL.md points at missing {ref}")
        for m in re.finditer(r"source skill|hunter-party-|\(today:|Until consolidation", skill):
            problems.append(f"{h}/SKILL.md: historical wording: {m.group(0)}")

        # Category names in report-format.md must be What to Hunt headings.
        hunt = re.search(r"^## What to Hunt\n(.*?)^## ", skill, re.M | re.S)
        cats = {re.sub(r"\s*\*\(.*?\)\*", "", c).strip() for c in re.findall(r"^### (.+)$", hunt.group(1), re.M)}
        for c in re.findall(r"^### (.+)$", (d / "references/report-format.md").read_text(), re.M):
            if c.strip() not in cats:
                problems.append(f"{h}: report-format section '{c.strip()}' is not a What to Hunt heading")

        for f in sorted((d / "references").glob("*.md")):
            text, rel = f.read_text(), f.relative_to(ROOT)
            # history.md scans the diff history itself, so it passes $SCOPE on purpose.
            if "-- $SCOPE" in text and f.name != "history.md":
                problems.append(f"{rel}: scan passes raw $SCOPE (use the per-language eligible list)")
            for line in text.splitlines():
                cmd = re.match(r"\s*rg ((?:-[-\w=]*\s+)*)['\"]", line)
                if cmd and re.search(r"-- \$((GO|PY|TS)_(FILES|PROD|TESTS)|ALL_\w+)\b", line):
                    opts = cmd.group(1).split()
                    if not any(o == "-H" or re.fullmatch(r"-[A-Za-z]*[Hl][A-Za-z]*", o) for o in opts):
                        problems.append(f"{rel}: scan without -H (one-file list prints no file name): {line[:60]}")
                    if not any(re.fullmatch(r"-[A-Za-z]*[nlc][A-Za-z]*", o) for o in opts):
                        problems.append(f"{rel}: scan without -n (piped output prints no line number): {line[:60]}")
                if re.search(r"(^|[;&|(]\s*)rg [^\n|;>]*?-- [^\n|;>]*? -[A-Za-z]\b", line):
                    problems.append(f"{rel}: rg option after --: {line.strip()[:60]}")
            want, have = toc(text), re.search(r"^Contents: .*$", text, re.M)
            if (have.group(0) if have else None) != want:
                problems.append(f"{rel}: Contents line stale or missing (run --sync-from to refresh)")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--sync-from", metavar="HUNTER", choices=HUNTERS,
                   help="copy shared blocks from this hunter to the others and refresh Contents lines")
    args = p.parse_args()
    if args.sync_from:
        sync(args.sync_from)
        refresh_tocs()
    check()
    print("\n".join(problems) or "clean")
    sys.exit(1 if problems else 0)
