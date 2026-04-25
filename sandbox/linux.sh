#!/usr/bin/env bash
# agentvm Linux bubblewrap sandbox wrapper
#
# Usage: linux.sh <workspace_path> [cmd [args...]]
#
# Environment variables (set by agentvm):
#   AGENTVM_EXTRA_RO_PATHS  Colon-separated extra read-only bind mounts
#   AGENTVM_EXTRA_RW_PATHS  Colon-separated extra read-write bind mounts
#
# Provider env vars (ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, …)
# are inherited from the parent process — bwrap does not --clearenv.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <workspace_path> [cmd [args...]]" >&2
  exit 1
fi

WORKSPACE="$1"
shift

if [[ $# -eq 0 ]]; then
  set -- /bin/bash
fi

if [[ ! -d "$WORKSPACE" ]]; then
  echo "error: workspace directory does not exist: $WORKSPACE" >&2
  exit 1
fi

AGENT_HOME="$WORKSPACE/.home"
mkdir -p "$AGENT_HOME"

# ---------------------------------------------------------------------------
# Build bwrap arguments
# ---------------------------------------------------------------------------
BWRAP_ARGS=()

# --- Namespace flags ---
BWRAP_ARGS+=(
  --unshare-user
  --unshare-pid
  --unshare-ipc
  --unshare-uts
  # --unshare-net is intentionally omitted: keep host networking
)

# --- UID/GID mapping ---
BWRAP_ARGS+=(
  --uid 1000
  --gid 1000
)

# --- Read-only system paths (only bind those that exist) ---
bind_ro_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    BWRAP_ARGS+=(--ro-bind "$path" "$path")
  fi
}

bind_ro_if_exists /usr
bind_ro_if_exists /bin
bind_ro_if_exists /sbin
bind_ro_if_exists /lib
bind_ro_if_exists /lib32
bind_ro_if_exists /lib64
bind_ro_if_exists /libx32
bind_ro_if_exists /etc
bind_ro_if_exists /run/resolvconf   # DNS on some distros

# --- Profile extra read-only paths ---
if [[ -n "${AGENTVM_EXTRA_RO_PATHS:-}" ]]; then
  IFS=':' read -ra _extra_ro <<< "$AGENTVM_EXTRA_RO_PATHS"
  for _p in "${_extra_ro[@]}"; do
    [[ -n "$_p" ]] && bind_ro_if_exists "$_p"
  done
fi

# --- Profile extra read-write paths ---
if [[ -n "${AGENTVM_EXTRA_RW_PATHS:-}" ]]; then
  IFS=':' read -ra _extra_rw <<< "$AGENTVM_EXTRA_RW_PATHS"
  for _p in "${_extra_rw[@]}"; do
    if [[ -n "$_p" && -e "$_p" ]]; then
      BWRAP_ARGS+=(--bind "$_p" "$_p")
    fi
  done
fi

# --- Writable agent workspace (bound at its real host path so HOME paths
#     match inside and outside the sandbox — important for per-agent HOME). ---
BWRAP_ARGS+=(--bind "$WORKSPACE" "$WORKSPACE")

# --- Ephemeral filesystems ---
BWRAP_ARGS+=(
  --tmpfs  /tmp
  --proc   /proc
  --dev    /dev
)

# --- Hostname ---
BWRAP_ARGS+=(--hostname agentvm)

# --- Working directory ---
BWRAP_ARGS+=(--chdir "$WORKSPACE")

# --- New session ---
BWRAP_ARGS+=(--new-session)

# --- Base environment ---
BWRAP_ARGS+=(
  --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  --setenv HOME "$AGENT_HOME"
  --setenv TERM "${TERM:-xterm-256color}"
  --setenv LANG "${LANG:-C.UTF-8}"
)

# ---------------------------------------------------------------------------
# Execute
# ---------------------------------------------------------------------------
exec bwrap "${BWRAP_ARGS[@]}" -- "$@"
