package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os/exec"
)

func runPipe(cfg Config) {
	var totalCost float64
	var totalInput, totalOutput int
	sessionCount := 0
	context := ""

	for i := 1; cfg.MaxSessions == 0 || i <= cfg.MaxSessions; i++ {
		sessionCount = i
		printSessionHeader(i, cfg.MaxSessions)
		if cfg.Model != "" {
			fmt.Printf("  model: %s\n", cfg.Model)
		} else {
			fmt.Printf("  model: (default)\n")
		}

		var prompt string
		if i == 1 {
			prompt = cfg.Task + "\n\n" + pipeSystemPrompt()
		} else {
			prompt = buildContinuationPrompt(i, cfg.Task, context) + "\n\n" + pipeSystemPrompt()
		}

		result, stats := runPipeSession(cfg.Model, prompt)

		totalCost += stats.cost
		totalInput += stats.inputTokens
		totalOutput += stats.outputTokens

		okMsg("Session %d done — tools: %d  cost: $%.4f  tokens: %d/%d",
			i, stats.toolUseCount, stats.cost, stats.inputTokens, stats.outputTokens)

		context = result

		if stats.toolUseCount == 0 && len(result) < 200 {
			fmt.Printf("\n%s%s✓ Task appears complete (session used no tools and output was brief)%s\n",
				colorGreen, colorBold, colorReset)
			break
		}
		if result == "" {
			errMsg("Session returned empty result, stopping")
			break
		}
	}

	printFinishBanner(sessionCount,
		fmt.Sprintf("Total cost: $%.4f", totalCost),
		fmt.Sprintf("Total tokens: %d in / %d out", totalInput, totalOutput),
	)
}

type sessionStats struct {
	toolUseCount int
	cost         float64
	inputTokens  int
	outputTokens int
}

func runPipeSession(model, prompt string) (string, sessionStats) {
	args := []string{"-p"}
	if model != "" {
		args = append(args, "--model", model)
	}
	args = append(args, "--verbose", "--output-format", "stream-json", prompt)
	cmd := exec.Command(claudeBin, args...)

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		errMsg("Failed to create pipe: %v", err)
		return "", sessionStats{}
	}

	if err := cmd.Start(); err != nil {
		errMsg("Failed to start claude: %v", err)
		return "", sessionStats{}
	}

	var result string
	var stats sessionStats

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		var raw map[string]interface{}
		if err := json.Unmarshal([]byte(line), &raw); err != nil {
			continue
		}

		eventType, _ := raw["type"].(string)

		switch eventType {
		case "assistant":
			if msg, ok := raw["message"].(map[string]interface{}); ok {
				if content, ok := msg["content"].([]interface{}); ok {
					for _, block := range content {
						if b, ok := block.(map[string]interface{}); ok {
							if b["type"] == "text" {
								if text, ok := b["text"].(string); ok && text != "" {
									fmt.Printf("%s%s%s\n", colorCyan, text, colorReset)
								}
							}
						}
					}
				}
			}

		case "tool_use":
			stats.toolUseCount++
			toolName := "unknown"
			if tn, ok := raw["tool_name"].(string); ok {
				toolName = tn
			}
			fmt.Printf("  %s🔧 [%s]%s\n", colorYellow, toolName, colorReset)

		case "result":
			if r, ok := raw["result"].(string); ok {
				result = r
			}
			if c, ok := raw["cost_usd"].(float64); ok {
				stats.cost = c
			}
			if usage, ok := raw["usage"].(map[string]interface{}); ok {
				if v, ok := usage["input_tokens"].(float64); ok {
					stats.inputTokens = int(v)
				}
				if v, ok := usage["output_tokens"].(float64); ok {
					stats.outputTokens = int(v)
				}
			}
		}
	}

	cmd.Wait()
	return result, stats
}
