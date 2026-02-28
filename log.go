package main

import (
	"fmt"
	"time"
)

// ANSI color codes
const (
	colorRed    = "\033[0;31m"
	colorGreen  = "\033[0;32m"
	colorYellow = "\033[1;33m"
	colorBlue   = "\033[0;34m"
	colorCyan   = "\033[0;36m"
	colorBold   = "\033[1m"
	colorReset  = "\033[0m"
)

func logMsg(format string, a ...any) {
	ts := time.Now().Format("15:04:05")
	msg := fmt.Sprintf(format, a...)
	fmt.Printf("%s[%s]%s %s\n", colorBlue, ts, colorReset, msg)
}

func okMsg(format string, a ...any) {
	msg := fmt.Sprintf(format, a...)
	fmt.Printf("%s%s✓%s %s\n", colorGreen, colorBold, colorReset, msg)
}

func errMsg(format string, a ...any) {
	msg := fmt.Sprintf(format, a...)
	fmt.Printf("%s%s✗%s %s\n", colorRed, colorBold, colorReset, msg)
}

func printSessionHeader(session, maxSessions int) {
	fmt.Printf("\n%s%s── Session %d / %d ──%s\n", colorBold, colorBlue, session, maxSessions, colorReset)
}

func printFinishBanner(sessions int, lines ...string) {
	fmt.Printf("\n%s%s══════════════════════════════════════════%s\n", colorBold, colorBlue, colorReset)
	fmt.Printf("%s%s  ICC Finished%s\n", colorBold, colorBlue, colorReset)
	fmt.Printf("%s%s══════════════════════════════════════════%s\n", colorBold, colorBlue, colorReset)
	fmt.Printf("  Total sessions: %d\n", sessions)
	for _, line := range lines {
		fmt.Printf("  %s\n", line)
	}
	fmt.Printf("%s%s══════════════════════════════════════════%s\n", colorBold, colorBlue, colorReset)
}
