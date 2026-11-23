#!/usr/bin/env python3
"""Draft review comments on a GitHub pull request or a GitLab merge request.

    post_drafts.py threads <pr>                         the head commit, the title and description, existing threads, your own drafts
    post_drafts.py diff <pr>                            the diff that comments are checked against
    post_drafts.py post <pr> <comments.json> --dry-run  check every comment, write nothing
    post_drafts.py post <pr> <comments.json>            check every comment, then create the drafts

<pr> is a pull request or merge request URL, or a number (host and repository then come from the
`origin` remote of the current directory). Needs `gh` or `glab`, logged in to that host.

comments.json:
    {"summary": "markdown, optional",
     "comments": [
       {"path": "a.py", "line": 28, "body": "..."},                    line 28 of the new file
       {"path": "a.py", "start_line": 27, "line": 30, "body": "..."},  lines 27-30 of the new file
       {"path": "a.py", "old_line": 26, "body": "..."},                a removed line, numbered as in the old file
       {"path": "a.py", "start_line": 25, "old_line": 26, "body": "..."},  removed lines 25-26 of the old file
       {"path": "a.py", "body": "..."},                                the file as a whole
       {"body": "..."}]}                                               the change as a whole

A body may hold one ```suggestion block. It replaces exactly the commented lines of the new file.
A place written as `dir/file.py:8` or `dir/file.py:8-12` becomes a link to those lines at the head commit.
Nothing is published: GitHub gets one pending review, GitLab gets draft notes.
"""
import hashlib
import json
import re
import subprocess
import sys
from urllib.parse import quote, urlparse

SUGGESTION_FENCE = re.compile(r"^```suggestion[ \t]*$", re.M)
COMMENT_KEYS = {"path", "line", "start_line", "old_line", "body"}
PREVIEW_CHARS = 300
PLACE_IN_TEXT = re.compile(r"`((?:[\w.@+-]+/)+[\w.@+-]+):(\d+)(?:-(\d+))?`")
CODE_BLOCK = re.compile(r"(^```.*?^```)", re.M | re.S)


class ApiError(Exception):
    pass


def run(cmd, stdin=None):
    done = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
    return done.returncode, done.stdout, done.stderr


def parse_diff(text):
    """Maps each path of a unified diff to its commentable lines.

    new: {new line number: old line number, or None for an added line}.
    old: {removed old line number: the new line number that the next line of the new file has}.
    added: {added new line number: the old line number that the next line of the old file has}.
    """
    files, current = {}, None
    old_left = new_left = old_no = new_no = 0

    def register(entry):
        for path in (entry["old_path"], entry["new_path"]):
            if path:
                files[path] = entry

    def path_of(raw):
        # ponytail: git octal-escapes non-ASCII paths; they are not decoded here. Decode when one shows up.
        raw = raw.split("\t")[0].strip('"')
        return None if raw == "/dev/null" else raw[2:]

    for line in text.splitlines():
        if old_left or new_left:
            marker = line[:1]
            if marker == "+":
                current["new"][new_no] = None
                current["added"][new_no] = old_no
                new_no, new_left = new_no + 1, new_left - 1
            elif marker == "-":
                current["old"][old_no] = new_no
                old_no, old_left = old_no + 1, old_left - 1
            elif marker != "\\":
                current["new"][new_no] = old_no
                old_no, new_no, old_left, new_left = old_no + 1, new_no + 1, old_left - 1, new_left - 1
        elif line.startswith("diff --git "):
            current = {"old_path": None, "new_path": None, "new": {}, "old": {}, "added": {}, "hunks": []}
            same_path = re.match(r"diff --git a/(.*) b/\1$", line)
            if same_path:
                current["old_path"] = current["new_path"] = same_path[1]
                register(current)
        elif current is None:
            continue
        elif line.startswith("rename from "):
            current["old_path"] = line[len("rename from "):]
        elif line.startswith("rename to "):
            current["new_path"] = line[len("rename to "):]
            register(current)
        elif line.startswith("--- "):
            current["old_path"] = path_of(line[4:])
        elif line.startswith("+++ "):
            current["new_path"] = path_of(line[4:])
            register(current)
        elif line.startswith("@@"):
            header = re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
            old_no, new_no = int(header[1]), int(header[3])
            old_left, new_left = int(header[2] or 1), int(header[4] or 1)
            current["hunks"].append((old_no, old_left, new_no, new_left))
    return files


def old_line_outside_hunks(entry, line):
    shift = sum(new_len - old_len for _, old_len, new_start, new_len in entry["hunks"] if new_start + new_len <= line)
    return line - shift


def line_counters(entry, removed, number):
    """(old, new) line counters at a line of the diff. GitLab names a line by them: its line code."""
    if removed:
        return number, entry["old"][number]
    if number in entry["added"]:
        return entry["added"][number], number
    old = entry["new"].get(number)
    return (old_line_outside_hunks(entry, number) if old is None else old), number


def place(comment, files, lines_outside_hunks_allowed):
    """Returns the comment with its position resolved against the diff, or raises ValueError with the remedy."""
    unknown = set(comment) - COMMENT_KEYS
    if unknown:
        raise ValueError(f"unknown key {sorted(unknown)}; allowed: {sorted(COMMENT_KEYS)}")
    body = comment.get("body", "").strip()
    if not body:
        raise ValueError("empty body")
    path, line, start, old_line = (comment.get(key) for key in ("path", "line", "start_line", "old_line"))
    suggestions = len(SUGGESTION_FENCE.findall(body))
    if suggestions > 1:
        raise ValueError("more than one suggestion block; keep one, or split the comment")
    if suggestions and line is None:
        raise ValueError("a suggestion block needs \"line\": it can only replace lines of the new file")
    if path is None:
        if line is not None or old_line is not None:
            raise ValueError("a line needs a \"path\"")
        return {"kind": "general", "body": body}
    if path not in files:
        raise ValueError(
            f"{path} is not in the diff. Put the comment on the changed line that causes the problem "
            "and name this file in the text, or drop \"path\" to make it a general comment")
    entry = files[path]
    placed = {"body": body, "path": entry["new_path"] or entry["old_path"],
              "old_path": entry["old_path"] or entry["new_path"]}
    if line is None and old_line is None:
        if start is not None:
            raise ValueError("\"start_line\" needs \"line\"")
        return {**placed, "kind": "file"}
    if line is not None and old_line is not None:
        raise ValueError("give \"line\" (new file) or \"old_line\" (removed line), not both")
    if old_line is not None:
        start = old_line if start is None else start
        if start > old_line:
            raise ValueError(f"start_line {start} is after old_line {old_line}")
        kept = [number for number in range(start, old_line + 1) if number not in entry["old"]]
        if kept:
            raise ValueError(
                f"old line {kept[0]} of {path} is not a removed line. For a line that still exists, "
                "use \"line\" with its number in the new file")
        return {**placed, "kind": "old", "old_line": old_line, "start_line": start,
                "range": [line_counters(entry, True, number) for number in (start, old_line)]}
    start = line if start is None else start
    if start > line:
        raise ValueError(f"start_line {start} is after line {line}")
    outside = [number for number in range(start, line + 1) if number not in entry["new"]]
    if outside and not lines_outside_hunks_allowed:
        raise ValueError(
            f"line {outside[0]} of {path} is outside the diff hunks, and GitHub takes no line comment there. "
            "Drop \"line\" to comment on the file, and name the line in the text"
            + ("; say the fix in words, without a suggestion block" if suggestions else ""))
    old_of_line = entry["new"][line] if line in entry["new"] else old_line_outside_hunks(entry, line)
    return {**placed, "kind": "new", "line": line, "start_line": start, "old_line": old_of_line,
            "range": [line_counters(entry, False, number) for number in (start, line)]}


def link_places(text, blob_url, range_join):
    """Turns each `dir/file:line` outside a code block into a short link to that line of the head commit.

    The link targets go at the end of the text, so the sentences stay readable in the edit box.
    """
    targets = {}

    def link(found):
        path, first, last = found[1], found[2], found[3]
        span = first + (f"-{last}" if last else "")
        target = f"{blob_url}/{quote(path)}#L{first}" + (f"{range_join}{last}" if last else "")
        label = f"{path.rsplit('/', 1)[1]}:{span}"
        if targets.get(label, (target,))[0] != target:
            label = f"{path}:{span}"  # another folder has a file of this name
        targets[label] = (target, f"{path}:{span}")
        return f"[{label}][]"

    # ponytail: the path is not checked against the repository, and a file in the root folder (no "/") stays
    # code, because `host.com:8080` looks the same. List the tree of the head commit when a wrong link shows up.
    linked = "".join(part if part.startswith("```") else PLACE_IN_TEXT.sub(link, part) for part in CODE_BLOCK.split(text))
    return linked + "".join(["\n"] + [f'\n[{label}]: {target} "{title}"' for label, (target, title) in targets.items()]) * bool(targets)


def describe(placed):
    if placed["kind"] == "general":
        return "general"
    if placed["kind"] == "file":
        return f"{placed['path']} (file)"
    removed = placed["kind"] == "old"
    end = placed["old_line"] if removed else placed["line"]
    span = str(end) if placed["start_line"] == end else f"{placed['start_line']}-{end}"
    return f"{placed['old_path']}:{span} (removed)" if removed else f"{placed['path']}:{span}"


def preview(text):
    return " ".join(text.split())[:PREVIEW_CHARS]


class GitHub:
    lines_outside_hunks_allowed = False

    def __init__(self, host, repo, number):
        self.host, self.repo, self.number = host, repo, number
        self.owner, self.name = repo.split("/")

    def api(self, *args, body=None):
        cmd = ["gh", "api", "--hostname", self.host, *args]
        if body is not None:
            cmd += ["--input", "-"]
        code, out, err = run(cmd, None if body is None else json.dumps(body))
        if code:
            raise ApiError((err or out).strip())
        return json.loads(out) if out.strip() else None

    def graphql(self, query, **variables):
        # gh exits 0 on some GraphQL failures and non-zero on others, so the answer is read in both cases.
        _, out, err = run(["gh", "api", "--hostname", self.host, "graphql", "--input", "-"],
                          json.dumps({"query": query, "variables": variables}))
        answer = json.loads(out) if out.strip().startswith("{") else {}
        if answer.get("errors") or "data" not in answer:
            raise ApiError("; ".join(e["message"] for e in answer.get("errors", [])) or err.strip())
        return answer["data"]

    def load(self):
        pull = self.api(f"repos/{self.repo}/pulls/{self.number}")
        self.head, self.url = pull["head"]["sha"], pull["html_url"]
        self.title, self.description = pull["title"], pull["body"]
        self.blob_url, self.range_join = f"{self.url.split('/pull/')[0]}/blob/{self.head}", "-L"
        # ponytail: GitHub refuses this diff above 20,000 lines or 300 files; build it from git when a PR that big shows up.
        code, self.diff, err = run(["gh", "api", "--hostname", self.host, f"repos/{self.repo}/pulls/{self.number}",
                                    "-H", "Accept: application/vnd.github.diff"])
        if code:
            raise ApiError(err.strip())

    def threads(self):
        # ponytail: first 100 threads, reviews and comments; page when a PR has more.
        pull = self.graphql("""query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){
          pullRequest(number:$number){
            reviews(first:100){nodes{state body author{login}}}
            comments(first:100){nodes{body author{login}}}
            reviewThreads(first:100){nodes{path line originalLine diffSide subjectType isResolved isOutdated
              comments(first:1){nodes{body author{login} pullRequestReview{state}}}}}}}}""",
                            owner=self.owner, name=self.name, number=self.number)["repository"]["pullRequest"]
        rows = []
        for thread in pull["reviewThreads"]["nodes"]:
            first = thread["comments"]["nodes"][0]
            draft = first["pullRequestReview"]["state"] == "PENDING"
            state = "draft" if draft else "resolved" if thread["isResolved"] else "open"
            where = thread["path"] if thread["subjectType"] == "FILE" else f"{thread['path']}:{thread['line'] or thread['originalLine']}"
            where += " (removed)" * (thread["subjectType"] != "FILE" and thread["diffSide"] == "LEFT")
            rows.append((state + (" outdated" if thread["isOutdated"] else ""), where, first["author"]["login"], first["body"]))
        for review in pull["reviews"]["nodes"]:
            if review["body"]:
                state = "draft" if review["state"] == "PENDING" else "open"
                rows.append((state, "review summary", review["author"]["login"], review["body"]))
        for comment in pull["comments"]["nodes"]:
            rows.append(("open", "general", comment["author"]["login"], comment["body"]))
        return rows

    def post(self, placed_comments, summary):
        general = [summary] if summary else []
        general += [placed["body"] for placed in placed_comments if placed["kind"] == "general"]
        pending = self.graphql("""query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){
          pullRequest(number:$number){reviews(states:PENDING,first:1){nodes{id body}}}}}""",
                               owner=self.owner, name=self.name, number=self.number
                               )["repository"]["pullRequest"]["reviews"]["nodes"]
        separator = "\n\n---\n\n"
        if not pending:
            review_id = self.api("-X", "POST", f"repos/{self.repo}/pulls/{self.number}/reviews",
                                 body={"commit_id": self.head, "body": separator.join(general)})["node_id"]
        else:
            review_id, existing_summary = pending[0]["id"], pending[0]["body"]
            print("You already have a pending review on this pull request; the drafts are added to it.")
            if general and not existing_summary:
                # GitHub answers "Could not edit a review with a missing body" for a pending review without one.
                sys.exit("That pending review has no summary text, and GitHub cannot add one to it later, so the summary "
                         "and the general comments have no place. Submit or discard that review on GitHub, then run "
                         "again. Nothing was written.")
            if general:
                self.graphql("""mutation($id:ID!,$body:String!){updatePullRequestReview(
                  input:{pullRequestReviewId:$id,body:$body}){pullRequestReview{id}}}""",
                             id=review_id, body=separator.join([existing_summary] + general))
        failures = []
        for index, placed in enumerate(placed_comments):
            if placed["kind"] == "general":
                continue
            thread = {"pullRequestReviewId": review_id, "path": placed["path"], "body": placed["body"]}
            if placed["kind"] == "file":
                thread["subjectType"] = "FILE"
            else:
                side = "LEFT" if placed["kind"] == "old" else "RIGHT"
                end = placed["old_line"] if placed["kind"] == "old" else placed["line"]
                thread.update(line=end, side=side)
                if placed["start_line"] != end:
                    thread.update(startLine=placed["start_line"], startSide=side)
            try:
                created = self.graphql("""mutation($input:AddPullRequestReviewThreadInput!){
                  addPullRequestReviewThread(input:$input){thread{id}}}""", input=thread)["addPullRequestReviewThread"]["thread"]
                if created is None:
                    failures.append((index, "GitHub created no thread and gave no reason"))
            except ApiError as error:
                failures.append((index, str(error)))
        return failures, f"{self.url}/files"


class GitLab:
    lines_outside_hunks_allowed = True

    def __init__(self, host, repo, number):
        self.host = host
        self.base = f"projects/{quote(repo, safe='')}/merge_requests/{number}"

    def api(self, path, method="GET", body=None, raw=False):
        cmd = ["glab", "api", "--hostname", self.host, "-X", method, path]
        if body is not None:
            cmd += ["-H", "Content-Type: application/json", "--input", "-"]
        code, out, err = run(cmd, None if body is None else json.dumps(body))
        if code:
            raise ApiError((err or out).strip())
        if raw:
            return out
        return json.loads(out) if out.strip() else None

    def pages(self, path):
        page, items = 1, []
        while True:
            batch = self.api(f"{path}?per_page=100&page={page}")
            items += batch
            if len(batch) < 100:
                return items
            page += 1

    def load(self):
        merge_request = self.api(self.base)
        self.refs, self.url = merge_request["diff_refs"], merge_request["web_url"]
        self.head = self.refs["head_sha"]
        self.title, self.description = merge_request["title"], merge_request["description"]
        self.blob_url, self.range_join = f"{self.url.split('/-/merge_requests/')[0]}/-/blob/{self.head}", "-"
        self.diff = self.api(f"{self.base}/raw_diffs", raw=True)

    def threads(self):
        def place_of(position):
            if not position or not position.get("new_path"):
                return "general"
            if position.get("new_line"):
                return f"{position['new_path']}:{position['new_line']}"
            if position.get("old_line"):
                return f"{position['old_path']}:{position['old_line']} (removed)"
            return position["new_path"]

        rows = []
        for discussion in self.pages(f"{self.base}/discussions"):
            first = discussion["notes"][0]
            if not first["system"]:
                state = "resolved" if first.get("resolved") else "open"
                rows.append((state, place_of(first.get("position")), first["author"]["username"], first["body"]))
        for draft in self.pages(f"{self.base}/draft_notes"):
            rows.append(("draft", place_of(draft.get("position")), "you", draft["note"]))
        return rows

    def post(self, placed_comments, summary):
        failures = []
        notes = [(None, {"kind": "general", "body": summary})] * bool(summary) + list(enumerate(placed_comments))
        for index, placed in notes:
            note = {"note": placed["body"]}
            if placed["kind"] != "general":
                position = {**self.refs, "position_type": "text", "old_path": placed["old_path"], "new_path": placed["path"]}
                if placed["kind"] == "file":
                    position["position_type"] = "file"
                elif placed["range"][0] != placed["range"][1]:
                    # GitLab 18.5 rejects line numbers in the `line_range` of a draft note, so each end is a line code only.
                    file_hash = hashlib.sha1(placed["path"].encode()).hexdigest()
                    side = "old" if placed["kind"] == "old" else "new"
                    position["line_range"] = dict(zip(("start", "end"), (
                        {"line_code": f"{file_hash}_{old}_{new}", "type": side} for old, new in placed["range"])))
                if placed["kind"] == "old":
                    position["old_line"] = placed["old_line"]
                elif placed["kind"] == "new":
                    position["new_line"] = placed["line"]
                    if placed["old_line"] is not None:
                        position["old_line"] = placed["old_line"]
                    # A GitLab suggestion counts its lines upward from the commented line.
                    note["note"] = SUGGESTION_FENCE.sub(f"```suggestion:-{placed['line'] - placed['start_line']}+0", placed["body"])
                note["position"] = position
            try:
                draft = self.api(f"{self.base}/draft_notes", "POST", note)
                on_a_line = placed["kind"] in ("new", "old")
                if on_a_line and not draft.get("line_code"):
                    # GitLab stores a draft it cannot attach to the diff; submitting the review then fails with HTTP 500.
                    self.api(f"{self.base}/draft_notes/{draft['id']}", "DELETE")
                    failures.append((index, "GitLab could not attach the draft to that line, so it was deleted"))
            except ApiError as error:
                failures.append((index, str(error)))
        return failures, self.url


def target(reference):
    if reference.isdigit():
        code, remote, _ = run(["git", "remote", "get-url", "origin"])
        found = re.match(r"(?:ssh://)?(?:git@|https://)([^:/]+)[:/](.+?)(?:\.git)?$", remote.strip())
        if code or not found:
            sys.exit(f"{reference} is a number, and the current directory has no usable `origin` remote. Pass the URL.")
        host, repo, number = found[1], found[2], reference
        on_github = "github" in host
    else:
        url = urlparse(reference)
        found = re.match(r"/(.+?)/(-/merge_requests|pull)/(\d+)", url.path)
        if not found:
            sys.exit(f"{reference} is not a pull request URL, a merge request URL or a number.")
        host, repo, number = url.netloc, found[1], found[3]
        on_github = found[2] == "pull"
    return (GitHub if on_github else GitLab)(host, repo, int(number))


def main(argv):
    if len(argv) < 2 or argv[0] not in ("threads", "diff", "post"):
        sys.exit(__doc__)
    command, host = argv[0], target(argv[1])
    try:
        host.load()
        if command == "diff":
            print(host.diff)
            return 0
        if command == "threads":
            print(f"head {host.head}")
            print(f"title {host.title}")
            print("description " + ((host.description or "").strip().replace("\n", "\n    ") or "(none)"))
            for state, where, author, text in host.threads():
                print(f"{state:<17} {where:<40} @{author:<16} {preview(text)}")
            return 0
        if len(argv) < 3:
            sys.exit(__doc__)
        with open(argv[2]) as handle:
            review = json.load(handle)
        files, placed_comments, misplaced = parse_diff(host.diff), [], []
        for index, comment in enumerate(review.get("comments", [])):
            try:
                placed_comments.append(place(comment, files, host.lines_outside_hunks_allowed))
            except ValueError as problem:
                misplaced.append(f"comments[{index}] ({preview(comment.get('body', ''))[:50]}): {problem}")
        if misplaced:
            print("\n".join(misplaced))
            print(f"\n{len(misplaced)} of {len(review['comments'])} comments cannot be placed. Nothing was written.")
            return 1
        for index, placed in enumerate(placed_comments):
            print(f"comments[{index}] -> {describe(placed)}")
        if "--dry-run" in argv:
            print(f"\nAll {len(placed_comments)} comments fit the diff at {host.head[:8]}. Dry run: nothing was written.")
            return 0
        # ponytail: each text gets its own link targets. Two general comments that name files of one name and line
        # in different folders share one GitHub review text, and the first target wins. Link the joined text then.
        for placed in placed_comments:
            placed["body"] = link_places(placed["body"], host.blob_url, host.range_join)
        summary = link_places(review.get("summary", "").strip(), host.blob_url, host.range_join)
        failures, url = host.post(placed_comments, summary)
        for index, reason in failures:
            print(f"FAILED {'summary' if index is None else f'comments[{index}]'}: {reason}")
        drafted = len(placed_comments) - sum(index is not None for index, _ in failures)
        print(f"\n{drafted} of {len(placed_comments)} comments are drafts now{', and the summary' * bool(summary)}. "
              f"Nothing is published: {url}")
        return 1 if failures else 0
    except ApiError as error:
        sys.exit(f"The host refused: {error}")


def self_check():
    diff = """diff --git a/a.py b/a.py
--- a/a.py
+++ b/a.py
@@ -2,3 +2,4 @@
 two
+added
 three
 four
@@ -20,4 +21,2 @@
 twenty
-gone
-gone too
 twenty-three
diff --git a/old.py b/new.py
similarity index 100%
rename from old.py
rename to new.py
"""
    files = parse_diff(diff)
    entry = files["a.py"]
    assert entry["new"] == {2: 2, 3: None, 4: 3, 5: 4, 21: 20, 22: 23}, entry["new"]
    assert entry["old"] == {21: 22, 22: 22} and entry["added"] == {3: 3}
    assert line_counters(entry, False, 3) == (3, 3) and line_counters(entry, False, 22) == (23, 22)
    assert line_counters(entry, True, 22) == (22, 22) and line_counters(entry, False, 30) == (31, 30)
    assert files["old.py"] is files["new.py"]
    assert old_line_outside_hunks(entry, 10) == 9 and old_line_outside_hunks(entry, 30) == 31
    assert place({"path": "a.py", "line": 3, "body": "x"}, files, False)["old_line"] is None
    assert place({"path": "a.py", "line": 10, "body": "x"}, files, True)["old_line"] == 9
    assert place({"path": "a.py", "old_line": 21, "body": "x"}, files, False)["kind"] == "old"
    assert describe(place({"path": "a.py", "start_line": 21, "old_line": 22, "body": "x"}, files, False)) == "a.py:21-22 (removed)"
    assert place({"path": "new.py", "body": "x"}, files, False)["old_path"] == "old.py"
    for wrong in ({"path": "a.py", "line": 10, "body": "x"}, {"path": "b.py", "line": 1, "body": "x"},
                  {"path": "a.py", "old_line": 3, "body": "x"}, {"path": "a.py", "old_line": 21, "body": "```suggestion\ny\n```"},
                  {"path": "a.py", "start_line": 20, "old_line": 22, "body": "x"},
                  {"path": "a.py", "lines": 3, "body": "x"}, {"path": "a.py", "line": 3, "body": " "}):
        try:
            place(wrong, files, False)
        except ValueError:
            continue
        raise AssertionError(f"accepted {wrong}")
    linked = link_places("See `a/b.py:8` and `c/b.py:8`, not `b.py:8`.\n\n```\n`a/b.py:9`\n```\n`a/b.py:3-5`", "https://h/blob/s", "-L")
    assert linked.startswith("See [b.py:8][] and [c/b.py:8][], not `b.py:8`.\n\n```\n`a/b.py:9`\n```\n[b.py:3-5][]\n\n"), linked
    assert linked.endswith('[b.py:8]: https://h/blob/s/a/b.py#L8 "a/b.py:8"\n[c/b.py:8]: https://h/blob/s/c/b.py#L8 "c/b.py:8"\n'
                           '[b.py:3-5]: https://h/blob/s/a/b.py#L3-L5 "a/b.py:3-5"'), linked
    assert link_places("no place here", "u", "-") == "no place here"
    print("self-check passed")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-check"]:
        self_check()
    else:
        sys.exit(main(sys.argv[1:]))
