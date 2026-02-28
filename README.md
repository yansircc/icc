# Infinite Claude Code

[![CI](https://github.com/yansircc/icc/actions/workflows/ci.yml/badge.svg)](https://github.com/yansircc/icc/actions/workflows/ci.yml)

Let Claude Code break through its context window limit by automatically relaying across sessions to complete complex tasks.

## How It Works

### File-Signal Architecture (TTY Mode)

```
icc generates a unique path /tmp/icc-handoff-<hex>.md
    | passed to agent via --append-system-prompt
    v
agent works -> context-guard PostToolUse warns -> agent writes handoff file
    |
    v
icc polls and detects the file
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
4. **icc** detects the handoff file, gracefully exits the current session, and starts a new session to continue

```
Session 1 --> near limit --> writes handoff file
                                |
Session 2 --> near limit --> writes handoff file
                                |
Session 3 --> task complete (no handoff -> icc exits)
```

## Installation

### From Release (Recommended)

Download the latest binary from [Releases](https://github.com/yansircc/icc/releases):

```bash
# macOS (Apple Silicon)
curl -Lo icc https://github.com/yansircc/icc/releases/latest/download/icc-darwin-arm64
chmod +x icc && sudo mv icc /usr/local/bin/

# macOS (Intel)
curl -Lo icc https://github.com/yansircc/icc/releases/latest/download/icc-darwin-amd64
chmod +x icc && sudo mv icc /usr/local/bin/

# Linux (amd64)
curl -Lo icc https://github.com/yansircc/icc/releases/latest/download/icc-linux-amd64
chmod +x icc && sudo mv icc /usr/local/bin/
```

### From Source

```bash
go build -o icc .
```

### Setup Hooks

```bash
icc install
```

This will:
- Copy the embedded `context-guard.sh` to `~/.claude/hooks/`
- Register PreToolUse/PostToolUse hooks in `~/.claude/settings.json`

## Usage

```bash
# TTY mode (default) — runs in tmux, you can attach to observe
./icc "Build a REST API with tests"
tmux attach -t icc-a1b2c3   # session name shown at startup

# Pipe mode — simple, no manual intervention
./icc -p "Write a Python HTTP server"

# Multiple concurrent instances (each gets a unique tmux session)
./icc --name proj-a "Task A" &
./icc --name proj-b "Task B" &
```

### Options

| Option | Default | Description | Mode |
|--------|---------|-------------|------|
| `-p` | _(off)_ | Pipe mode (`claude -p`, no tmux) | - |
| `--version`, `-v` | | Print version and exit | - |
| `--model MODEL` | sonnet | Claude model | Both |
| `--max-sessions N` | 10 | Maximum number of relay sessions | Both |
| `--warn-tokens N` | 175000 | Warning threshold | Both |
| `--critical-tokens N` | 190000 | Rejection threshold | Both |
| `--permission-mode MODE` | bypassPermissions | Permission mode | TTY |
| `--session-timeout N` | 600 | Per-session timeout (seconds) | TTY |
| `--name NAME` | icc-\<random\> | tmux session name | TTY |

Environment variables `CTX_WARN_TOKENS` and `CTX_CRITICAL_TOKENS` also work.

### Examples

```bash
# Pipe mode
./icc -p --model haiku --max-sessions 5 \
  "Write a Python HTTP server with GET/POST endpoints"

# TTY mode with custom name
./icc --name my-task --model haiku --max-sessions 5 \
  "Build a REST API with tests"

# Low thresholds to test the relay mechanism
CTX_WARN_TOKENS=5000 CTX_CRITICAL_TOKENS=8000 \
  ./icc --model haiku --max-sessions 3 \
  "Create a calculator app with unit tests"
```

## File Descriptions

| File | Purpose |
|------|---------|
| `main.go` | Entry point: CLI parsing, env overrides, `install` subcommand, dispatch |
| `install.go` | `icc install`: embed + deploy hook script, register in settings.json |
| `log.go` | ANSI colors, timestamped logging, session header/finish banner |
| `prompt.go` | Handoff protocol: system prompt + continuation prompt templates |
| `pipe.go` | Pipe mode: `claude -p` stream-json session loop, cost tracking |
| `tty.go` | TTY mode: tmux session management, prompt sending |
| `detect.go` | Signal detection: polling, shell prompt detection, graceful exit |
| `context-guard.sh` | Hook source (embedded into binary via `go:embed`) |
| `e2e.sh` | End-to-end tests: `bash e2e.sh [pipe\|tty\|all]` |

## Signal Flow Details

### TTY Mode (File Signals)

1. ICC generates a unique path `/tmp/icc-handoff-<hex>.md` and tmux session `icc-<hex>` for each run
2. The path is communicated to the agent via `ICC_HANDOFF_PATH` env var and `--append-system-prompt`
3. The context-guard hook reminds the agent to write a handoff file at the WARN threshold
4. The context-guard hook rejects tools and guides the agent to write the file at the CRITICAL threshold (whitelisting writes to the handoff path)
5. ICC polls `[ -f $HANDOFF_PATH ]` to detect the file
6. Once detected, it sends Esc + `/exit` to gracefully quit claude
7. It reads the handoff file contents and constructs a continuation prompt to start a new session

### Termination Conditions

- **Claude exits naturally with no handoff file** -- task complete, ICC exits
- **max-sessions reached** -- ICC exits
- **Session timeout** -- forcibly exits

## Dependencies

- `claude` CLI (installed and logged in)
- `tmux` (required for TTY mode)
- `jq` (required by `context-guard.sh` hook)

## Comparison of the Two Modes

| | Pipe Mode (`-p`) | TTY Mode (default) |
|---|---|---|
| Execution | `claude -p` pipe | tmux TTY session |
| Manual intervention | Not supported | `tmux attach` at any time |
| Relay signal | stream-json result parsing | File signal (`/tmp/icc-handoff-*.md`) |
| Cost tracking | Yes (real-time) | No |
| Relay method | New process | Esc + /exit -> new process |
| Handoff format | Conversation output | Q0-Q4 file |
| Concurrent instances | N/A | Unique session per `--name` |

## Notes

- Must be run from an external terminal; cannot be nested inside Claude Code
- Hook thresholds can be adjusted based on actual task complexity
- Handoff files are saved at `/tmp/icc-handoff-*.md` and can be reviewed afterward for relay history
- The agent is designed to run fully autonomously and will not ask for human confirmation
- **`CLAUDE_BIN`**: icc finds the `claude` binary via `exec.LookPath`, which ignores shell aliases and functions. If you use a wrapper (e.g. [ccc](https://github.com/anthropics/claude-code)) that injects API keys or provider config, set `CLAUDE_BIN` to point to it, otherwise claude may fail with 401:
  ```bash
  export CLAUDE_BIN=/path/to/your/wrapper
  ```
