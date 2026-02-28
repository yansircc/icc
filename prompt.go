package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const handoffFormat = `## Q0: What is the current state of this project?
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
(Honest uncertainty is more valuable than false confidence.)`

const handoffRules = `- You are an AUTONOMOUS agent. NEVER ask the human for confirmation, clarification, or approval. NEVER pause to wait for input. Make decisions and execute.
- DO NOT list completed work or modified files — the supervisor auto-injects git diff.
- DO NOT restate the original task — the supervisor passes it separately.
- DO NOT answer a question with "None" — if truly none, skip it entirely.
- Q0 (project state) is MANDATORY — without it the next agent cannot orient itself.`

// renderSystemPrompt builds the TTY mode system prompt (includes handoff file path).
func renderSystemPrompt(handoffPath string) string {
	return fmt.Sprintf(`[IMPORTANT SYSTEM INSTRUCTION — ICC RELAY PROTOCOL]

You are one node in an autonomous state machine. When your context fills up, a supervisor will restart a fresh agent that inherits your state. Your job is to make progress on the task and, when warned about context limits, write a handoff file so the next agent can resume without loss.

## Handoff Mechanism

The environment variable ICC_HANDOFF_PATH is set to:
  %s

When you receive a context warning (⚠ Context used...), you MUST:
1. Finish your current immediate step
2. Use the Write tool to create the handoff file at the EXACT path above
3. The file signals the supervisor to start a new session — this is how the relay works

## Handoff File Format

The file MUST follow this structure:

`+"```"+`markdown
%s
`+"```"+`

## Critical Rules

%s
- The handoff is a FILE written via the Write tool — NOT text output to the conversation.`, handoffPath, handoffFormat, handoffRules)
}

// pipeSystemPrompt returns the pipe mode system prompt (no file signals).
func pipeSystemPrompt() string {
	return fmt.Sprintf(`[IMPORTANT SYSTEM INSTRUCTION — ICC RELAY PROTOCOL]

You are one node in an autonomous state machine. When your context fills up, a supervisor will restart a fresh agent that inherits your state.

When you receive a context warning (⚠ Context used...), you MUST:
1. Finish your current immediate step
2. Output a HANDOFF as your final message following the format below

HANDOFF FORMAT — answer each question concisely:

%s

RULES:
%s`, handoffFormat, handoffRules)
}

// buildContinuationPrompt constructs the prompt for session 2+.
// handoffSource can be a file path (TTY mode) or raw text (pipe mode).
func buildContinuationPrompt(sessionNum int, task, handoffSource string) string {
	handoff := handoffSource
	if data, err := os.ReadFile(handoffSource); err == nil {
		handoff = string(data)
	}

	gitState := runGit("diff", "--stat", "HEAD~1", "HEAD")
	if gitState == "" {
		gitState = "(no git history)"
	}
	gitStatus := runGit("status", "--short")

	return fmt.Sprintf(`You are session %d of an autonomous state machine. You are resuming from session %d.

CRITICAL: You are AUTONOMOUS. Do NOT ask the human anything. Do NOT wait for confirmation. Read the handoff, understand the state, and EXECUTE immediately.

## Original Task
%s

## Auto-recovered State (from git)
`+"`"+"`"+"`"+`
%s
%s
`+"`"+"`"+"`"+`

## Handoff from Previous Session
%s

Read the handoff above carefully before doing anything.
- Q0 gives you project orientation
- Q1 tells you exactly where to start
- Q2 tells you what NOT to try — respect these, they were learned the hard way
- Q3 explains decisions that might look wrong but aren't
- Q4 flags risks you should verify early

Now execute. Do not ask questions. Do not wait for approval. Start working.`,
		sessionNum, sessionNum-1, task, gitState, gitStatus, handoff)
}

func runGit(args ...string) string {
	cmd := exec.Command("git", args...)
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}
