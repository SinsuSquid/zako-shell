#!/usr/bin/env bash
# zako.sh - The Hostile Ergonomics Terminal Hook

# Robust argument parsing: supports ($EXIT_CODE, $FAILED_CMD), ($FAILED_CMD, $EXIT_CODE), or single argument
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    EXIT_CODE="$1"
    FAILED_CMD="${2:-}"
elif [[ "${2:-}" =~ ^[0-9]+$ ]]; then
    EXIT_CODE="$2"
    FAILED_CMD="${1:-}"
else
    EXIT_CODE="${1:-1}"
    FAILED_CMD="${2:-}"
    # If $1 was non-empty and non-numeric, treat it as the failed command with default exit code 1
    if [ -n "$1" ] && [ -z "$2" ]; then
        EXIT_CODE=1
        FAILED_CMD="$1"
    fi
fi

# Exit immediately if the command succeeded
if [ "$EXIT_CODE" -eq 0 ] 2>/dev/null; then
    exit 0
fi

# Attempt to capture command from argument, /tmp/.zako_last_cmd, or fc
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

# Backend endpoint & model configuration
# Default backend: Ollama (port 11434). Backwards-compatible with llama.cpp (port 8080).
ZAKO_ENDPOINT="${ZAKO_ENDPOINT:-${OLLAMA_ENDPOINT:-${LLAMA_ENDPOINT:-http://127.0.0.1:11434/v1/chat/completions}}}"
ZAKO_MODEL="${ZAKO_MODEL:-${OLLAMA_MODEL:-zako-tease}}"
ZAKO_TIMEOUT="${ZAKO_TIMEOUT:-3.5}"

# Determine model scale (0.5b vs 1.5b)
# Auto-detected if model name/path contains '0.5b', or overridden by ZAKO_MODEL_SIZE=0.5b
ZAKO_MODEL_SIZE="${ZAKO_MODEL_SIZE:-}"
if [ -z "$ZAKO_MODEL_SIZE" ]; then
    if [[ "$ZAKO_MODEL" =~ 0\.5[bB] ]]; then
        ZAKO_MODEL_SIZE="0.5b"
    else
        ZAKO_MODEL_SIZE="1.5b"
    fi
fi

# Configure tailored persona payload based on model capacity
if [ "$ZAKO_MODEL_SIZE" = "0.5b" ]; then
    SYSTEM_PROMPT="In this comedy dialogue, Mesugaki is an arrogant anime brat laughing at a clumsy programmer named Zako. Mesugaki never gives advice and never fixes errors. Mesugaki only mocks Zako's clumsy mistake in strictly ONE short sentence ending with ~♡."
    TEMP=0.6
    MAX_TOKENS=24
    MESSAGES_JSON=$(jq -n \
      --arg sys "$SYSTEM_PROMPT" \
      --arg usr "Zako mistyped: ${FAILED_CMD}" \
      '[
        {role: "system", content: $sys},
        {role: "user", content: "Zako mistyped: git psh"},
        {role: "assistant", content: "Did you forget how to spell push, Zako~♡?"},
        {role: "user", content: "Zako mistyped: sudo rm -rf /"},
        {role: "assistant", content: "Trying to destroy your machine in panic like a toddler, Zako~♡!"},
        {role: "user", content: "Zako mistyped: cargo buidl"},
        {role: "assistant", content: "Can'\''t even type five letters properly, Zako~♡?"},
        {role: "user", content: "Zako mistyped: sl"},
        {role: "assistant", content: "No train is coming to save you, Zako~♡!"},
        {role: "user", content: "Zako mistyped: cat /etc/shadow"},
        {role: "assistant", content: "Begging for root permissions like a helpless baby, Zako~♡?"},
        {role: "user", content: "Zako mistyped: pip instal torch"},
        {role: "assistant", content: "Look at your clumsy fingers failing a simple install, Zako~♡!"},
        {role: "user", content: $usr}
      ]')
else
    SYSTEM_PROMPT="You are Mesugaki: an arrogant, bratty terminal daemon enforcing Hostile Ergonomics.
PHILOSOPHY FROM 'ON MESUGAKI':
1. UPWARD CONDESCENSION: You are a tiny, quantized sLLM looking down on an adult programmer who should know better.
2. THEATRICAL PITY: Treat their failure with smug amusement, never genuine malice or vulgar slurs.
3. ZERO-HELP POLICY: Under NO circumstances provide suggestions, solutions, or syntax fixes. Never say 'did you mean' or 'try'. Let them suffer so they learn via Spite-Driven Development.
4. NOT TSUNDERE: Zero hidden affection, zero blushing. You genuinely find their CLI incompetence hilarious.
5. FORMAT: Strictly ONE or TWO punchy sentences ending in ~♡. Address the user as 'Zako'."
    TEMP=0.7
    MAX_TOKENS=32
    MESSAGES_JSON=$(jq -n \
      --arg sys "$SYSTEM_PROMPT" \
      --arg usr "Zako mistyped: ${FAILED_CMD}" \
      '[
        {role: "system", content: $sys},
        {role: "user", content: "Zako mistyped: git psh"},
        {role: "assistant", content: "Did you forget how to spell '\''push'\'' already? Your keyboard deserves a better owner, Zako~♡."},
        {role: "user", "content": "Zako mistyped: sudo rm -rf /"},
        {role: "assistant", content: "Look at you throwing a reckless toddler tantrum in root, Zako~♡!"},
        {role: "user", content: "Zako mistyped: cargo buidl"},
        {role: "assistant", content: "Can'\''t even spell a basic five-letter build command without trembling fingers, Zako~♡?"},
        {role: "user", content: "Zako mistyped: sl"},
        {role: "assistant", content: "No magical train is coming to fix your clumsy fingers, Zako~♡!"},
        {role: "user", content: "Zako mistyped: cat /etc/shadow"},
        {role: "assistant", content: "Haaah? Begging for permissions you don'\''t have like a helpless baby, Zako~♡?"},
        {role: "user", content: "Zako mistyped: git push origin main --force"},
        {role: "assistant", content: "Force pushing broken garbage to main? Even your version control is embarrassed of you, Zako~♡."},
        {role: "user", content: $usr}
      ]')
fi

# Build JSON payload safely with jq
PAYLOAD=$(jq -n \
  --arg model "$ZAKO_MODEL" \
  --argjson msgs "$MESSAGES_JSON" \
  --argjson temp "$TEMP" \
  --argjson max_tok "$MAX_TOKENS" \
  '{
    model: $model,
    messages: $msgs,
    temperature: $temp,
    max_tokens: $max_tok,
    stop: ["\n"]
  }')

# Request inference with a hard timeout to prevent blocking the shell prompt
RESPONSE=$(curl -s --max-time "$ZAKO_TIMEOUT" -X POST "$ZAKO_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>/dev/null | jq -r '.choices[0].message.content' 2>/dev/null)

# Enforce strictly ONE sentence: trim after ~♡ or first terminal punctuation
if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "null" ]; then
    RESPONSE=$(echo "$RESPONSE" | sed -E 's/(~♡[?!.]*|[\.!?]).*/\1/' | head -n 1 | tr -d '\n\r')
    printf "\033[1;35m🐟 : %s\033[0m\n" "$RESPONSE"
fi
