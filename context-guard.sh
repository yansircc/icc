#!/bin/bash
# context-guard.sh — Context monitoring hook
# PostToolUse @ WARN: inject a reminder about remaining tokens on every call
# PreToolUse  @ CRITICAL: deny exploratory tools, only allow Read/Write/Edit/NotebookEdit
#                         whitelist writes to ICC_HANDOFF_PATH
set -euo pipefail

INPUT=$(cat)
WARN=${CTX_WARN_TOKENS:-175000}
CRITICAL=${CTX_CRITICAL_TOKENS:-190000}

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')

[[ ! -f "$TRANSCRIPT" ]] && exit 0

# Extract latest context usage from transcript (jq processes JSONL natively)
CTX=$(jq -r 'select(.type == "assistant") | .message.usage // {} |
    select(.output_tokens > 20) |
    ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) +
     (.cache_read_input_tokens // 0) + (.output_tokens // 0))' \
    "$TRANSCRIPT" 2>/dev/null | tail -1)
CTX=${CTX:-0}

# PreToolUse @ CRITICAL: deny exploratory tools
if [[ "$HOOK_EVENT" == "PreToolUse" ]] && (( CTX >= CRITICAL )); then
    # Whitelist: allow writing to handoff file path
    if [[ -n "${ICC_HANDOFF_PATH:-}" ]]; then
        FILEPATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
        [[ "$FILEPATH" == "$ICC_HANDOFF_PATH" ]] && exit 0
        if [[ "$TOOL_NAME" == "Bash" ]]; then
            COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
            echo "$COMMAND" | grep -qF "$ICC_HANDOFF_PATH" && exit 0
        fi
    fi

    case "$TOOL_NAME" in
        Write|Edit|Read|NotebookEdit) exit 0 ;;
    esac

    jq -n --arg r "Context ${CTX} tokens has exceeded the limit of ${CRITICAL}. Only Read/Write/Edit are allowed. Output the handoff immediately (follow the format in the system instructions)." \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
fi

# PostToolUse @ WARN: inject reminder
if [[ "$HOOK_EVENT" == "PostToolUse" ]] && (( CTX >= WARN )); then
    REMAIN=$(( CRITICAL - CTX ))
    jq -n --arg c "WARNING: Context has used ${CTX} tokens, approximately ${REMAIN} tokens remaining before the hard limit. Finish your current step as soon as possible, then output the handoff (follow the format in the system instructions)." \
      '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
    exit 0
fi

exit 0
