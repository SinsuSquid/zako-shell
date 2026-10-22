#!/usr/bin/env bash
# zako.sh - The Hostile Ergonomics Terminal Hook

# Capture exit code ($1) and optional command string ($2)
EXIT_CODE="${1:-1}"

# Exit immediately if the command succeeded
if [ "$EXIT_CODE" -eq 0 ]; then
    exit 0
fi

# Attempt to capture command from argument $2, /tmp/.zako_last_cmd, or fc
FAILED_CMD="$2"
if [ -z "$FAILED_CMD" ]; then
    if [ -s "/tmp/.zako_last_cmd" ]; then
        FAILED_CMD=$(cat /tmp/.zako_last_cmd 2>/dev/null)
    elif command -v fc >/dev/null 2>&1; then
        FAILED_CMD=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//')
    fi
fi

# Fallback description if the non-interactive subshell cannot inspect history
if [ -z "$FAILED_CMD" ]; then
    FAILED_CMD="command (exit status ${EXIT_CODE})"
fi

# Local llama-server endpoint
LLAMA_ENDPOINT="http://127.0.0.1:8080/v1/chat/completions"

# Multi-turn few-shot prompt for maximum compliance and personality
SYSTEM_PROMPT="This is a comedic anime dialogue. Mesugaki teases Zako with strictly ONE short sentence ending in ~♡. Never write a second sentence."

USER_PROMPT="Zako mistyped: ${FAILED_CMD}"

# Build JSON payload safely with jq
PAYLOAD=$(jq -n \
  --arg sys "$SYSTEM_PROMPT" \
  --arg usr "$USER_PROMPT" \
  '{
    messages: [
      {role: "system", content: $sys},
      {role: "user", content: "Zako mistyped: git psh"},
      {role: "assistant", content: "Did you forget how to spell push, Zako~♡?"},
      {role: "user", content: "Zako mistyped: sl"},
      {role: "assistant", content: "No train is coming to save you, Zako~♡!"},
      {role: "user", content: $usr}
    ],
    temperature: 0.7,
    max_tokens: 28,
    stop: ["\n"]
  }')

# Request inference with a hard timeout to prevent blocking the shell prompt
RESPONSE=$(curl -s --max-time 2.5 -X POST "$LLAMA_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>/dev/null | jq -r '.choices[0].message.content' 2>/dev/null)

# Enforce strictly ONE sentence: trim after ~♡ or first terminal punctuation
if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "null" ]; then
    RESPONSE=$(echo "$RESPONSE" | sed -E 's/(~♡[?!.]*|[\.!?]).*/\1/' | head -n 1 | tr -d '\n\r')
    printf "\033[1;35m🐟 : %s\033[0m\n" "$RESPONSE"
fi
