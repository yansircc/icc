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
        ok "$desc"; (( PASS++ ))
    else
        err "$desc"; (( FAIL++ ))
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
        bash "$SCRIPT_DIR/icc" -p \
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
test_tty() {
    echo -e "\n${BOLD}${BLUE}━━━ TTY Mode E2E ━━━${RESET}\n"

    if ! command -v tmux &>/dev/null; then
        skip "tmux not found, skipping TTY test"
        return
    fi

    local tmpdir="/tmp/icc-test-tty-$$"
    local logfile="/tmp/icc-e2e-tty-$$.log"
    local session_name="icc-e2e-$$"
    rm -rf "$tmpdir" /tmp/icc-handoff-*.md

    tmux kill-session -t "$session_name" 2>/dev/null || true

    log "Running icc --name $session_name (max-sessions=3, low thresholds, timeout=180s)..."
    CTX_WARN_TOKENS=5000 CTX_CRITICAL_TOKENS=8000 \
        bash "$SCRIPT_DIR/icc" \
            --name "$session_name" \
            --model haiku --max-sessions 3 --session-timeout 180 \
            "Create $tmpdir/calculator.py with add/sub/mul/div functions and $tmpdir/test_calc.py with pytest tests" \
        > "$logfile" 2>&1 || true

    local output
    output=$(cat "$logfile")

    assert "icc (TTY) produced output" '[[ -n "$output" ]]'
    assert "Session 1 started" 'echo "$output" | grep -q "Session 1"'
    assert "Claude ready detected" 'echo "$output" | grep -q "Claude ready"'

    local handoff_files
    handoff_files=$(ls /tmp/icc-handoff-*.md 2>/dev/null || true)
    assert "Handoff file(s) created" '[[ -n "$handoff_files" ]]'

    if [[ -n "$handoff_files" ]]; then
        local first_handoff
        first_handoff=$(echo "$handoff_files" | head -1)
        local q_count
        q_count=$(grep -c '^## Q[0-4]' "$first_handoff" 2>/dev/null || echo 0)
        assert "Handoff contains Q0-Q4 sections (found $q_count)" '(( q_count >= 2 ))'

        echo ""
        log "Handoff preview ($first_handoff):"
        head -10 "$first_handoff" | sed 's/^/  /'
    fi

    assert "Finish banner appeared" 'echo "$output" | grep -q "ICC Finished"'
    assert "Session 2 started (relay occurred)" 'echo "$output" | grep -q "Session 2"'

    rm -f "$logfile"
    rm -rf "$tmpdir"
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
