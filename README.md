# ICC

Let Claude Code break through its context window limit by automatically relaying across sessions to complete complex tasks.

## How It Works

### File-Signal Architecture (TTY Mode)

```
supervisor generates a unique path /tmp/icc-handoff-<hex>.md
    | passed to agent via --append-system-prompt
    v
agent works -> context-guard PostToolUse warns -> agent writes handoff file
    |
    v
supervisor polls and detects the file
    | Esc -> /exit to quit
    v
shell prompt returns (claude process exits)
    |
    v
reads handoff file -> generates new path -> starts new claude session
```

### Core Flow

1. **context-guard hook** monitors context consumption after each tool call
2. When the warning threshold is reached, a reminder is injected telling the agent to prepare a handoff
3. When the critical threshold is reached, exploratory tools are blocked, guiding the agent to write a handoff to the designated file
4. **supervisor** detects the handoff file, gracefully exits the current session, and starts a new session to continue

```
Session 1 --> near limit --> writes handoff file
                                |
Session 2 --> near limit --> writes handoff file
                                |
Session 3 --> task complete (no handoff -> supervisor exits)
```

## Installation

```bash
cd ~/code/52/icc
bash install.sh
```

This will:
- Copy `context-guard.sh` to `~/.claude/hooks/`
- Register PreToolUse/PostToolUse hooks in `~/.claude/settings.json`

## Usage

There are two operating modes:

### Pipe Mode (`supervisor.sh`)

Runs via `claude -p` pipe mode, automatically parsing stream-json output. Simple and straightforward, but does not allow manual intervention.

```bash
bash supervisor.sh [OPTIONS] "task description"
```

### TTY Mode (`supervisor-tty.sh`)

Launches a real claude TTY session inside tmux, relaying via file signals. You can attach at any time to observe or intervene manually.

```bash
bash supervisor-tty.sh [OPTIONS] "task description"

# Watch the session in progress
tmux attach -t icc
```

### Options

| Option | Default | Description | Applies To |
|--------|---------|-------------|------------|
| `--model MODEL` | sonnet | Claude model | Both |
| `--max-sessions N` | 10 | Maximum number of relay sessions | Both |
| `--warn-tokens N` | 175000 | Warning threshold | Both |
| `--critical-tokens N` | 190000 | Rejection threshold | Both |
| `--permission-mode MODE` | bypassPermissions | Permission mode | TTY |
| `--session-timeout N` | 600 | Per-session timeout (seconds) | TTY |

The environment variables `CTX_WARN_TOKENS` and `CTX_CRITICAL_TOKENS` also apply.

### Examples

```bash
# Pipe mode - basic usage
bash supervisor.sh "Implement a full Todo API with CRUD and tests"

# Pipe mode - specify model and session count
bash supervisor.sh --model haiku --max-sessions 5 \
  "Write a Python HTTP server with GET/POST endpoints"

# TTY mode - you can attach to observe
bash supervisor-tty.sh --model haiku --max-sessions 5 \
  "Build a REST API with tests"

# Low thresholds to test the relay mechanism
CTX_WARN_TOKENS=5000 CTX_CRITICAL_TOKENS=8000 \
  bash supervisor-tty.sh --model haiku --max-sessions 3 \
  "Create a calculator app with unit tests"
```

## File Descriptions

| File | Purpose |
|------|---------|
| `supervisor.sh` | Pipe mode main loop: `claude -p` -> parse stream-json -> relay |
| `supervisor-tty.sh` | TTY mode main loop: tmux session -> file-signal relay |
| `context-guard.sh` | Hook: PostToolUse reminders / PreToolUse rejection (whitelists handoff path) |
| `install.sh` | Install hooks to `~/.claude/` |
| `lib/core.sh` | Shared infrastructure: config defaults, colors, logging, arg parsing, banners |
| `lib/handoff.sh` | Handoff protocol: system prompt + continuation prompt templates |
| `lib/detect.sh` | Signal detection: polling skeleton + handoff file + shell prompt detection |

## Signal Flow Details

### TTY Mode (File Signals)

1. Supervisor generates a unique path `/tmp/icc-handoff-<hex>.md` for each session
2. The path is communicated to the agent via the `ICC_HANDOFF_PATH` environment variable and `--append-system-prompt`
3. The context-guard hook reminds the agent to write a handoff file at the WARN threshold
4. The context-guard hook rejects tools and guides the agent to write the file at the CRITICAL threshold (whitelisting writes to the handoff path)
5. Supervisor polls `[ -f $HANDOFF_PATH ]` to detect the file
6. Once detected, it sends Esc + `/exit` to gracefully quit claude
7. It reads the handoff file contents and constructs a continuation prompt to start a new session

### Termination Conditions

- **Claude exits naturally with no handoff file** -- task complete, supervisor exits
- **max-sessions reached** -- supervisor exits
- **Session timeout** -- forcibly exits

## Dependencies

- `claude` CLI (installed and logged in)
- `jq`
- `python3`
- `tmux` (required for TTY mode)
- `openssl` (for generating random file names)

## Comparison of the Two Modes

| | Pipe Mode (`supervisor.sh`) | TTY Mode (`supervisor-tty.sh`) |
|---|---|---|
| Execution | `claude -p` pipe | tmux TTY session |
| Manual intervention | Not supported | `tmux attach` at any time |
| Relay signal | stream-json result parsing | File signal (`/tmp/icc-handoff-*.md`) |
| Cost tracking | Yes (real-time) | No |
| Relay method | New process | Esc + /exit -> new process |
| Handoff format | Conversation output | Q0-Q4 file |

## Notes

- Must be run from an external terminal; cannot be nested inside Claude Code
- Hook thresholds can be adjusted based on actual task complexity
- Handoff files are saved at `/tmp/icc-handoff-*.md` and can be reviewed afterward for relay history
- The agent is designed to run fully autonomously and will not ask for human confirmation
