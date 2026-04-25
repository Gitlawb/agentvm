#!/usr/bin/env bash
# agentvm workspace setup for Claude Code profile
#
# Called by agentvm before spawning a claude-code agent. Runs on the host with
# full filesystem access, but writes ONLY to the per-agent HOME at
# <workspace>/.home/ — never to the host's ~/.claude/.
#
# Bootstraps minimal config so Claude Code skips first-run wizards:
#   - .claude/settings.json  → skip dangerous-mode + auto-perm prompts
#   - .claude.json           → hasCompletedOnboarding=true + folder trust accepted
#
# Usage: setup-claude-code.sh <workspace-path>
set -euo pipefail

WORKSPACE="${1:?Usage: $0 <workspace-path>}"
AGENT_HOME="$WORKSPACE/.home"
mkdir -p "$AGENT_HOME/.claude"

# 1. settings.json — set skip flags. If the host's settings.json was seeded
#    into the agent home, merge into it; otherwise write fresh.
SETTINGS_FILE="$AGENT_HOME/.claude/settings.json"
python3 - "$SETTINGS_FILE" <<'PYEOF'
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
d["skipAutoPermissionPrompt"] = True
d.setdefault("permissions", {})["defaultMode"] = "auto"
with open(target, "w") as f:
    json.dump(d, f, indent=2)
PYEOF

# 2. Global config — write to both .claude.json (Claude Code's path) and
#    .openclaude.json (OpenClaude's preferred path) so running openclaude
#    inside a claude-code agent also lands at the chat prompt without a wizard.
#    Sets theme + hasCompletedOnboarding + folder trust.
for target in "$AGENT_HOME/.claude.json" "$AGENT_HOME/.openclaude.json"; do
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
d["theme"] = "dark"
d["hasCompletedOnboarding"] = True
d.setdefault("projects", {}).setdefault(workspace, {})["hasTrustDialogAccepted"] = True
with open(target, "w") as f:
    json.dump(d, f, indent=2)
PYEOF
done
