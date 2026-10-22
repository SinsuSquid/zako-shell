#!/usr/bin/env bash
# zako-daemon.sh - Management script for the local llama-server daemon

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_PATH="${MODEL_PATH:-$SCRIPT_DIR/models/qwen2.5-0.5b-instruct-q4_k_m.gguf}"
LLAMA_SERVER="${LLAMA_SERVER:-$HOME/.local/bin/llama-server}"
LIB_DIR="${LIB_DIR:-$HOME/.local/lib64}"
PID_FILE="/tmp/zako-llama-server.pid"
LOG_FILE="/tmp/zako-llama-server.log"
PORT="${PORT:-8080}"
HOST="${HOST:-127.0.0.1}"
THREADS="${THREADS:-4}"
CTX_SIZE="${CTX_SIZE:-512}"

export LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

check_requirements() {
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
    check_requirements

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "zako-daemon is already running (PID: $(cat "$PID_FILE"))."
        return 0
    fi

    echo "Starting zako-daemon on CPU ($HOST:$PORT)..."
    nohup "$LLAMA_SERVER" \
        -m "$MODEL_PATH" \
        --host "$HOST" \
        --port "$PORT" \
        -ngl 0 \
        -t "$THREADS" \
        -c "$CTX_SIZE" \
        --log-disable > "$LOG_FILE" 2>&1 &

    local pid=$!
    echo "$pid" > "$PID_FILE"

    # Wait briefly for startup
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        echo "zako-daemon started successfully (PID: $pid) ♡"
    else
        echo "zako-daemon failed to start. Check $LOG_FILE" >&2
        rm -f "$PID_FILE"
        exit 1
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
    echo "zako-daemon is not running."
}

status_daemon() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        local pid
        pid=$(cat "$PID_FILE")
        echo "zako-daemon is running (PID: $pid)."
        if curl -s "http://$HOST:$PORT/health" 2>/dev/null | grep -q "ok"; then
            echo "Health check: OK ♡"
        else
            echo "Health check: Endpoint reachable"
        fi
    else
        echo "zako-daemon is stopped."
    fi
}

run_foreground() {
    check_requirements
    echo "Running zako-daemon in foreground on CPU ($HOST:$PORT)..."
    exec "$LLAMA_SERVER" \
        -m "$MODEL_PATH" \
        --host "$HOST" \
        --port "$PORT" \
        -ngl 0 \
        -t "$THREADS" \
        -c "$CTX_SIZE"
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
        exit 1
        ;;
esac
