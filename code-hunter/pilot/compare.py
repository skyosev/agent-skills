"""Compare hunter reports across setups and runs.

    python3 code-hunter/pilot/compare.py S=<dir> W=<dir> [--within PREFIX ...] [--tol 3] [--out FILE]
    python3 code-hunter/pilot/compare.py --selftest

Each setup dir holds one sub-dir per run, with the report.md and result.json that pilot.sh writes. A finding's
anchor is the first file:line in the second cell of a Findings table row, else in the row. A run dir without a
report.md is skipped. Findings in one file whose lines are at
most --tol apart are one site across runs, whatever their category: two runs can file one defect under two
categories. --within keeps only findings whose anchor file starts with one of the prefixes (the premise test compares
only the subset's findings). Prints a runs table, rows per category, and a site matrix; writes the sites that only one
setup found to --out, for review.
"""
import argparse, json, pathlib, re, sys

ANCHOR = re.compile(r"([\w./@+-]+\.\w+):(\d+)")
CELL = re.compile(r"(?<!\\)\|")
COMPLETED = re.compile(r"Audit completed:\s*(\d+)")


def parse(text):
    """Rows of a report: (category, file, line, row text). The anchor is in the second column, or in the row."""
    rows, category, in_findings = [], None, False
    for line in text.splitlines():
        if line.startswith("## "):
            in_findings = line.strip() == "## Findings"
            category = None
        elif in_findings and line.startswith("### "):
            category = line[4:].strip()
        elif in_findings and category and line.startswith("|"):
            cells = CELL.split(line)
            if len(cells) < 4 or cells[1].strip() == "#" or set(cells[1].strip()) <= set("-: "):
                continue
            loc = cells[2].replace("`", "")
            m = ANCHOR.search(loc) or ANCHOR.search(line)
            rows.append((category, m.group(1) if m else loc.strip(), int(m.group(2)) if m else 0, line.strip()))
    return rows


def load(setup_dir):
    runs = {}
    for d in sorted(p for p in pathlib.Path(setup_dir).iterdir() if p.is_dir()):
        report, result = d / "report.md", d / "result.json"
        if not report.exists():
            print(f"warning: {d}: no report.md, run skipped", file=sys.stderr)
            continue
        text = report.read_text()
        res = json.loads(result.read_text()) if result.exists() and result.stat().st_size else {}
        rows = parse(text)
        m = COMPLETED.search(text)
        if m and int(m.group(1)) != len(rows):
            print(f"warning: {report}: Audit completed {m.group(1)}, parsed {len(rows)} rows", file=sys.stderr)
        runs[d.name] = {"rows": rows, "result": res}
    return runs


def cluster(findings, tol):
    """findings: (setup, run, category, file, line, text). Returns lists of findings at the same site."""
    groups = []
    for f in sorted(findings, key=lambda f: (f[3], f[4])):
        g = groups[-1] if groups else None
        if g and g[0][3] == f[3] and f[4] - g[0][4] <= tol:
            g.append(f)
        else:
            groups.append([f])
    return groups


def report(setups, within, tol):
    keep = lambda r: not within or any(r[1].startswith(p) for p in within)
    out = ["| Setup | Run | Rows | Rows kept | Cost USD | Minutes | Turns | Output tokens | Denials |", "|---|---|---|---|---|---|---|---|---|"]
    findings = []
    for name, runs in setups.items():
        for run, data in runs.items():
            res, kept = data["result"], [r for r in data["rows"] if keep(r)]
            findings += [(name, run, *r) for r in kept]
            usage = res.get("usage") or {}
            out.append(f"| {name} | {run} | {len(data['rows'])} | {len(kept)} | {res.get('total_cost_usd', 0):.2f} | "
                       f"{res.get('duration_ms', 0) / 60000:.1f} | {res.get('num_turns', '')} | "
                       f"{usage.get('output_tokens', '')} | {len(res.get('permission_denials') or [])} |")
    names = list(setups)
    out += ["", "| Category | " + " | ".join(f"{n}: rows per run" for n in names) + " |", "|---|" + "---|" * len(names)]
    for cat in sorted({f[2] for f in findings}):
        out.append(f"| {cat} | " + " | ".join(" / ".join(str(sum(1 for f in findings if f[:3] == (n, run, cat)))
                                                    for run in setups[n]) for n in names) + " |")
    cols = [(n, run) for n in names for run in setups[n]]
    out += ["", "| Site | " + " | ".join(n + run for n, run in cols) + " | Categories |", "|---|" + "---|" * (len(cols) + 1)]
    groups = cluster(findings, tol)
    for g in groups:
        have = {f[:2] for f in g}
        out.append(f"| {g[0][3]}:{g[0][4]} | " + " | ".join("x" if c in have else "" for c in cols) +
                   f" | {', '.join(sorted({f[2] for f in g}))} |")
    out.append("| sites per run | " + " | ".join(str(sum(1 for g in groups if c in {f[:2] for f in g})) for c in cols) + " | |")
    return "\n".join(out), [g for g in groups if len({f[0] for f in g}) == 1]


def disagreements(only, setups):
    lines = ["# Sites that only one setup found", ""]
    for g in only:
        name, runs = g[0][0], sorted({f[1] for f in g})
        lines += [f"## {g[0][3]}:{g[0][4]}", "", f"Found by {name}, runs {', '.join(runs)} of {len(setups[name])}.", ""]
        for cat in sorted({f[2] for f in g}):
            lines += [f"{cat}:", "", next(f[5] for f in g if f[2] == cat)[:600], ""]
    return "\n".join(lines)


def selftest():
    a = "## Scope\n- Audit completed: 2 findings\n\n## Findings\n\n### Magic Numbers\n\n| # | Location | Value |\n|---|---|---|\n" \
        "| 1 | `internal/a.go:10` | `x \\| y` |\n| 2 | internal/b.go:5, internal/c.go:7 | 3 |\n\n### Coexisting Generations\n\n" \
        "| # | Concern | Strata |\n|---|---|---|\n| 1 | HTTP | `lib/old.go:3` and `lib/new.go:8` |\n\n## Recommendations\n| 1 | z.go:1 |\n"
    rows = parse(a)
    assert [(r[0], r[1], r[2]) for r in rows] == [("Magic Numbers", "internal/a.go", 10), ("Magic Numbers", "internal/b.go", 5),
                                                ("Coexisting Generations", "lib/old.go", 3)], rows
    fs = [("S", "1", "M", "a.go", 10, ""), ("W", "1", "M", "a.go", 12, ""), ("W", "1", "M", "a.go", 20, ""), ("S", "1", "N", "a.go", 10, ""),
          ("S", "1", "M", "b.go", 11, "")]
    assert [len(g) for g in cluster(fs, 3)] == [3, 1, 1]  # one site whatever the category; another file is another site
    print("selftest ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
        sys.exit()
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("setups", nargs="+", metavar="NAME=DIR")
    p.add_argument("--within", action="append", default=[])
    p.add_argument("--tol", type=int, default=3)
    p.add_argument("--out", default="disagreements.md")
    args = p.parse_args()
    setups = {s.split("=", 1)[0]: load(s.split("=", 1)[1]) for s in args.setups}
    table, only = report(setups, args.within, args.tol)
    print(table)
    pathlib.Path(args.out).write_text(disagreements(only, setups))
    print(f"\n{len(only)} sites found by one setup only -> {args.out}")
