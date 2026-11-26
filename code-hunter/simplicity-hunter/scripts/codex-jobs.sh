#!/usr/bin/env bash
# Starts several Codex jobs at once, each confined to its own folder, and prints one status line per job.
#
#   bash codex-jobs.sh <job>...
#   bash codex-jobs.sh --selftest
#
# A job is a folder that holds prompt.md. The job reads that prompt, and writes its reply to <job>/reply.md, its
# output to <job>/log.txt and its scratch files to <job>/tmp. Go builds with its cache in <job>/tmp/go-build, because
# Go's default cache under the home folder is read-only in the sandbox. Codex's sandbox lets it write inside the job
# folder only. When the job ends, the script removes everything in <job> except prompt.md, log.txt and reply.md: a Go
# build cache can take hundreds of megabytes, and Codex may ignore TMPDIR and make its own scratch folder in <job>.
# All jobs start together. The script ends when every job has ended, and then prints one line per job, in argument
# order, with the absolute path:
#   <job>: ok                   exit code 0 and a reply that is not empty
#   <job>: failed — timed out   the time cap stopped the job
#   <job>: failed — exit <n>    Codex exited with n
#   <job>: failed — empty reply Codex exited with 0 and wrote no reply
# "ok" says only that the process ended well. It does not say that the reply is right: check-replies.sh checks it.
#
# Exit 0: every job ended, whatever its status. Exit 2: no job, or a job without prompt.md; no job has started.
# Exit 129, 130 or 143: HUP, INT or TERM stopped the launcher, and it sent TERM to every job that still ran.
set -euo pipefail
LLM=gpt-6.2-sol
EFFORT=high
CAP_SECONDS=3600
KILL_AFTER_SECONDS=60  # time between the stop signal and the kill; a job that ignores the stop signal still ends

# Usage: run_jobs <cap-seconds> <job>...
run_jobs() {
  local cap=$1 job rc i
  shift
  local jobs=() pids=()
  # Codex runs with -C <job> and TMPDIR=<job>/tmp; a relative path would point at the wrong place.
  for job in "$@"; do
    case $job in /*) ;; *) job=$PWD/$job ;; esac
    jobs+=("${job%/}")
  done
  [ ${#jobs[@]} -gt 0 ] || { echo "usage: codex-jobs.sh <job>..." >&2; exit 2; }
  for job in "${jobs[@]}"; do
    [ -f "$job/prompt.md" ] || { echo "no prompt.md in $job" >&2; exit 2; }
  done

  # Each timeout runs in its own process group, so a signal that stops the launcher would not reach its jobs.
  # `jobs -rp` lists only the jobs that still run: a PID of an ended job may already belong to another process.
  # A SIGKILL of the launcher cannot be trapped, and its jobs then run on until their time cap.
  local stop='kill -TERM $(jobs -rp) 2>/dev/null || true; exit'
  trap "$stop 129" HUP
  trap "$stop 130" INT
  trap "$stop 143" TERM

  for job in "${jobs[@]}"; do
    # An old reply must not pass as the reply of a job that writes nothing.
    rm -f "$job/reply.md"
    mkdir -p "$job/tmp"
    TMPDIR=$job/tmp GOCACHE=$job/tmp/go-build timeout --kill-after="$KILL_AFTER_SECONDS" "$cap" \
      codex exec --ephemeral --ignore-user-config --skip-git-repo-check -C "$job" -s workspace-write \
        -m "$LLM" -c model_reasoning_effort="$EFFORT" -c approval_policy=never \
        -c sandbox_workspace_write.exclude_slash_tmp=true \
        -c sandbox_workspace_write.exclude_tmpdir_env_var=true \
        -o "$job/reply.md" - < "$job/prompt.md" > "$job/log.txt" 2>&1 &
    pids+=($!)
  done

  for i in "${!jobs[@]}"; do
    job=${jobs[i]} rc=0
    wait "${pids[i]}" || rc=$?
    # A Go module cache is read-only, so the folder is made writable first. A failed removal must not cost the
    # status lines of the jobs after it.
    chmod -R u+w "$job" 2>/dev/null || true
    find "$job" -mindepth 1 -maxdepth 1 ! -name prompt.md ! -name log.txt ! -name reply.md \
      -exec rm -rf {} + 2>/dev/null || true
    if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
      echo "$job: failed — timed out"
    elif [ "$rc" != 0 ]; then
      echo "$job: failed — exit $rc"
    elif [ ! -s "$job/reply.md" ]; then
      echo "$job: failed — empty reply"
    else
      echo "$job: ok"
    fi
  done
}

selftest() {
  local self stub out want rc pid launcher
  self=$(realpath "$0")
  root=$(mktemp -d)
  trap 'chmod -R u+w "$root"; rm -rf "$root"' EXIT
  stub=$root/bin
  mkdir "$stub"
  cat > "$stub/codex" <<'STUB'
#!/usr/bin/env bash
dir= reply=
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[i]}" = -C ] && dir=${args[i+1]}
  [ "${args[i]}" = -o ] && reply=${args[i+1]}
done
# What the stub saw goes next to the job folder, because the launcher keeps only its own three files in it.
seen=$dir.seen
mkdir -p "$seen"
date +%s.%N > "$seen/start"
printf '%s\n' "$@" > "$seen/args.txt"
echo "TMPDIR=$TMPDIR" >> "$seen/args.txt"
echo "GOCACHE=$GOCACHE" >> "$seen/args.txt"
[ -d "$TMPDIR" ] && echo "tmpdir: exists" >> "$seen/args.txt"
cat > "$seen/stdin.txt"
case $(head -n 1 "$seen/stdin.txt") in
  ok) echo reply > "$reply" ;;
  "exit 3") exit 3 ;;
  empty) : > "$reply" ;;
  sleep) sleep 30 & echo "$$ $!" > "$seen/pid"; wait ;;
  silent) ;;
  read-only) mkdir "$TMPDIR/ro" && touch "$TMPDIR/ro/f" && chmod 555 "$TMPDIR/ro"; echo reply > "$reply" ;;
  litter)
    mkdir -p "$dir/.run/go-mod" "$dir/notes" && touch "$dir/.run/go-mod/f" "$dir/notes/f"
    chmod 555 "$dir/.run/go-mod"; echo reply > "$reply" ;;
esac
STUB
  chmod +x "$stub/codex"
  export PATH=$stub:$PATH

  cd "$root"
  mkdir j1 j2 j3 j4 j5
  echo ok > j1/prompt.md; echo "exit 3" > j2/prompt.md; echo empty > j3/prompt.md
  echo sleep > j4/prompt.md; echo silent > j5/prompt.md; echo old > j5/reply.md
  out=$(run_jobs 2 j1 j2 j3 j4 j5)
  want="$root/j1: ok
$root/j2: failed — exit 3
$root/j3: failed — empty reply
$root/j4: failed — timed out
$root/j5: failed — empty reply"
  [ "$out" = "$want" ] || { echo "status lines differ:"; echo "$out"; return 1; }

  want="exec
--ephemeral
--ignore-user-config
--skip-git-repo-check
-C
$root/j1
-s
workspace-write
-m
gpt-6.2-sol
-c
model_reasoning_effort=high
-c
approval_policy=never
-c
sandbox_workspace_write.exclude_slash_tmp=true
-c
sandbox_workspace_write.exclude_tmpdir_env_var=true
-o
$root/j1/reply.md
-
TMPDIR=$root/j1/tmp
GOCACHE=$root/j1/tmp/go-build
tmpdir: exists"
  [ "$(cat j1.seen/args.txt)" = "$want" ] || { echo "j1.seen/args.txt differs:"; cat j1.seen/args.txt; return 1; }
  [ -f j1/reply.md ] && [ -f j1/log.txt ] || { echo "j1 lost its reply or log"; return 1; }
  cmp -s j1.seen/stdin.txt j1/prompt.md || { echo "j1 stdin differs from prompt.md"; return 1; }

  for pid in $(cat j4.seen/pid); do
    ! kill -0 "$pid" 2>/dev/null || { echo "pid $pid of j4 is alive"; return 1; }
  done

  sort -n j?.seen/start | awk 'NR == 1 { first = $1 } { last = $1 } END { exit !(NR == 5 && last - first < 1) }' ||
    { echo "start times are more than 1 second apart"; return 1; }

  mkdir ok2 bad2
  echo ok > ok2/prompt.md
  rc=0
  (run_jobs 2 ok2 bad2) > /dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "missing prompt.md: exit $rc, want 2"; return 1; }
  [ ! -e ok2.seen ] && [ ! -e bad2.seen ] || { echo "a job started before the check"; return 1; }

  # Bash runs a function inside $(…) without set -e. So these cases start the launcher in its own process, as its
  # callers do, where set -e and the signal traps apply.
  mkdir ro litter after
  echo read-only > ro/prompt.md; echo litter > litter/prompt.md; echo ok > after/prompt.md
  out=$(bash "$self" ro litter after 2>&1) ||
    { echo "a read-only folder in a job folder stopped the launcher:"; echo "$out"; return 1; }
  [ "$out" = "$root/ro: ok
$root/litter: ok
$root/after: ok" ] || { echo "status lines after a read-only folder differ:"; echo "$out"; return 1; }
  out=$(find j1 j2 j3 j4 j5 ro litter after -mindepth 1 ! -name prompt.md ! -name log.txt ! -name reply.md)
  [ -z "$out" ] || { echo "job folders hold more than prompt.md, log.txt and reply.md:"; echo "$out"; return 1; }

  mkdir slow
  echo sleep > slow/prompt.md
  bash "$self" slow > /dev/null & launcher=$!
  for _ in $(seq 50); do [ -s slow.seen/pid ] && break; sleep 0.1; done
  [ -s slow.seen/pid ] || { echo "the sleep job never started"; return 1; }
  rc=0
  kill -TERM "$launcher"
  wait "$launcher" || rc=$?
  [ "$rc" = 143 ] || { echo "a stopped launcher exits $rc, want 143"; return 1; }
  for _ in $(seq 50); do kill -0 $(cat slow.seen/pid) 2>/dev/null || break; sleep 0.1; done
  for pid in $(cat slow.seen/pid); do
    ! kill -0 "$pid" 2>/dev/null || { echo "pid $pid of a stopped launcher's job is alive"; return 1; }
  done
  echo "selftest ok"
}

if [ "${1:-}" = --selftest ]; then
  selftest
else
  run_jobs "$CAP_SECONDS" "$@"
fi
