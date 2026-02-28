package main

import (
	"os/exec"
	"regexp"
	"strings"
	"time"
)

// pollUntil calls checkFn repeatedly until it returns true or timeout is reached.
// Returns true if the condition was met, false on timeout.
func pollUntil(checkFn func() bool, timeout, interval time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for {
		if checkFn() {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(interval)
	}
}

// capturePaneBottom captures the tmux pane and returns the last N non-empty lines.
func capturePaneBottom(pane string, n int) string {
	cmd := exec.Command("tmux", "capture-pane", "-t", pane, "-p")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	lines := strings.Split(string(out), "\n")
	var nonEmpty []string
	for _, l := range lines {
		if strings.TrimSpace(l) != "" {
			nonEmpty = append(nonEmpty, l)
		}
	}
	if len(nonEmpty) == 0 {
		return ""
	}
	start := len(nonEmpty) - n
	if start < 0 {
		start = 0
	}
	return strings.Join(nonEmpty[start:], "\n")
}

var shellPromptRe = regexp.MustCompile(`[%$]\s*$`)

// isShellPrompt checks if the tmux pane shows a shell prompt (zsh/bash).
func isShellPrompt(pane string) bool {
	return shellPromptRe.MatchString(capturePaneBottom(pane, 3))
}

// waitForClaudeReady clears the pane history then waits for the claude ❯ prompt.
// Clearing first prevents false positives from a previous session's ❯.
func waitForClaudeReady(pane string, timeout time.Duration) bool {
	exec.Command("tmux", "clear-history", "-t", pane).Run()

	return pollUntil(func() bool {
		return strings.Contains(capturePaneBottom(pane, 6), "❯")
	}, timeout, 2*time.Second)
}

// gracefulExit sends Esc + /exit to the claude session and waits for shell prompt.
// Key insight: /exit triggers an autocomplete dropdown in Claude Code.
// We must send "/exit" as literal text (-l), wait for autocomplete to render,
// then press Enter to select the first match. Sending "/exit" + Enter together
// races with autocomplete and fails.
func gracefulExit(pane string, timeout time.Duration) {
	tmuxSendKeys(pane, "Escape")
	time.Sleep(500 * time.Millisecond)
	tmuxSendLiteral(pane, "/exit")
	time.Sleep(2 * time.Second)
	tmuxSendKeys(pane, "Enter")

	ok := pollUntil(func() bool {
		return isShellPrompt(pane)
	}, timeout, 1*time.Second)

	if !ok {
		// Fallback: Ctrl+C to interrupt, then retry /exit
		tmuxSendKeys(pane, "C-c")
		time.Sleep(1 * time.Second)
		tmuxSendKeys(pane, "Escape")
		time.Sleep(500 * time.Millisecond)
		tmuxSendLiteral(pane, "/exit")
		time.Sleep(2 * time.Second)
		tmuxSendKeys(pane, "Enter")
		pollUntil(func() bool {
			return isShellPrompt(pane)
		}, 15*time.Second, 1*time.Second)
	}
}

// waitForSignal waits for a handoff file to appear or claude to exit (shell prompt).
// Returns: 0 = handoff file, 1 = shell prompt (claude exited), 2 = timeout.
func waitForSignal(handoffPath, pane string, timeout time.Duration) int {
	time.Sleep(5 * time.Second) // Let claude start processing

	deadline := time.Now().Add(timeout)
	for {
		// Check for handoff file first
		if fileExists(handoffPath) {
			time.Sleep(2 * time.Second)
			if fileExists(handoffPath) {
				return 0
			}
		}

		// Check for shell prompt (claude has exited)
		if isShellPrompt(pane) {
			time.Sleep(2 * time.Second)
			if isShellPrompt(pane) {
				return 1
			}
		}

		if time.Now().After(deadline) {
			return 2
		}
		time.Sleep(2 * time.Second)
	}
}
