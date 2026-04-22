# agentvm

Spawn and manage isolated AI-agent workspaces from the terminal. Like Docker, but pure shell — no daemon, no container runtime.

Each agent gets its own workspace directory and a dedicated tmux session. Output is persisted to a log file; the sandbox is applied automatically based on your OS:

- **macOS** — `sandbox-exec` (Seatbelt): deny-by-default filesystem policy; agents can only write to their workspace, `/tmp`, and their agent-config dirs
- **Linux** — `bwrap` (bubblewrap): unshared PID/IPC/UTS namespaces; workspace bind-mounted to `/workspace`
- **Fallback** — unrestricted shell in workspace directory (with a warning)

Supports **Claude Code**, **OpenAI Codex**, **Gemini CLI**, **Aider**, or any custom binary. Each agent can hold its own [gitlawb](https://gitlawb.com) DID for decentralized identity.

---

## Requirements

| Requirement | macOS | Linux |
|---|---|---|
| bash ≥ 3.2 | ✓ (built-in) | ✓ |
| tmux | `brew install tmux` | `apt install tmux` |
| sandbox-exec | built-in (macOS 10.5+) | — |
| bwrap | — | `apt install bubblewrap` |

---

## Installation

```sh
git clone <repo> ~/.local/share/agentvm
ln -sf ~/.local/share/agentvm/agentvm ~/.local/bin/agentvm

# Optional: enable shell completion
agentvm completion bash > ~/.local/share/bash-completion/completions/agentvm
agentvm completion zsh  > ~/.zsh/completions/_agentvm    # save anywhere on $fpath
```

Sanity-check your environment:

```sh
agentvm doctor
```

---

## Quick Start

```sh
# 1. Set up your API keys once (stored in ~/.agentvm/env, chmod 600)
agentvm env set ANTHROPIC_API_KEY=sk-ant-...
agentvm env set OPENAI_API_KEY=sk-proj-...

# 2. Spawn an agent
agentvm spawn c1 -p claude-code

# 3. Send it a prompt (or attach to its tmux session)
agentvm exec c1 "write a hello-world in rust"
agentvm logs c1 -f          # tail its output
agentvm attach c1           # hop into its pane
```

---

## Commands

### Lifecycle

| Command | Description |
|---|---|
| `agentvm spawn <name> [-p <profile>] [--gitlawb] [--prompt <file>] [-t K=V]... [--from-dir <path>\|--from-git <url> [--ref <ref>]] [-- cmd...]` | Create workspace and start a sandboxed tmux session |
| `agentvm run [-p <profile>] [--prompt <file>] [--timeout <s>] [--keep] [-- cmd...]` | Ephemeral one-shot: spawn → wait → print logs → cleanup |
| `agentvm swarm <base> <n> [-p <profile>] [--prompt <file>] [-t K=V]...` | Spawn N agents named `<base>-1 .. <base>-N` |
| `agentvm restart <name>` | Restart an agent reusing its stored profile/prompt/tags/command |
| `agentvm clone <src> <dst>` | Copy workspace to a new agent (dead; use `restart` to start) |
| `agentvm rename <old> <new>` | Rename agent (workspace, session, logs, SB profile) |

### Observe

| Command | Description |
|---|---|
| `agentvm list [--tag K=V] [--status running\|dead] [-q\|--json]` | List agents with status, PID, profile, tags |
| `agentvm ps [--all] [--json]` | Resource usage (CPU%, MEM%, RSS, uptime) |
| `agentvm info <name> [--json]` | Detailed info including DID, prompt file, log size |
| `agentvm stats` | Aggregate counts + workspace/log byte sizes |
| `agentvm history [-n <lines>] [-e <event>]` | Lifecycle journal (spawn/kill/clean/purge) |
| `agentvm diff <name>` | Files changed in workspace since spawn (git-aware) |
| `agentvm grid` | Open a single tmux session with one window per running agent |
| `agentvm open <name>` | Open workspace in OS file manager |
| `agentvm logs <name> [-n <lines>] [-f] [--raw]` | Tail the persistent log file (ANSI stripped by default) |
| `agentvm watch [-n <seconds>]` | Live dashboard: ps + last-3-lines tail of every running agent |
| `agentvm attach <name>` | Attach to agent's tmux session |
| `agentvm exec <name> [--file <f>] [--no-enter] <cmd...>` | Send keystrokes (or file contents) to agent's pane |
| `agentvm send <name> <file>` | Shorthand for `exec <name> --file <file>` |
| `agentvm broadcast [--tag K=V] <cmd...>` | Send a command to every running agent (optionally filtered) |
| `agentvm wait <name> [--timeout <s>]` | Block until the agent session exits |

### Manage

| Command | Description |
|---|---|
| `agentvm kill <name>` | Kill one agent's tmux session |
| `agentvm killall [--tag K=V] [--force]` | Kill all running agents (optionally filtered) |
| `agentvm clean` | Remove workspaces and state for DEAD agents |
| `agentvm purge [--force]` | Kill and remove ALL agents (asks confirmation) |

### Configure

| Command | Description |
|---|---|
| `agentvm profiles` | List available profiles |
| `agentvm keys` | Show API-key status for every profile |
| `agentvm env {list\|get\|set\|unset\|edit\|path}` | Manage `~/.agentvm/env` (chmod 600) |
| `agentvm doctor` | Diagnose tmux, sandbox backend, profile binaries, env perms |
| `agentvm completion <bash\|zsh>` | Emit shell-completion script |
| `agentvm upgrade` | `git pull` the install directory |
| `agentvm root` | Print `$AGENTVM_HOME` |
| `agentvm version` | Print version |
| `agentvm help` | Full help |

---

## Profiles

A profile describes how to spawn a particular agent: its default command, extra sandbox mounts, and which env vars to forward into the sandbox.

| Profile | Binary | Required env |
|---|---|---|
| `claude-code` | `claude` | `ANTHROPIC_API_KEY` |
| `codex` | `codex` | `OPENAI_API_KEY` |
| `gemini` | `gemini` | `GEMINI_API_KEY` or `GOOGLE_API_KEY` |
| `aider` | `aider` | at least one LLM provider key |

Create your own as `profiles/<name>.env` — see the existing files for the schema.

```sh
# profiles/my-profile.env
PROFILE_LABEL="My Agent"
PROFILE_CMD="my-agent --auto"
PROFILE_RO_PATHS="${HOME}/.local/bin"         # : separated
PROFILE_RW_PATHS="${HOME}/.my-agent"          # : separated
PROFILE_ENV_VARS="MY_API_KEY:MY_BASE_URL"     # : separated
PROFILE_POST_CREATE_SCRIPT="$SCRIPT_DIR/profiles/setup-my-profile.sh"
```

---

## Cookbook

### Send a pre-written task to an agent at spawn time

```sh
cat > /tmp/task.md <<'EOF'
Read the repo. Summarize what it does in 5 bullets. Write the summary to SUMMARY.md.
EOF

agentvm spawn reviewer -p claude-code --prompt /tmp/task.md -t task=review
```

The prompt file is typed into the agent's pane (literal keystrokes, so special chars survive). It's also stored in state so `agentvm restart reviewer` replays it.

### Parallel exploration (swarm)

```sh
# 5 independent workers, each with the same prompt but their own workspace + DID
agentvm swarm crawler 5 -p claude-code --gitlawb --prompt /tmp/crawl.md
agentvm watch
agentvm logs crawler-3 -f
```

### One-shot CI runs

```sh
# Spawn, run, capture, clean — exits with the agent's final log on stdout
agentvm run -p codex --timeout 600 --prompt /tmp/ci-task.md
```

Use `--keep` if you want to inspect the workspace afterward.

### Tag-based bulk ops

```sh
agentvm spawn w1 -p claude-code -t env=staging
agentvm spawn w2 -p claude-code -t env=staging
agentvm spawn w3 -p codex       -t env=prod

agentvm list --tag env=staging
agentvm broadcast --tag env=staging "git pull"
agentvm killall  --tag env=staging --force
```

### Clone a workspace to branch work

```sh
agentvm clone reviewer reviewer-experiment
agentvm restart reviewer-experiment
```

### Run an agent against an existing project

```sh
# copy a local dir into the workspace
agentvm spawn refactor -p claude-code --from-dir ~/Projects/my-app --prompt /tmp/task.md

# or clone a git repo at a specific ref
agentvm spawn trial -p claude-code --from-git https://github.com/foo/bar --ref main
```

### Inspect what an agent changed

```sh
agentvm diff refactor     # shows `git status -s` + `git diff HEAD` if workspace is a git repo
                          # falls back to find-newer-than-spawn-time for non-git workspaces
```

### Identity-per-agent (decentralized)

```sh
agentvm spawn claude-1 -p claude-code --gitlawb
# Provisions an Ed25519 DID in workspace/.gitlawb/, registers with the node,
# then HOME inside the sandbox is redirected to the workspace so the agent
# signs commits with its own key.
```

---

## File layout

```
$AGENTVM_HOME/               # default: ~/.agentvm
├── env                      # API keys (chmod 600, sourced automatically)
├── config                   # shell-level defaults (AGENTVM_DEFAULT_PROFILE, etc.)
├── history.log              # lifecycle journal (tab-separated)
├── hooks/                   # optional user scripts:
│   ├── pre-spawn            #   runs before session starts:  $1=name $2=workspace
│   └── post-spawn           #   runs after session starts
├── workspaces/
│   └── <name>/              # agent's private read-write workspace
└── state/
    ├── <name>.env           # metadata: pid, profile, tags, prompt file, etc.
    ├── <name>.sb            # generated Seatbelt profile (macOS only)
    └── <name>.log           # persistent pane output (tmux pipe-pane)

agentvm/                     # this repo
├── agentvm                  # main CLI script
├── profiles/                # claude-code.env, codex.env, gemini.env, aider.env, ...
├── sandbox/
│   ├── macos.sb.tmpl        # Seatbelt template (__WORKSPACE__/__AGENTVM_HOME__ placeholders)
│   └── linux.sh             # bubblewrap wrapper
└── tests/smoke.sh           # end-to-end smoke test
```

---

## How it works

### Spawning

1. A workspace directory is created at `$AGENTVM_HOME/workspaces/<name>/`
2. The profile's `PROFILE_POST_CREATE_SCRIPT` runs on the host (pre-accepts trust dialogs, writes settings)
3. If `--gitlawb`, a fresh Ed25519 DID is generated and registered; `HOME` inside the sandbox is redirected to the workspace
4. A sandbox wrapper command is built (macOS: `.sb` profile + `sandbox-exec`; Linux: `bwrap`)
5. A detached tmux session `agentvm-<name>` is started; `tmux pipe-pane` persists output to `state/<name>.log`
6. Metadata is saved to `state/<name>.env`
7. If `--prompt FILE` was given, the file's contents are typed into the pane after a short startup delay

### Filesystem isolation

On macOS, the Seatbelt profile allows reads globally (Claude Code / Codex touch too many system paths to enumerate) but restricts writes to:
- the agent's workspace
- `/tmp`, `/private/tmp`, `/var/folders` (system temp dirs)
- `/dev` (shells routinely write to `/dev/null`)
- `$AGENTVM_HOME` (so an agent can itself spawn sub-agents — meta-agent pattern)
- paths listed in the profile's `PROFILE_RW_PATHS` (e.g. `~/.claude`, `~/.codex`)

On Linux, `bwrap` binds system paths read-only, tmpfs's `/tmp`, and binds the workspace at `/workspace`.

### Logs

Every spawned session is piped to `$AGENTVM_STATE/<name>.log` via `tmux pipe-pane`. This means:

- `agentvm logs <name> -f` is a plain `tail -f` on a file — robust and scriptable
- The log survives after the session dies; `agentvm clean` removes it
- ANSI escape sequences are stripped by default; pass `--raw` to keep them

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `AGENTVM_HOME` | `~/.agentvm` | Root directory for workspaces, state, env file |
| `AGENTVM_DEFAULT_PROFILE` | (unset) | Used when `spawn` is called without `--profile`. Can be set in `$AGENTVM_HOME/config`. |
| `EDITOR` / `VISUAL` | `vi` | Used by `agentvm env edit` |

---

## Testing

```sh
./tests/smoke.sh        # end-to-end smoke test in an isolated AGENTVM_HOME
./tests/smoke.sh --keep # keep the tmp dir for inspection on failure
```

The smoke test exercises every major command (spawn, list, info, logs, exec, ps, tags, clone, rename, killall, clean, run, purge, completion).

---

## Background

This tool was built while researching how to sandbox AI agents in the terminal. The core idea is to give each agent:

1. An isolated filesystem scope (the only place it can write)
2. A dedicated tmux session (observable, attachable, killable)
3. A persistent log (scriptable, tailable, survives crashes)
4. A clean environment (no host `PATH` contamination on Linux)
5. Optional per-agent identity (gitlawb DID) for decentralized provenance

The approach mirrors what Anthropic's [`sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime) does internally for Claude Code on macOS and Linux, but packaged as a shell script you can use with any agent or process — and with first-class multi-agent ergonomics (swarm, broadcast, watch, tags).

Related projects: [E2B](https://e2b.dev) · [microsandbox](https://microsandbox.dev) · [bubblewrap](https://github.com/containers/bubblewrap) · [landrun](https://github.com/Zouuup/landrun)
