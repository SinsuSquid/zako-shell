#!/usr/bin/env bash
# zako-daemon.sh - Management script for the local daemon (Ollama default, llama.cpp optional)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Backend selection: 'ollama' (default) or 'llama.cpp' / 'llama'
BACKEND="${ZAKO_BACKEND:-${BACKEND:-ollama}}"

# Ollama settings
OLLAMA_BIN="${OLLAMA_BIN:-$(command -v ollama 2>/dev/null || echo "/usr/local/bin/ollama")}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_MODEL="${ZAKO_MODEL:-${OLLAMA_MODEL:-zako-tease}}"

# llama.cpp fallback settings
if [ -z "$MODEL_PATH" ]; then
    if [ -f "$SCRIPT_DIR/models/qwen2.5-1.5b-instruct-q4_k_m.gguf" ]; then
        MODEL_PATH="$SCRIPT_DIR/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
    else
        MODEL_PATH="$SCRIPT_DIR/models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
    fi
fi
LLAMA_SERVER="${LLAMA_SERVER:-$HOME/.local/bin/llama-server}"
LIB_DIR="${LIB_DIR:-$HOME/.local/lib64}"
LLAMA_PORT="${PORT:-8080}"
LLAMA_HOST="${HOST:-127.0.0.1}"
THREADS="${THREADS:-4}"
CTX_SIZE="${CTX_SIZE:-512}"

PID_FILE="/tmp/zako-daemon.pid"
LOG_FILE="/tmp/zako-daemon.log"

check_requirements_ollama() {
    if ! command -v "$OLLAMA_BIN" >/dev/null 2>&1 && [ ! -x "$OLLAMA_BIN" ]; then
        echo "Error: ollama not found or not executable. Install from https://ollama.com" >&2
        exit 1
    fi
}

check_requirements_llama() {
    export LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [ ! -x "$LLAMA_SERVER" ]; then
        echo "Error: llama-server not found or not executable at '$LLAMA_SERVER'" >&2
        exit 1
    fi

    if [ ! -f "$MODEL_PATH" ]; then
        echo "Error: Model file not found at '$MODEL_PATH'" >&2
        exit 1
    fi
}

start_daemon() {
    if [ "$BACKEND" = "ollama" ]; then
        check_requirements_ollama

        # Check if Ollama is already listening
        if curl -s "http://$OLLAMA_HOST:$OLLAMA_PORT/" 2>/dev/null | grep -q "Ollama is running"; then
            echo "zako-daemon: Ollama is already running on $OLLAMA_HOST:$OLLAMA_PORT ♡"
            return 0
        fi

        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "zako-daemon is already running (PID: $(cat "$PID_FILE"))."
            return 0
        fi

        echo "Starting zako-daemon with Ollama ($OLLAMA_HOST:$OLLAMA_PORT)..."
        nohup "$OLLAMA_BIN" serve > "$LOG_FILE" 2>&1 &
        local pid=$!
        echo "$pid" > "$PID_FILE"

        # Wait briefly for startup
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            echo "zako-daemon (Ollama) started successfully (PID: $pid) ♡"
        else
            echo "zako-daemon failed to start. Check $LOG_FILE" >&2
            rm -f "$PID_FILE"
            exit 1
        fi
    else
        check_requirements_llama

        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "zako-daemon is already running (PID: $(cat "$PID_FILE"))."
            return 0
        fi

        echo "Starting zako-daemon with llama-server on CPU ($LLAMA_HOST:$LLAMA_PORT)..."
        env LD_LIBRARY_PATH="$LIB_DIR" nohup "$LLAMA_SERVER" \
            -m "$MODEL_PATH" \
            --host "$LLAMA_HOST" \
            --port "$LLAMA_PORT" \
            -ngl 0 \
            -t "$THREADS" \
            -c "$CTX_SIZE" \
            -lv 0 > "$LOG_FILE" 2>&1 &

        local pid=$!
        echo "$pid" > "$PID_FILE"

        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            echo "zako-daemon (llama-server) started successfully (PID: $pid) ♡"
        else
            echo "zako-daemon failed to start. Check $LOG_FILE" >&2
            rm -f "$PID_FILE"
            exit 1
        fi
    fi
}

stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping zako-daemon (PID: $pid)..."
            kill "$pid" 2>/dev/null
            rm -f "$PID_FILE"
            echo "zako-daemon stopped."
            return 0
        fi
        rm -f "$PID_FILE"
    fi

    if [ "$BACKEND" = "ollama" ]; then
        if curl -s "http://$OLLAMA_HOST:$OLLAMA_PORT/" 2>/dev/null | grep -q "Ollama is running"; then
            echo "Note: Ollama is running via an external process or system service (not started by PID file $PID_FILE)."
            return 0
        fi
    fi

    echo "zako-daemon is not running."
}

status_daemon() {
    if [ "$BACKEND" = "ollama" ]; then
        if curl -s "http://$OLLAMA_HOST:$OLLAMA_PORT/" 2>/dev/null | grep -q "Ollama is running"; then
            echo "zako-daemon (Ollama) is running at http://$OLLAMA_HOST:$OLLAMA_PORT ♡"
            if command -v "$OLLAMA_BIN" >/dev/null 2>&1; then
                if "$OLLAMA_BIN" list 2>/dev/null | grep -q "$OLLAMA_MODEL"; then
                    echo "Model '$OLLAMA_MODEL': Ready ♡"
                else
                    echo "Model '$OLLAMA_MODEL': Not found in 'ollama list'."
                    local modelfile_path="$SCRIPT_DIR/Modelfiles/Modelfile.1.5b"
                    if [[ "$OLLAMA_MODEL" == *"0.5b"* ]]; then
                        modelfile_path="$SCRIPT_DIR/Modelfiles/Modelfile.0.5b"
                    elif [ ! -f "$modelfile_path" ] && [ -f "$SCRIPT_DIR/Modelfiles/Modelfile" ]; then
                        modelfile_path="$SCRIPT_DIR/Modelfiles/Modelfile"
                    fi
                    if [ -f "$modelfile_path" ]; then
                        echo "  -> Run 'ollama create $OLLAMA_MODEL -f $modelfile_path' to create it."
                    fi
                fi
            fi
        else
            echo "zako-daemon (Ollama) is stopped."
        fi
    else
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            local pid
            pid=$(cat "$PID_FILE")
            echo "zako-daemon (llama-server) is running (PID: $pid)."
            if curl -s "http://$LLAMA_HOST:$LLAMA_PORT/health" 2>/dev/null | grep -q "ok"; then
                echo "Health check: OK ♡"
            else
                echo "Health check: Endpoint reachable"
            fi
        else
            echo "zako-daemon (llama-server) is stopped."
        fi
    fi
}

run_foreground() {
    if [ "$BACKEND" = "ollama" ]; then
        check_requirements_ollama
        echo "Running zako-daemon (Ollama) in foreground..."
        exec "$OLLAMA_BIN" serve
    else
        check_requirements_llama
        echo "Running zako-daemon (llama-server) in foreground on CPU ($LLAMA_HOST:$LLAMA_PORT)..."
        exec "$LLAMA_SERVER" \
            -m "$MODEL_PATH" \
            --host "$LLAMA_HOST" \
            --port "$LLAMA_PORT" \
            -ngl 0 \
            -t "$THREADS" \
            -c "$CTX_SIZE"
    fi
}

case "${1:-start}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 1
        start_daemon
        ;;
    status)
        status_daemon
        ;;
    run)
        run_foreground
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|run}"
        echo "Environment variables: BACKEND=ollama|llama.cpp, ZAKO_MODEL=zako-tease"
        exit 1
        ;;
esac
