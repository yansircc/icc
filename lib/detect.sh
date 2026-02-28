#!/bin/bash
# lib/detect.sh — tmux pane detection: file signal + shell prompt detection
# Used by supervisor-tty.sh

# ─── Generic polling skeleton ───
# Usage: poll_until check_fn [timeout] [interval]
# Returns 0 = condition met, 1 = timeout
poll_until() {
    local check_fn="$1" timeout="${2:-60}" interval="${3:-2}"
    local start
    start=$(date +%s)
    while true; do
        "$check_fn" && return 0
        (( $(date +%s) - start > timeout )) && return 1
        sleep "$interval"
    done
}

# ─── Shell prompt detection ───
# Strategy: last non-empty line of the pane ends with % or $ (zsh/bash prompt)
# Usage: is_shell_prompt "$PANE"
is_shell_prompt() {
    local pane="$1"
    local content
    content=$(tmux capture-pane -t "$pane" -p 2>/dev/null) || return 1
    local bottom
    bottom=$(echo "$content" | sed '/^[[:space:]]*$/d' | tail -3)
    echo "$bottom" | grep -qE '(%|[$]) *$'
}

# ─── Wait for claude to be ready (detect ❯ prompt) ───
# Usage: wait_for_claude_ready "$PANE" "$TIMEOUT"
wait_for_claude_ready() {
    local pane="$1" timeout="${2:-60}"
    _check_claude_prompt() {
        local content
        content=$(tmux capture-pane -t "$pane" -p 2>/dev/null) || return 1
        local bottom
        bottom=$(echo "$content" | sed '/^[[:space:]]*$/d' | tail -6)
        echo "$bottom" | grep -q '❯'
    }
    poll_until _check_claude_prompt "$timeout" 2
}

# ─── Graceful exit of claude session ───
# Usage: graceful_exit "$PANE" "$TIMEOUT"
graceful_exit() {
    local pane="$1" timeout="${2:-30}"

    tmux send-keys -t "$pane" Escape
    sleep 1
    tmux send-keys -t "$pane" "/exit" Enter
    sleep 2

    _check_shell() { is_shell_prompt "$pane"; }
    poll_until _check_shell "$timeout" 1 || {
        tmux send-keys -t "$pane" C-c
        sleep 1
        tmux send-keys -t "$pane" "/exit" Enter
        sleep 3
    }
    return 0
}

# ─── Wait for signal: handoff file OR claude exit ───
# Return value: 0 = handoff file appeared, 1 = shell prompt (claude exited), 2 = timeout
# Usage: wait_for_signal "$HANDOFF_PATH" "$PANE" "$TIMEOUT"
wait_for_signal() {
    local handoff_path="$1"
    local pane="$2"
    local timeout="${3:-600}"
    local start
    start=$(date +%s)

    sleep 5  # Let claude start processing

    while true; do
        # Check for handoff file first
        if [[ -f "$handoff_path" ]]; then
            sleep 2
            [[ -f "$handoff_path" ]] && return 0
        fi

        # Check for shell prompt (claude has exited)
        if is_shell_prompt "$pane"; then
            sleep 2
            is_shell_prompt "$pane" && return 1
        fi

        (( $(date +%s) - start > timeout )) && return 2
        sleep 2
    done
}
