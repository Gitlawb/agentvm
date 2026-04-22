#!/usr/bin/env bash
# agentvm workspace setup for Gemini CLI profile.
# Called on the host before the sandbox starts. Pre-accepts the directory trust
# prompt by ensuring ~/.gemini/ and <workspace>/.gemini/ exist with a minimal
# settings file.
set -euo pipefail

WORKSPACE="${1:?Usage: $0 <workspace-path>}"

for d in "${HOME}/.gemini" "${WORKSPACE}/.gemini"; do
  mkdir -p "$d"
  # Write a minimal trust settings file if absent
  if [[ ! -f "$d/settings.json" ]]; then
    printf '{"trustedFolders": ["%s"]}\n' "$WORKSPACE" > "$d/settings.json"
  fi
done
