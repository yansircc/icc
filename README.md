# infinite-claude

让 Claude Code 突破 context window 限制，自动接力完成复杂任务。

## 工作原理

1. **context-guard hook** 监控每次工具调用后的 context 消耗
2. 到达警告阈值时，注入提醒让 agent 准备总结
3. 到达临界阈值时，拒绝探索类工具，迫使 agent 输出交接总结
4. **supervisor** 捕获总结，启动新 session 继续工作

```
Session 1 ──→ 接近上限 ──→ 总结交接
                                ↓
Session 2 ──→ 接近上限 ──→ 总结交接
                                ↓
Session 3 ──→ 任务完成 ✓
```

## 安装

```bash
cd ~/code/52/31-infinite-claude
bash install.sh
```

这会：
- 将 `context-guard.sh` 复制到 `~/.claude/hooks/`
- 在 `~/.claude/settings.json` 中注册 PreToolUse/PostToolUse hooks

## 使用

```bash
bash supervisor.sh [OPTIONS] "任务描述"
```

### 选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `--model MODEL` | sonnet | Claude 模型 |
| `--max-sessions N` | 10 | 最大接力次数 |
| `--warn-tokens N` | 150000 | 警告阈值 |
| `--critical-tokens N` | 170000 | 拒绝阈值 |

环境变量 `CTX_WARN_TOKENS` 和 `CTX_CRITICAL_TOKENS` 同样生效。

### 示例

```bash
# 基本使用
bash supervisor.sh "实现一个完整的 Todo API，包含 CRUD 和测试"

# 指定模型和 session 数
bash supervisor.sh --model haiku --max-sessions 5 \
  "Write a Python HTTP server with GET/POST endpoints"

# 低阈值测试接力机制
CTX_WARN_TOKENS=5000 CTX_CRITICAL_TOKENS=8000 \
  bash supervisor.sh --model haiku --max-sessions 3 \
  "Create a calculator app with unit tests"
```

## 文件说明

| 文件 | 用途 |
|------|------|
| `supervisor.sh` | 主循环：启动 session → 解析 stream-json → 接力 |
| `context-guard.sh` | Hook：PostToolUse 提醒 / PreToolUse 拒绝 |
| `install.sh` | 安装 hook 到 `~/.claude/` |

## 依赖

- `claude` CLI（已安装并登录）
- `jq`
- `python3`

## 终止条件

supervisor 在以下情况停止：
- session 未使用任何工具且输出 < 200 字符 → 认为任务完成
- session 返回空结果 → 异常退出
- 达到 `--max-sessions` 上限

## 注意事项

- 必须在外部终端运行，不能在 Claude Code 内嵌套
- hook 阈值可以根据实际任务复杂度调整
- 交接信息通过 bash 变量传递，零文件依赖
