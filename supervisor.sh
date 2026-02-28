#!/bin/bash
# supervisor.sh — ICC main loop (pipe mode)
# Start claude session -> parse stream-json -> relay to new session when context is exhausted
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/handoff.sh"

# ─── Argument parsing ───
TASK=""
while [[ $# -gt 0 ]]; do
    if handle_common_arg "$1" "${2:-}"; then shift 2; continue; fi
    case "$1" in
        --help|-h)
            cat <<'USAGE'
Usage: supervisor.sh [OPTIONS] "TASK DESCRIPTION"

Options:
  --model MODEL          Claude model to use (default: sonnet)
  --max-sessions N       Maximum relay sessions (default: 10)
  --warn-tokens N        Context warning threshold (default: 175000)
  --critical-tokens N    Context critical/deny threshold (default: 190000)

Environment variables CTX_WARN_TOKENS, CTX_CRITICAL_TOKENS also work.

Example:
  bash supervisor.sh --model haiku --max-sessions 3 \
    "Write a Python HTTP server with GET/POST endpoints"
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
    echo "Error: no task provided. Usage: supervisor.sh [OPTIONS] \"TASK\"" >&2
    exit 1
fi

# ─── Prevent nesting detection ───
unset CLAUDECODE 2>/dev/null || true

# ─── Statistics ───
TOTAL_COST=0
TOTAL_INPUT=0
TOTAL_OUTPUT=0
SESSION_COUNT=0

add_cost() {
    TOTAL_COST=$(python3 -c "print(round($TOTAL_COST + ${1:-0}, 6))")
}
add_tokens() {
    TOTAL_INPUT=$(( TOTAL_INPUT + ${1:-0} ))
    TOTAL_OUTPUT=$(( TOTAL_OUTPUT + ${2:-0} ))
}

# ─── Main loop ───
CONTEXT=""

for (( i=1; i<=MAX_SESSIONS; i++ )); do
    SESSION_COUNT=$i
    print_session_header "$i"
    echo -e "  model: $MODEL"

    # Build prompt
    if [[ $i -eq 1 ]]; then
        PROMPT="${TASK}

${HANDOFF_SYSTEM_PROMPT}"
    else
        PROMPT="$(build_continuation_prompt "$i" "$TASK" "$CONTEXT")

${HANDOFF_SYSTEM_PROMPT}"
    fi

    # Run claude, parse stream-json line by line
    RESULT=""
    TOOL_USE_COUNT=0
    SESSION_COST=0
    SESSION_INPUT=0
    SESSION_OUTPUT=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        TYPE=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || continue

        case "$TYPE" in
            assistant)
                TEXT=$(echo "$line" | jq -r '
                    .message.content[]? |
                    select(.type == "text") |
                    .text // empty
                ' 2>/dev/null)
                [[ -n "$TEXT" ]] && echo -e "${CYAN}${TEXT}${RESET}"
                ;;
            tool_use)
                TOOL_USE_COUNT=$(( TOOL_USE_COUNT + 1 ))
                TNAME=$(echo "$line" | jq -r '.tool_name // "unknown"' 2>/dev/null)
                echo -e "  ${YELLOW}🔧 [$TNAME]${RESET}"
                ;;
            result)
                RESULT=$(echo "$line" | jq -r '.result // empty' 2>/dev/null)
                SESSION_COST=$(echo "$line" | jq -r '.cost_usd // 0' 2>/dev/null)
                SESSION_INPUT=$(echo "$line" | jq -r '.usage.input_tokens // 0' 2>/dev/null)
                SESSION_OUTPUT=$(echo "$line" | jq -r '.usage.output_tokens // 0' 2>/dev/null)
                ;;
        esac
    done < <(claude -p --model "$MODEL" --verbose --output-format stream-json "$PROMPT" 2>/dev/null)

    # Accumulate statistics
    add_cost "$SESSION_COST"
    add_tokens "$SESSION_INPUT" "$SESSION_OUTPUT"

    ok "Session $i done — tools: ${TOOL_USE_COUNT}  cost: \$${SESSION_COST}  tokens: ${SESSION_INPUT}/${SESSION_OUTPUT}"

    CONTEXT="$RESULT"

    # Termination check
    RESULT_LEN=${#RESULT}
    if (( TOOL_USE_COUNT == 0 )) && (( RESULT_LEN < 200 )); then
        echo -e "\n${GREEN}${BOLD}✓ Task appears complete (session used no tools and output was brief)${RESET}"
        break
    fi
    if [[ -z "$RESULT" ]]; then
        err "Session returned empty result, stopping"
        break
    fi
done

# ─── Final statistics ───
print_finish_banner "$SESSION_COUNT" \
    "Total cost: \$${TOTAL_COST}" \
    "Total tokens: ${TOTAL_INPUT} in / ${TOTAL_OUTPUT} out"
