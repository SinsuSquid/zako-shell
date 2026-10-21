#!/usr/bin/env bash
# mesu-starship.sh - The Hostile Ergonomics Terminal Hook

# Capture the exit code of the last command and the command string itself
EXIT_CODE=$1
FAILED_CMD=$(fc -ln -1 | sed 's/^[[:space:]]*//')

# Exit immediately if the command succeeded (0) or if the input is empty
if [ "$EXIT_CODE" -eq 0 ] || [ -z "$FAILED_CMD" ]; then
    exit 0
fi

# Local llama-server endpoint
LLAMA_ENDPOINT="http://127.0.0.1:8080/v1/chat/completions"

# Minimal payload tuned for ultra-low latency generation
PAYLOAD=$(cat <<EOF
{
  "messages": [
    {
      "role": "system",
      "content": "You are Mesugaki-chan, a playful and bratty terminal daemon. Address the user as Zako or Zako-chan. Lightly tease them for their failed command in 1 short punchy sentence ending with ~♡. Zero help policy. Never explain how to fix it."
    },
    {
      "role": "user",
      "content": "Failed command: '${FAILED_CMD}', Exit code: ${EXIT_CODE}"
    }
  ],
  "temperature": 0.8,
  "max_tokens": 40
}
EOF
)

# Request inference with a hard timeout to prevent blocking the shell prompt
RESPONSE=$(curl -s --max-time 1.5 -X POST "$LLAMA_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>/dev/null | jq -r '.choices[0].message.content' 2>/dev/null)

# Print formatted output with ANSI magenta styling if a valid response exists
if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "null" ]; then
    printf "\033[1;35m♡ Mesugaki: %s\033[0m\n" "$RESPONSE"
fi
