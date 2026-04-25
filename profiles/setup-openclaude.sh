#!/usr/bin/env bash
# agentvm workspace setup for OpenClaude profile
#
# Called by agentvm before spawning an openclaude agent. Writes ONLY to the
# per-agent HOME at <workspace>/.home/ — never to the host's ~/.claude/.
#
# Bootstraps minimal config so OpenClaude doesn't show its first-run wizard.
# OpenClaude gates the wizard on (config.theme && config.hasCompletedOnboarding),
# checked against its global config file. That file is, in order of preference:
#   1. $CLAUDE_CONFIG_DIR/.openclaude.json   (new path)
#   2. ~/.claude.json                        (legacy path Claude Code uses)
# We write both so it works regardless of which path resolves.
#
# Files written:
#   - .claude/settings.json         → permission skip flags
#   - .openclaude.json              → theme + hasCompletedOnboarding + folder trust
#   - .claude.json                  → same (legacy fallback)
#
# Usage: setup-openclaude.sh <workspace-path>
set -euo pipefail

WORKSPACE="${1:?Usage: $0 <workspace-path>}"
AGENT_HOME="$WORKSPACE/.home"
mkdir -p "$AGENT_HOME/.claude"

# 1. settings.json — auto permissions, skip prompts
SETTINGS_FILE="$AGENT_HOME/.claude/settings.json"
if [[ ! -f "$SETTINGS_FILE" ]]; then
  cat > "$SETTINGS_FILE" <<'JSON'
{
  "permissions": {
    "defaultMode": "auto"
  },
  "skipDangerousModePermissionPrompt": true,
  "skipAutoPermissionPrompt": true
}
JSON
fi

# 2. Global config — both new (.openclaude.json) and legacy (.claude.json) paths.
#    Sets theme + hasCompletedOnboarding so the first-run wizard is skipped,
#    plus folder-trust for this workspace.
for target in "$AGENT_HOME/.openclaude.json" "$AGENT_HOME/.claude.json"; do
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
