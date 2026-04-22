#!/usr/bin/env bash
# agentvm workspace setup for Codex profile
#
# Called automatically by agentvm before spawning an agent with the codex profile.
# Runs on the host (not inside the sandbox) with full filesystem access.
#
# What it does:
#   1. Pre-accepts the directory trust prompt by adding the workspace path to
#      ~/.codex/config.toml as a trusted project.
#   2. Also writes a workspace-local config (used in gitlawb mode where HOME=<workspace>).
#
# Usage: setup-codex.sh <workspace-path>
set -euo pipefail

WORKSPACE="${1:?Usage: $0 <workspace-path>}"

# Add workspace trust to a codex config.toml
add_trust() {
  local config="$1"
  local workspace="$2"
  python3 - "$config" "$workspace" <<'PYEOF'
import sys, os, re

config_path, workspace = sys.argv[1], sys.argv[2]

# Read existing config or start fresh
content = ""
if os.path.exists(config_path):
    with open(config_path) as f:
        content = f.read()

# Check if this workspace is already trusted
entry = f'[projects."{workspace}"]'
if entry in content:
    sys.exit(0)  # already present, nothing to do

# Append the trust entry
os.makedirs(os.path.dirname(os.path.abspath(config_path)) or ".", exist_ok=True)
with open(config_path, "a") as f:
    f.write(f'\n[projects."{workspace}"]\ntrust_level = "trusted"\n')
PYEOF
}

# 1. Update the host's ~/.codex/config.toml
add_trust "${HOME}/.codex/config.toml" "$WORKSPACE"

# 2. Create a workspace-local codex config (used in gitlawb mode where HOME=<workspace>)
mkdir -p "${WORKSPACE}/.codex"
add_trust "${WORKSPACE}/.codex/config.toml" "$WORKSPACE"
