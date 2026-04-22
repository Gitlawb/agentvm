#!/usr/bin/env bash
# End-to-end smoke test for agentvm. Runs in an isolated AGENTVM_HOME so it
# cannot disturb the user's real agents. Exits 0 on success, non-zero on failure.
#
# Usage: tests/smoke.sh [--keep]    # --keep leaves the tmpdir for inspection
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "$0")/.." && pwd)"
AGENTVM="$SCRIPT_DIR/agentvm"
[[ -x "$AGENTVM" ]] || { echo "agentvm not executable at $AGENTVM"; exit 1; }

KEEP=false
[[ "${1:-}" == "--keep" ]] && KEEP=true

TMP="$(mktemp -d -t agentvm-smoke.XXXXXX)"
export AGENTVM_HOME="$TMP"
cleanup() {
  if [[ "$KEEP" == "true" ]]; then
    echo "# [keep] test dir: $TMP"
    return
  fi
  "$AGENTVM" purge --force 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

fail=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=$((fail+1)); }
section() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

section "version + help"
"$AGENTVM" version >/dev/null && pass "version" || bad "version failed"
"$AGENTVM" help    >/dev/null && pass "help"    || bad "help failed"

section "doctor"
if "$AGENTVM" doctor >/dev/null 2>&1; then pass "doctor clean exit"; else bad "doctor non-zero (may be expected if binaries missing)"; fi

section "profiles"
"$AGENTVM" profiles >/dev/null && pass "profiles listed"

section "env subcommand"
"$AGENTVM" env set SMOKE_KEY=abc123 >/dev/null
[[ "$("$AGENTVM" env get SMOKE_KEY)" == "abc123" ]] && pass "env get returns set value" || bad "env get wrong value"
"$AGENTVM" env unset SMOKE_KEY >/dev/null
"$AGENTVM" env get SMOKE_KEY 2>/dev/null && bad "env get should fail after unset" || pass "env unset removes key"

section "spawn + list + info"
"$AGENTVM" spawn smoke-a -- /bin/sh -c 'while true; do date; sleep 1; done' >/dev/null
"$AGENTVM" list | grep -q smoke-a && pass "spawned agent appears in list" || bad "agent not in list"
"$AGENTVM" list -q | grep -qx smoke-a && pass "list -q prints bare name" || bad "list -q failed"
"$AGENTVM" info smoke-a | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep -q '^Agent: smoke-a' && pass "info prints agent" || bad "info output wrong"
"$AGENTVM" info smoke-a --json | grep -q '"name":"smoke-a"' && pass "info --json works" || bad "info --json missing name"
"$AGENTVM" list --json | grep -q '"name":"smoke-a"' && pass "list --json works" || bad "list --json missing name"

section "logs"
sleep 2
[[ -f "$AGENTVM_HOME/state/smoke-a.log" ]] && pass "log file exists" || bad "log file not created"
"$AGENTVM" logs smoke-a -n 5 >/dev/null && pass "logs returned" || bad "logs failed"

section "exec"
"$AGENTVM" exec smoke-a 'echo SMOKE_MARKER_XYZ' >/dev/null
sleep 2
grep -q SMOKE_MARKER_XYZ "$AGENTVM_HOME/state/smoke-a.log" && pass "exec reached the pane" || bad "SMOKE_MARKER_XYZ not found in log"

section "ps"
"$AGENTVM" ps --json | grep -q '"name":"smoke-a"' && pass "ps --json includes running agent" || bad "ps --json missing name"

section "tags + filter"
"$AGENTVM" spawn smoke-b -t env=test -- /bin/sh -c 'sleep 100' >/dev/null
"$AGENTVM" list --tag env=test | grep -q smoke-b && pass "list --tag filters" || bad "list --tag didn't filter"
[[ "$("$AGENTVM" list --tag env=test -q | wc -l | tr -d ' ')" == "1" ]] && pass "list --tag returns one agent" || bad "unexpected match count"

section "clone + restart"
"$AGENTVM" kill smoke-b >/dev/null 2>&1 || true
sleep 1
"$AGENTVM" clone smoke-b smoke-b-fork >/dev/null && pass "clone succeeded" || bad "clone failed"
[[ -d "$AGENTVM_HOME/workspaces/smoke-b-fork" ]] && pass "cloned workspace exists" || bad "cloned workspace missing"

section "rename"
"$AGENTVM" rename smoke-b-fork smoke-b-renamed >/dev/null && pass "rename succeeded" || bad "rename failed"
[[ -d "$AGENTVM_HOME/workspaces/smoke-b-renamed" ]] && pass "renamed workspace exists" || bad "renamed workspace missing"

section "killall"
"$AGENTVM" killall --force >/dev/null
sleep 1
if "$AGENTVM" list --status running -q | grep -q .; then bad "killall left a running agent"; else pass "killall emptied running set"; fi

section "clean"
sleep 1
"$AGENTVM" clean >/dev/null
remaining="$("$AGENTVM" list -q | wc -l | tr -d ' ')"
[[ "$remaining" == "0" ]] && pass "clean removed dead agents" || bad "clean left dead agents (still: $("$AGENTVM" list -q | tr '\n' ',' ))"

section "completion"
"$AGENTVM" completion bash | grep -q '_agentvm_complete' && pass "bash completion emits" || bad "bash completion broken"
"$AGENTVM" completion zsh  | grep -q '#compdef agentvm'  && pass "zsh completion emits"  || bad "zsh completion broken"

section "run (one-shot)"
out="$("$AGENTVM" run --name smoke-run --timeout 5 -- /bin/sh -c 'echo ONESHOT_OK; exit 0' 2>/dev/null || true)"
echo "$out" | grep -q ONESHOT_OK && pass "run captured output" || bad "run did not capture output: $out"

section "purge"
"$AGENTVM" spawn smoke-purge1 -- /bin/sh -c 'sleep 30' >/dev/null
"$AGENTVM" spawn smoke-purge2 -- /bin/sh -c 'sleep 30' >/dev/null
"$AGENTVM" purge --force >/dev/null
sleep 1
remaining="$("$AGENTVM" list -q | wc -l | tr -d ' ')"
[[ "$remaining" == "0" ]] && pass "purge removed everything" || bad "purge left agents: $("$AGENTVM" list -q | tr '\n' ',')"

if [[ $fail -eq 0 ]]; then
  printf '\n\033[32mALL SMOKE TESTS PASSED\033[0m (tmp: %s)\n' "$TMP"
  exit 0
else
  printf '\n\033[31m%d SMOKE CHECK(S) FAILED\033[0m (tmp kept: %s)\n' "$fail" "$TMP"
  KEEP=true
  exit 1
fi
