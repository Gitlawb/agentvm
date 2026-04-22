#!/usr/bin/env bash
# agentvm workspace setup for Claude Code profile
#
# Called automatically by agentvm before spawning an agent with the claude-code
# profile. Runs on the host (not inside the sandbox) with full filesystem access.
#
# What it does:
#   1. Creates <workspace>/.claude/settings.json with skipDangerousModePermissionPrompt=true
#      so Claude Code skips the "--dangerously-skip-permissions" confirmation prompt.
#   2. Sets skipDangerousModePermissionPrompt=true in ~/.claude/settings.json (global),
#      which is what Claude Code actually reads for this setting.
#   3. Pre-accepts the folder trust dialog in ~/.claude.json and <workspace>/.claude.json
#      (the latter is used in gitlawb mode where HOME=<workspace>).
#
# Usage: setup-claude-code.sh <workspace-path>
set -euo pipefail

WORKSPACE="${1:?Usage: $0 <workspace-path>}"

# 1. Create project-local settings (referenced in gitlawb mode where HOME=workspace)
mkdir -p "$WORKSPACE/.claude"
printf '{"skipDangerousModePermissionPrompt": true}\n' > "$WORKSPACE/.claude/settings.json"

# 2. Set skipDangerousModePermissionPrompt in global ~/.claude/settings.json
#    (Claude Code reads this from the user's global config, not the project dir)
python3 - "${HOME}/.claude/settings.json" <<'PYEOF'
import json, os, sys
target = sys.argv[1]
d = {}
if os.path.exists(target):
    try:
        with open(target) as f:
            d = json.load(f)
    except Exception:
        pass
d["skipDangerousModePermissionPrompt"] = True
with open(target, "w") as f:
    json.dump(d, f, indent=2)
PYEOF

# 3. Pre-accept folder trust dialog.
#    Update both the host's ~/.claude.json AND <workspace>/.claude.json so it
#    works regardless of whether HOME is overridden (gitlawb mode).
for target in "${HOME}/.claude.json" "${WORKSPACE}/.claude.json"; do
  python3 - "$target" "$WORKSPACE" <<'PYEOF'
import json, os, sys
target, workspace = sys.argv[1], sys.argv[2]
d = {}
if os.path.exists(target):
    try:
        with open(target) as f:
            d = json.load(f)
    except Exception:
        pass
d.setdefault("projects", {}).setdefault(workspace, {})["hasTrustDialogAccepted"] = True
os.makedirs(os.path.dirname(os.path.abspath(target)) or ".", exist_ok=True)
with open(target, "w") as f:
    json.dump(d, f, indent=2)
PYEOF
done
