package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
)

// version is set at build time via -ldflags "-X main.version=...".
var version = "dev"

// Config holds all runtime configuration.
type Config struct {
	Task           string
	Model          string
	PermissionMode string
	SessionName    string
	PipeMode       bool
	MaxSessions    int
	WarnTokens     int
	CriticalTokens int
	SessionTimeout int
}

// claudeBin is the resolved path to the claude CLI binary.
var claudeBin string

func findClaude() string {
	if v := os.Getenv("CLAUDE_BIN"); v != "" {
		return v
	}
	if p, err := exec.LookPath("claude"); err == nil {
		return p
	}
	fmt.Fprintln(os.Stderr, "Error: 'claude' not found in PATH. Set CLAUDE_BIN to override.")
	os.Exit(1)
	return ""
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envIntOrDefault(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func requireArg(args []string, i int, flag string) string {
	if i+1 >= len(args) {
		fmt.Fprintf(os.Stderr, "Error: %s requires a value\n", flag)
		os.Exit(1)
	}
	return args[i+1]
}

func requireIntArg(args []string, i int, flag string) int {
	s := requireArg(args, i, flag)
	n, err := strconv.Atoi(s)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: invalid %s value: %s\n", flag, s)
		os.Exit(1)
	}
	return n
}

func printUsage() {
	fmt.Print(`Usage: icc [OPTIONS] "TASK DESCRIPTION"

Options:
  -p                       Pipe mode (claude -p, no tmux). Default is TTY mode.
  --model MODEL            Claude model (default: claude's own default)
  --max-sessions N         Max relay sessions (default: 0 = unlimited)
  --warn-tokens N          Context warning threshold (default: 175000)
  --critical-tokens N      Context deny threshold (default: 190000)
  --permission-mode MODE   Permission mode (default: bypassPermissions) [TTY only]
  --session-timeout N      Per-session timeout in seconds (default: 0 = unlimited) [TTY only]
  --name NAME              tmux session name (default: icc-<random>) [TTY only]

Environment variables CTX_WARN_TOKENS, CTX_CRITICAL_TOKENS also work.

NOTE: icc finds the claude binary via exec.LookPath, which ignores shell aliases
and functions. If you use a wrapper that injects API keys or provider config,
set CLAUDE_BIN to point to it, otherwise claude may fail with 401.

  export CLAUDE_BIN=/path/to/your/wrapper

Examples:
  # TTY mode (default) — you can attach to observe
  icc --model haiku --max-sessions 5 "Build a REST API with tests"
  tmux attach -t icc-a1b2c3

  # Pipe mode — simple, no manual intervention
  icc -p --model haiku --max-sessions 3 "Write a Python HTTP server"

  # Multiple concurrent instances (each gets unique tmux session)
  icc --name proj-a "Task A" &
  icc --name proj-b "Task B" &
`)
}

func main() {
	cfg := Config{
		Model:          os.Getenv("MODEL"),
		MaxSessions:    envIntOrDefault("MAX_SESSIONS", 0),
		WarnTokens:     envIntOrDefault("CTX_WARN_TOKENS", 175000),
		CriticalTokens: envIntOrDefault("CTX_CRITICAL_TOKENS", 190000),
		PermissionMode: envOrDefault("PERMISSION_MODE", "bypassPermissions"),
		SessionTimeout: envIntOrDefault("SESSION_TIMEOUT", 0),
	}

	args := os.Args[1:]

	// Subcommand dispatch
	if len(args) > 0 && args[0] == "install" {
		runInstall()
		return
	}

	for i := 0; i < len(args); {
		switch args[i] {
		case "-p":
			cfg.PipeMode = true
			i++
		case "--model":
			cfg.Model = requireArg(args, i, "--model")
			i += 2
		case "--max-sessions":
			cfg.MaxSessions = requireIntArg(args, i, "--max-sessions")
			i += 2
		case "--warn-tokens":
			cfg.WarnTokens = requireIntArg(args, i, "--warn-tokens")
			i += 2
		case "--critical-tokens":
			cfg.CriticalTokens = requireIntArg(args, i, "--critical-tokens")
			i += 2
		case "--permission-mode":
			cfg.PermissionMode = requireArg(args, i, "--permission-mode")
			i += 2
		case "--session-timeout":
			cfg.SessionTimeout = requireIntArg(args, i, "--session-timeout")
			i += 2
		case "--name":
			cfg.SessionName = requireArg(args, i, "--name")
			i += 2
		case "--version", "-v":
			fmt.Println(version)
			os.Exit(0)
		case "--help", "-h":
			printUsage()
			os.Exit(0)
		default:
			if len(args[i]) > 0 && args[i][0] == '-' {
				fmt.Fprintf(os.Stderr, "Unknown option: %s\n", args[i])
				os.Exit(1)
			}
			cfg.Task = args[i]
			i++
		}
	}

	if cfg.Task == "" {
		fmt.Fprintln(os.Stderr, "Error: no task provided. Run 'icc --help' for usage.")
		os.Exit(1)
	}

	// Prevent nesting detection
	os.Unsetenv("CLAUDECODE")

	// Resolve claude binary
	claudeBin = findClaude()

	// Export token thresholds for context-guard.sh hook
	os.Setenv("CTX_WARN_TOKENS", strconv.Itoa(cfg.WarnTokens))
	os.Setenv("CTX_CRITICAL_TOKENS", strconv.Itoa(cfg.CriticalTokens))

	if cfg.PipeMode {
		runPipe(cfg)
	} else {
		runTTY(cfg)
	}
}
