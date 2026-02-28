#!/bin/bash
# e2e.sh — End-to-end tests for ICC (pipe mode + TTY mode)
# Usage: bash e2e.sh [pipe|tty|all]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Colors & logging ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${RESET} $*"; }
ok()   { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
err()  { echo -e "${RED}${BOLD}✗${RESET} $*"; }
skip() { echo -e "${YELLOW}⊘${RESET} $*"; }

PASS=0
FAIL=0

assert() {
    local desc="$1"
    if eval "$2"; then
        ok "$desc"; (( PASS++ )) || true
    else
        err "$desc"; (( FAIL++ )) || true
    fi
}

# ─── Pipe mode e2e ───
test_pipe() {
    echo -e "\n${BOLD}${BLUE}━━━ Pipe Mode E2E ━━━${RESET}\n"

    local output
    local tmpdir="/tmp/icc-test-pipe-$$"
    rm -rf "$tmpdir"

    log "Running icc -p (max-sessions=2, low thresholds)..."
    output=$(CTX_WARN_TOKENS=5000 CTX_CRITICAL_TOKENS=8000 \
        "$SCRIPT_DIR/icc" -p \
            --model haiku --max-sessions 2 \
            "Create a directory $tmpdir and write a Python hello.py that prints HELLO_ICC" \
        2>&1) || true

    assert "icc -p produced output" '[[ -n "$output" ]]'
    assert "Session 1 started" 'echo "$output" | grep -q "Session 1"'
    assert "Finish banner appeared" 'echo "$output" | grep -q "ICC Finished"'
    assert "Task produced artifacts ($tmpdir/hello.py)" '[[ -f "$tmpdir/hello.py" ]]'

    rm -rf "$tmpdir"

    echo ""
    log "Pipe mode output (last 10 lines):"
    echo "$output" | tail -10 | sed 's/^/  /'
}

# ─── TTY mode e2e ───
# Strategy: start icc in background, wait for Claude to be ready,
# then inject a handoff file externally to test the relay mechanism.
# This tests ICC's plumbing (detect file → exit claude → start session 2),
# not Claude's ability to complete tasks.
test_tty() {
    echo -e "\n${BOLD}${BLUE}━━━ TTY Mode E2E ━━━${RESET}\n"

    if ! command -v tmux &>/dev/null; then
        skip "tmux not found, skipping TTY test"
        return
    fi

    local logfile="/tmp/icc-e2e-tty-$$.log"
    local session_name="icc-e2e-$$"
    rm -f /tmp/icc-handoff-*.md

    tmux kill-session -t "$session_name" 2>/dev/null || true

    log "Starting icc in background (max-sessions=2, timeout=120s)..."
    "$SCRIPT_DIR/icc" \
        --name "$session_name" \
        --model haiku --max-sessions 2 --session-timeout 120 \
        "Print hello world" \
        > "$logfile" 2>&1 &
    local icc_pid=$!

    # Wait for Claude to be ready (poll the log for "Claude ready")
    local waited=0
    while ! grep -q "Claude ready" "$logfile" 2>/dev/null; do
        sleep 2
        waited=$(( waited + 2 ))
        if (( waited > 60 )); then
            err "Claude did not start within 60s"
            kill "$icc_pid" 2>/dev/null || true
            cat "$logfile" | tail -10 | sed 's/^/  /'
            rm -f "$logfile"
            tmux kill-session -t "$session_name" 2>/dev/null || true
            return
        fi
    done
    ok "Claude ready (${waited}s)"

    # Find the handoff path ICC is waiting for (from the log)
    local handoff_path
    handoff_path=$(grep -o "/tmp/icc-handoff-[a-f0-9]*.md" "$logfile" | head -1)
    assert "Handoff path found in log" '[[ -n "$handoff_path" ]]'

    if [[ -n "$handoff_path" ]]; then
        # Inject a fake handoff file to trigger the relay
        log "Injecting handoff file: $handoff_path"
        cat > "$handoff_path" << 'HANDOFF'
## Q0: What is the current state of this project?
E2E test: injected handoff to verify ICC relay mechanism.

## Q1: What should the next agent do first?
Print "relay verified" to confirm session 2 received the handoff.
HANDOFF

        # Wait for ICC to detect the file and start session 2
        local relay_waited=0
        while ! grep -q "Session 2" "$logfile" 2>/dev/null; do
            sleep 2
            relay_waited=$(( relay_waited + 2 ))
            if (( relay_waited > 90 )); then
                break
            fi
        done
    fi

    # Gracefully exit claude: Esc, type /exit literally, wait for autocomplete, Enter
    sleep 5
    local pane="${session_name}:0.0"
    tmux send-keys -t "$pane" Escape 2>/dev/null || true
    sleep 0.5
    tmux send-keys -t "$pane" -l "/exit" 2>/dev/null || true
    sleep 2
    tmux send-keys -t "$pane" Enter 2>/dev/null || true

    # Wait for icc to finish naturally
    wait "$icc_pid" 2>/dev/null || true

    local output
    output=$(cat "$logfile")

    assert "icc (TTY) produced output" '[[ -n "$output" ]]'
    assert "Session 1 started" 'echo "$output" | grep -q "Session 1"'
    assert "Handoff detected" 'echo "$output" | grep -q "handoff"'
    assert "Session 2 started (relay occurred)" 'echo "$output" | grep -q "Session 2"'
    assert "Finish banner appeared" 'echo "$output" | grep -q "ICC Finished"'

    rm -f "$logfile"
    tmux kill-session -t "$session_name" 2>/dev/null || true

    echo ""
    log "TTY mode output (last 15 lines):"
    echo "$output" | tail -15 | sed 's/^/  /'
}

# ─── Main ───
MODE="${1:-all}"

echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
echo -e "${BOLD}${BLUE}  ICC End-to-End Tests${RESET}"
echo -e "${BOLD}${BLUE}══════════════════════════════════════════${RESET}"

case "$MODE" in
    pipe)  test_pipe ;;
    tty)   test_tty ;;
    all)   test_pipe; test_tty ;;
    *)     echo "Usage: bash e2e.sh [pipe|tty|all]" >&2; exit 1 ;;
esac

# ─── Summary ───
echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
TOTAL=$(( PASS + FAIL ))
if (( FAIL == 0 )); then
    echo -e "${GREEN}${BOLD}  All $TOTAL assertions passed${RESET}"
else
    echo -e "${RED}${BOLD}  $FAIL / $TOTAL assertions failed${RESET}"
fi
echo -e "${BOLD}${BLUE}══════════════════════════════════════════${RESET}"

(( FAIL == 0 ))
