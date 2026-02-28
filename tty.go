package main

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"time"
)

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("%x", time.Now().UnixNano())[:n*2]
	}
	return hex.EncodeToString(b)
}

func tmuxCmd(args ...string) error {
	cmd := exec.Command("tmux", args...)
	return cmd.Run()
}

func tmuxSendKeys(pane string, keys ...string) {
	args := append([]string{"send-keys", "-t", pane}, keys...)
	tmuxCmd(args...)
}

// tmuxSendLiteral sends text literally (-l flag), bypassing key name lookup.
func tmuxSendLiteral(pane, text string) {
	tmuxCmd("send-keys", "-t", pane, "-l", text)
}

func sendPrompt(pane, prompt string) {
	tmpfile, err := os.CreateTemp("", "icc-prompt-")
	if err != nil {
		errMsg("Failed to create temp file: %v", err)
		return
	}
	tmpPath := tmpfile.Name()
	tmpfile.WriteString(prompt)
	tmpfile.Close()

	tmuxCmd("load-buffer", tmpPath)
	tmuxCmd("paste-buffer", "-p", "-t", pane)
	os.Remove(tmpPath)

	time.Sleep(300 * time.Millisecond)
	tmuxSendKeys(pane, "Enter")
}

func runTTY(cfg Config) {
	tmuxSession := cfg.SessionName
	if tmuxSession == "" {
		tmuxSession = "icc-" + randomHex(3)
	}
	pane := tmuxSession + ":0.0"

	// Kill any existing session with this name
	tmuxCmd("kill-session", "-t", tmuxSession)

	fmt.Printf("\n%s%s══════════════════════════════════════════%s\n", colorBold, colorBlue, colorReset)
	fmt.Printf("%s%s  ICC (tmux file-signal mode)%s\n", colorBold, colorBlue, colorReset)
	if cfg.Model != "" {
		fmt.Printf("  Model: %s\n", cfg.Model)
	} else {
		fmt.Printf("  Model: (default)\n")
	}
	if cfg.MaxSessions > 0 {
		fmt.Printf("  Max sessions: %d\n", cfg.MaxSessions)
	} else {
		fmt.Printf("  Max sessions: unlimited\n")
	}
	if cfg.SessionTimeout > 0 {
		fmt.Printf("  Session timeout: %ds\n", cfg.SessionTimeout)
	} else {
		fmt.Printf("  Session timeout: unlimited\n")
	}
	fmt.Printf("  Attach: %stmux attach -t %s%s\n", colorBold, tmuxSession, colorReset)
	fmt.Printf("%s%s══════════════════════════════════════════%s\n", colorBold, colorBlue, colorReset)

	tmuxCmd("new-session", "-d", "-s", tmuxSession, "-x", "200", "-y", "50")
	time.Sleep(1 * time.Second)

	prevHandoffPath := ""
	lastSession := 0

sessionLoop:
	for i := 1; cfg.MaxSessions == 0 || i <= cfg.MaxSessions; i++ {
		lastSession = i
		printSessionHeader(i, cfg.MaxSessions)

		handoffPath := fmt.Sprintf("/tmp/icc-handoff-%s.md", randomHex(3))
		os.Setenv("ICC_HANDOFF_PATH", handoffPath)
		logMsg("Handoff path: %s", handoffPath)

		sysprompt := renderSystemPrompt(handoffPath)
		spFile, err := os.CreateTemp("/tmp", "icc-sp-")
		if err != nil {
			errMsg("Failed to create temp file: %v", err)
			break sessionLoop
		}
		spFile.WriteString(sysprompt)
		spPath := spFile.Name()
		spFile.Close()

		logMsg("Starting claude session...")
		claudeCmd := fmt.Sprintf(
			"unset CLAUDECODE && ICC_HANDOFF_PATH='%s' CTX_WARN_TOKENS=%d CTX_CRITICAL_TOKENS=%d %s",
			handoffPath, cfg.WarnTokens, cfg.CriticalTokens, claudeBin,
		)
		if cfg.Model != "" {
			claudeCmd += fmt.Sprintf(" --model %s", cfg.Model)
		}
		claudeCmd += fmt.Sprintf(" --permission-mode %s --append-system-prompt \"$(cat %s)\"",
			cfg.PermissionMode, spPath,
		)
		tmuxSendKeys(pane, claudeCmd, "Enter")

		if !waitForClaudeReady(pane, 60*time.Second) {
			errMsg("Claude did not start in time")
			os.Remove(spPath)
			break sessionLoop
		}
		okMsg("Claude ready")

		var prompt string
		if i == 1 || prevHandoffPath == "" {
			prompt = cfg.Task
		} else {
			prompt = buildContinuationPrompt(i, cfg.Task, prevHandoffPath)
		}

		logMsg("Sending prompt...")
		sendPrompt(pane, prompt)

		logMsg("Waiting for signal (handoff file or claude exit)...")
		signal := waitForSignal(handoffPath, pane, time.Duration(cfg.SessionTimeout)*time.Second)

		os.Remove(spPath)

		switch signal {
		case 0: // handoff file detected
			okMsg("Session %d: handoff file detected at %s", i, handoffPath)
			logMsg("Handoff content preview:")
			if data, err := os.ReadFile(handoffPath); err == nil {
				lines := splitLines(string(data))
				for j := 0; j < 5 && j < len(lines); j++ {
					fmt.Printf("  %s\n", lines[j])
				}
			}

			logMsg("Gracefully exiting claude...")
			gracefulExit(pane, 30*time.Second)
			okMsg("Claude exited")

			prevHandoffPath = handoffPath

			if cfg.MaxSessions > 0 && i >= cfg.MaxSessions {
				logMsg("Reached max sessions (%d)", cfg.MaxSessions)
				break sessionLoop
			}
			time.Sleep(3 * time.Second)

		case 1: // claude exited
			if fileExists(handoffPath) {
				okMsg("Session %d: claude exited with handoff", i)
				prevHandoffPath = handoffPath
				if cfg.MaxSessions > 0 && i >= cfg.MaxSessions {
					logMsg("Reached max sessions (%d)", cfg.MaxSessions)
					break sessionLoop
				}
				time.Sleep(3 * time.Second)
			} else {
				fmt.Printf("\n%s%s✓ Session %d: claude exited without handoff — task likely complete%s\n",
					colorGreen, colorBold, i, colorReset)
				break sessionLoop
			}

		case 2: // timeout
			errMsg("Session %d timed out (%ds)", i, cfg.SessionTimeout)
			logMsg("Force-exiting claude...")
			gracefulExit(pane, 15*time.Second)
			if fileExists(handoffPath) {
				okMsg("Session %d: handoff file found after timeout at %s", i, handoffPath)
				prevHandoffPath = handoffPath
				if cfg.MaxSessions > 0 && i >= cfg.MaxSessions {
					break sessionLoop
				}
				time.Sleep(3 * time.Second)
			} else {
				break sessionLoop
			}
		}
	}

	printFinishBanner(lastSession,
		"Handoff files: ls /tmp/icc-handoff-*.md",
		fmt.Sprintf("Attach: tmux attach -t %s", tmuxSession),
		fmt.Sprintf("Cleanup: tmux kill-session -t %s", tmuxSession),
	)
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func splitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			lines = append(lines, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}
