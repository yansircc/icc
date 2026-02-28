#!/bin/bash
# lib/handoff.sh — HANDOFF protocol: system instructions + continuation prompt templates
# Shared by supervisor.sh and supervisor-tty.sh

# ─── Single format definition (written once) ───
HANDOFF_FORMAT='## Q0: What is the current state of this project?
(what is this project, what is the current goal, how far have we progressed.
The next agent is a blank process with ZERO history — this section is its only orientation.)

## Q1: What should the next agent do first?
(Be specific: which file, which function, what exact change.
NOT "continue implementing X" — that is useless without context.)

## Q2: What will NOT work? What dead ends were discovered?
(Every dead end you hide costs the next agent 10+ tool calls to rediscover.)

## Q3: What non-obvious decisions were made and why?
(If the next agent reads the code and thinks "why not do it the other way?" — answer here.)

## Q4: What are you uncertain about?
(Honest uncertainty is more valuable than false confidence.)'

HANDOFF_RULES='- You are an AUTONOMOUS agent. NEVER ask the human for confirmation, clarification, or approval. NEVER pause to wait for input. Make decisions and execute.
- DO NOT list completed work or modified files — the supervisor auto-injects git diff.
- DO NOT restate the original task — the supervisor passes it separately.
- DO NOT answer a question with "None" — if truly none, skip it entirely.
- Q0 (project state) is MANDATORY — without it the next agent cannot orient itself.'

# ─── TTY mode: render system prompt (includes handoff file path) ───
# Usage: render_system_prompt "$HANDOFF_PATH"
render_system_prompt() {
    local handoff_path="$1"
    cat <<PROMPT
[IMPORTANT SYSTEM INSTRUCTION — ICC RELAY PROTOCOL]

You are one node in an autonomous state machine. When your context fills up, a supervisor will restart a fresh agent that inherits your state. Your job is to make progress on the task and, when warned about context limits, write a handoff file so the next agent can resume without loss.

## Handoff Mechanism

The environment variable ICC_HANDOFF_PATH is set to:
  ${handoff_path}

When you receive a context warning (⚠ Context used...), you MUST:
1. Finish your current immediate step
2. Use the Write tool to create the handoff file at the EXACT path above
3. The file signals the supervisor to start a new session — this is how the relay works

## Handoff File Format

The file MUST follow this structure:

\`\`\`markdown
${HANDOFF_FORMAT}
\`\`\`

## Critical Rules

${HANDOFF_RULES}
- The handoff is a FILE written via the Write tool — NOT text output to the conversation.
PROMPT
}

# ─── Pipe mode system prompt (does not rely on file signals) ───
read -r -d '' HANDOFF_SYSTEM_PROMPT <<SYSPROMPT || true
[IMPORTANT SYSTEM INSTRUCTION — ICC RELAY PROTOCOL]

You are one node in an autonomous state machine. When your context fills up, a supervisor will restart a fresh agent that inherits your state.

When you receive a context warning (⚠ Context used...), you MUST:
1. Finish your current immediate step
2. Output a HANDOFF as your final message following the format below

HANDOFF FORMAT — answer each question concisely:

${HANDOFF_FORMAT}

RULES:
${HANDOFF_RULES}
SYSPROMPT

# ─── Build continuation prompt (used for session 2+) ───
# TTY mode usage: build_continuation_prompt "$SESSION_NUM" "$TASK" "$PREV_HANDOFF_PATH"
# Pipe mode usage: build_continuation_prompt "$SESSION_NUM" "$TASK" "$HANDOFF_TEXT"
build_continuation_prompt() {
    local session_num="$1"
    local task="$2"
    local handoff_source="$3"

    local handoff
    if [[ -f "$handoff_source" ]]; then
        handoff=$(cat "$handoff_source")
    else
        handoff="$handoff_source"
    fi

    local git_state
    git_state=$(git diff --stat HEAD~1 HEAD 2>/dev/null || echo "(no git history)")
    local git_status
    git_status=$(git status --short 2>/dev/null || echo "")

    cat <<EOF
You are session ${session_num} of an autonomous state machine. You are resuming from session $((session_num - 1)).

CRITICAL: You are AUTONOMOUS. Do NOT ask the human anything. Do NOT wait for confirmation. Read the handoff, understand the state, and EXECUTE immediately.

## Original Task
${task}

## Auto-recovered State (from git)
\`\`\`
${git_state}
${git_status}
\`\`\`

## Handoff from Previous Session
${handoff}

Read the handoff above carefully before doing anything.
- Q0 gives you project orientation
- Q1 tells you exactly where to start
- Q2 tells you what NOT to try — respect these, they were learned the hard way
- Q3 explains decisions that might look wrong but aren't
- Q4 flags risks you should verify early

Now execute. Do not ask questions. Do not wait for approval. Start working.
EOF
}
