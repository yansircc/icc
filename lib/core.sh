#!/bin/bash
# lib/core.sh — Shared infrastructure: default config, colors, logging, argument handling, banner

# ─── Default Config ───
MODEL="${MODEL:-sonnet}"
MAX_SESSIONS="${MAX_SESSIONS:-10}"
CTX_WARN_TOKENS="${CTX_WARN_TOKENS:-175000}"
CTX_CRITICAL_TOKENS="${CTX_CRITICAL_TOKENS:-190000}"
export CTX_WARN_TOKENS CTX_CRITICAL_TOKENS

# ─── Colors ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Logging ───
log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${RESET} $*"; }
ok()  { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
err() { echo -e "${RED}${BOLD}✗${RESET} $*"; }

# ─── Common Argument Handling ───
# Returns 0 = handled (caller should shift 2), 1 = unrecognized
handle_common_arg() {
    case "$1" in
        --model)           MODEL="$2" ;;
        --max-sessions)    MAX_SESSIONS="$2" ;;
        --warn-tokens)     CTX_WARN_TOKENS="$2"; export CTX_WARN_TOKENS ;;
        --critical-tokens) CTX_CRITICAL_TOKENS="$2"; export CTX_CRITICAL_TOKENS ;;
        *) return 1 ;;
    esac
    return 0
}

# ─── Banner ───
print_session_header() {
    echo -e "\n${BOLD}${BLUE}── Session $1 / $MAX_SESSIONS ──${RESET}"
}

print_finish_banner() {
    local sessions="$1"; shift
    echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${BLUE}  ICC Finished${RESET}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
    echo -e "  Total sessions: ${sessions}"
    for line in "$@"; do
        echo -e "  ${line}"
    done
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
}
