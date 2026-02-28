#!/bin/bash
# supervisor-tty.sh — ICC main loop in tmux mode
# File-signal architecture: agent writes handoff file → supervisor detects → relays to new session
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/handoff.sh"
source "$SCRIPT_DIR/lib/detect.sh"

# ─── TTY-specific configuration ───
PERMISSION_MODE="${PERMISSION_MODE:-bypassPermissions}"
SESSION_TIMEOUT="${SESSION_TIMEOUT:-600}"

# ─── Argument parsing ───
TASK=""
while [[ $# -gt 0 ]]; do
    if handle_common_arg "$1" "${2:-}"; then shift 2; continue; fi
    case "$1" in
        --permission-mode)  PERMISSION_MODE="$2"; shift 2 ;;
        --session-timeout)  SESSION_TIMEOUT="$2"; shift 2 ;;
        --help|-h)
            cat <<'USAGE'
Usage: supervisor-tty.sh [OPTIONS] "TASK DESCRIPTION"

Runs claude in a tmux TTY session with automatic file-signal relay.
Agent writes a handoff file when context is full → supervisor detects → starts new session.
You can attach to the tmux session to observe or intervene.

Options:
  --model MODEL            Claude model (default: sonnet)
  --max-sessions N         Max relay sessions (default: 10)
  --warn-tokens N          Context warning threshold (default: 175000)
  --critical-tokens N      Context deny threshold (default: 190000)
  --permission-mode MODE   Permission mode (default: bypassPermissions)
  --session-timeout N      Per-session timeout in seconds (default: 600)

Example:
  bash supervisor-tty.sh --model haiku --max-sessions 5 \
    "Build a REST API with tests"

  # Observe: tmux attach -t icc
USAGE
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            TASK="$1"; shift ;;
    esac
done

if [[ -z "$TASK" ]]; then
    echo "Error: no task provided." >&2
    exit 1
fi

# ─── tmux helpers ───
TMUX_SESSION="icc"
PANE="${TMUX_SESSION}:0.0"

send_prompt() {
    local tmpfile
    tmpfile=$(mktemp)
    printf '%s' "$1" > "$tmpfile"
    tmux load-buffer "$tmpfile"
    tmux paste-buffer -p -t "$PANE"
    rm -f "$tmpfile"
    sleep 0.3
    tmux send-keys -t "$PANE" Enter
}

# ─── Clean up old session ───
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
echo -e "${BOLD}${BLUE}  ICC (tmux file-signal mode)${RESET}"
echo -e "  Model: ${MODEL}"
echo -e "  Max sessions: ${MAX_SESSIONS}"
echo -e "  Session timeout: ${SESSION_TIMEOUT}s"
echo -e "  Attach: ${BOLD}tmux attach -t ${TMUX_SESSION}${RESET}"
echo -e "${BOLD}${BLUE}══════════════════════════════════════════${RESET}"

# ─── Start tmux ───
tmux new-session -d -s "$TMUX_SESSION" -x 200 -y 50
sleep 1

# ─── Main loop ───
PREV_HANDOFF_PATH=""

for (( i=1; i<=MAX_SESSIONS; i++ )); do
    print_session_header "$i"

    # Generate unique handoff path
    HEX=$(openssl rand -hex 3)
    HANDOFF_PATH="/tmp/icc-handoff-${HEX}.md"
    export ICC_HANDOFF_PATH="$HANDOFF_PATH"

    # Build system prompt (including handoff path)
    SYSPROMPT=$(render_system_prompt "$HANDOFF_PATH")
    SYSPROMPT_FILE=$(mktemp /tmp/icc-sp-XXXXX)
    printf '%s' "$SYSPROMPT" > "$SYSPROMPT_FILE"

    # Start claude
    log "Starting claude session..."
    tmux send-keys -t "$PANE" "unset CLAUDECODE && ICC_HANDOFF_PATH='${HANDOFF_PATH}' CTX_WARN_TOKENS=${CTX_WARN_TOKENS} CTX_CRITICAL_TOKENS=${CTX_CRITICAL_TOKENS} claude --model ${MODEL} --permission-mode ${PERMISSION_MODE} --append-system-prompt \"\$(cat ${SYSPROMPT_FILE})\"" Enter

    # Wait for claude to be ready
    if ! wait_for_claude_ready "$PANE" 60; then
        err "Claude did not start in time"
        rm -f "$SYSPROMPT_FILE"
        break
    fi
    ok "Claude ready"

    # Build and send user prompt
    if [[ $i -eq 1 ]]; then
        PROMPT="$TASK"
    else
        PROMPT=$(build_continuation_prompt "$i" "$TASK" "$PREV_HANDOFF_PATH")
    fi

    log "Sending prompt..."
    send_prompt "$PROMPT"

    # Wait for signal: handoff file appears OR claude exits naturally
    log "Waiting for signal (handoff file or claude exit)..."
    wait_for_signal "$HANDOFF_PATH" "$PANE" "$SESSION_TIMEOUT" && SIGNAL=0 || SIGNAL=$?

    rm -f "$SYSPROMPT_FILE"

    case $SIGNAL in
        0)
            ok "Session $i: handoff file detected at $HANDOFF_PATH"
            log "Handoff content preview:"
            head -5 "$HANDOFF_PATH" | sed 's/^/  /'

            log "Gracefully exiting claude..."
            graceful_exit "$PANE" 30
            ok "Claude exited"

            PREV_HANDOFF_PATH="$HANDOFF_PATH"

            if (( i >= MAX_SESSIONS )); then
                log "Reached max sessions ($MAX_SESSIONS)"
                break
            fi
            sleep 2
            ;;
        1)
            if [[ -f "$HANDOFF_PATH" ]]; then
                ok "Session $i: claude exited with handoff"
                PREV_HANDOFF_PATH="$HANDOFF_PATH"
                if (( i >= MAX_SESSIONS )); then
                    log "Reached max sessions ($MAX_SESSIONS)"
                    break
                fi
                sleep 2
            else
                echo -e "\n${GREEN}${BOLD}✓ Session $i: claude exited without handoff — task likely complete${RESET}"
                break
            fi
            ;;
        2)
            err "Session $i timed out (${SESSION_TIMEOUT}s)"
            log "Force-exiting claude..."
            graceful_exit "$PANE" 15
            break
            ;;
    esac
done

# ─── Cleanup ───
print_finish_banner "$i" \
    "Handoff files: ls /tmp/icc-handoff-*.md" \
    "Attach: tmux attach -t ${TMUX_SESSION}" \
    "Cleanup: tmux kill-session -t ${TMUX_SESSION}"
