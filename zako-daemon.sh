#!/usr/bin/env bash
# zako-daemon.sh - Management script for the local daemon (Ollama default, llama.cpp optional)

# Resolve canonical script directory even if invoked through symlink
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# Backend selection: 'ollama' (default) or 'llama.cpp' / 'llama'
BACKEND="${ZAKO_BACKEND:-${BACKEND:-ollama}}"

# Ollama settings
OLLAMA_BIN="${OLLAMA_BIN:-$(command -v ollama 2>/dev/null || echo "/usr/local/bin/ollama")}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_MODEL="${ZAKO_MODEL:-${OLLAMA_MODEL:-zako-tease}}"

# llama.cpp fallback settings
if [ -z "$MODEL_PATH" ]; then
    if [ -f "$SCRIPT_DIR/models/qwen2.5-3b-instruct-q4_k_m.gguf" ]; then
        MODEL_PATH="$SCRIPT_DIR/models/qwen2.5-3b-instruct-q4_k_m.gguf"
    elif [ -f "$SCRIPT_DIR/models/qwen2.5-1.5b-instruct-q4_k_m.gguf" ]; then
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

# Voice daemon settings (Kasane Teto RVC)
VOICE_PID_FILE="/tmp/zako-voice-daemon.pid"
VOICE_LOG_FILE="/tmp/zako-voice-daemon.log"
VOICE_PORT="${ZAKO_VOICE_PORT:-11435}"
ENABLE_VOICE="${ZAKO_VOICE_DAEMON:-0}"
ENABLE_RVC="${ZAKO_RVC:-0}"
RVC_METHOD="${ZAKO_RVC_METHOD:-rmvpe}"
RVC_PITCH="${ZAKO_RVC_PITCH:-2}"

# Auto-detect best python interpreter for voice daemon
detect_voice_python() {
    if [ -n "${ZAKO_PYTHON:-}" ] && [ -x "$ZAKO_PYTHON" ]; then
        echo "$ZAKO_PYTHON"
    elif [ -x "$SCRIPT_DIR/.venv/bin/python" ]; then
        echo "$SCRIPT_DIR/.venv/bin/python"
    elif [ "$ENABLE_RVC" = "1" ] && [ -x "$SCRIPT_DIR/../Open-LLM-VTuber_RVC/.venv/bin/python" ]; then
        echo "$SCRIPT_DIR/../Open-LLM-VTuber_RVC/.venv/bin/python"
    else
        command -v python3 || echo "python3"
    fi
}

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

start_voice_daemon() {
    local vpy
    vpy=$(detect_voice_python)

    if [ -f "$VOICE_PID_FILE" ] && kill -0 "$(cat "$VOICE_PID_FILE")" 2>/dev/null; then
        echo "zako-voice-daemon is already running (PID: $(cat "$VOICE_PID_FILE"))."
        return 0
    fi

    if curl -s --max-time 0.5 "http://127.0.0.1:$VOICE_PORT/health" >/dev/null 2>&1; then
        echo "zako-voice-daemon is already listening on port $VOICE_PORT ♡"
        return 0
    fi

    echo "Starting zako-voice-daemon (Kasane Teto, RVC=$ENABLE_RVC, pitch=+$RVC_PITCH, method=$RVC_METHOD, Python=$vpy)..."
    env PYTHONUNBUFFERED=1 ZAKO_RVC="$ENABLE_RVC" ZAKO_RVC_PITCH="$RVC_PITCH" ZAKO_RVC_METHOD="$RVC_METHOD" ZAKO_VOICE_PORT="$VOICE_PORT" setsid "$vpy" -u "$SCRIPT_DIR/zako-voice-daemon.py" < /dev/null > "$VOICE_LOG_FILE" 2>&1 &
    local vpid=$!
    echo "$vpid" > "$VOICE_PID_FILE"
    disown "$vpid" 2>/dev/null || true

    # Wait up to 15 seconds for model preload (RVC on CPU takes ~4-6s to warm up)
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        if curl -s --max-time 0.3 "http://127.0.0.1:$VOICE_PORT/health" >/dev/null 2>&1; then
            echo "zako-voice-daemon started successfully on port $VOICE_PORT (PID: $vpid) ♡"
            return 0
        fi
        sleep 0.5
        wait_count=$((wait_count + 1))
    done

    if kill -0 "$vpid" 2>/dev/null; then
        echo "zako-voice-daemon running (PID: $vpid), warming up models... Check $VOICE_LOG_FILE"
    else
        echo "zako-voice-daemon failed to start. Check $VOICE_LOG_FILE" >&2
        rm -f "$VOICE_PID_FILE"
        return 1
    fi
}

stop_voice_daemon() {
    if [ -f "$VOICE_PID_FILE" ]; then
        local vpid
        vpid=$(cat "$VOICE_PID_FILE")
        if kill -0 "$vpid" 2>/dev/null; then
            echo "Stopping zako-voice-daemon (PID: $vpid)..."
            kill "$vpid" 2>/dev/null
            rm -f "$VOICE_PID_FILE"
            echo "zako-voice-daemon stopped."
            return 0
        fi
        rm -f "$VOICE_PID_FILE"
    fi
    echo "zako-voice-daemon is not running."
}

status_voice_daemon() {
    if curl -s --max-time 0.5 "http://127.0.0.1:$VOICE_PORT/health" >/dev/null 2>&1; then
        local health
        health=$(curl -s --max-time 1 "http://127.0.0.1:$VOICE_PORT/health" 2>/dev/null)
        local rvc_on
        rvc_on=$(echo "$health" | jq -r '.rvc_enabled' 2>/dev/null || echo "unknown")
        local rvc_pitch
        rvc_pitch=$(echo "$health" | jq -r '.rvc_pitch' 2>/dev/null || echo "0")
        local rvc_method
        rvc_method=$(echo "$health" | jq -r '.rvc_method // empty' 2>/dev/null || echo "")
        local tts_engine
        tts_engine=$(echo "$health" | jq -r '.tts_backend // "edge-tts"' 2>/dev/null || echo "edge-tts")

        echo "zako-voice-daemon is running at http://127.0.0.1:$VOICE_PORT ♡"
        if [ "$rvc_on" = "true" ]; then
            echo "  Voice Engine: $tts_engine + Kasane Teto ONNX (pitch +$rvc_pitch, method: $rvc_method) 🥖"
        else
            echo "  Voice Engine: $tts_engine 🤖"
        fi
    else
        if [ -f "$VOICE_PID_FILE" ] && kill -0 "$(cat "$VOICE_PID_FILE")" 2>/dev/null; then
            echo "zako-voice-daemon process running (PID: $(cat "$VOICE_PID_FILE")), initializing models..."
        else
            echo "zako-voice-daemon is stopped."
        fi
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

    if [ "$ENABLE_VOICE" = "1" ] || [ "$ENABLE_VOICE" = "true" ]; then
        start_voice_daemon
    fi
}

stop_daemon() {
    stop_voice_daemon 2>/dev/null || true

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

    echo ""
    status_voice_daemon
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

ACTION="${1:-start}"
shift || true

while [ $# -gt 0 ]; do
    case "$1" in
        --voice|--with-voice)
            ENABLE_VOICE=1
            ;;
        --rvc|--teto)
            ENABLE_VOICE=1
            ENABLE_RVC=1
            ;;
        --method=*)
            RVC_METHOD="${1#*=}"
            ;;
        --method)
            shift
            RVC_METHOD="$1"
            ;;
        --pitch=*)
            RVC_PITCH="${1#*=}"
            CUSTOM_PITCH=1
            ;;
        --pitch)
            shift
            RVC_PITCH="$1"
            CUSTOM_PITCH=1
            ;;
        *)
            ;;
    esac
    shift
done

case "$ACTION" in
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
    voice-start)
        ENABLE_VOICE=1
        start_voice_daemon
        ;;
    voice-stop)
        stop_voice_daemon
        ;;
    voice-status)
        status_voice_daemon
        ;;
    voice-restart)
        stop_voice_daemon
        sleep 1
        ENABLE_VOICE=1
        start_voice_daemon
        ;;
    run)
        run_foreground
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|voice-start|voice-stop|voice-status|voice-restart|run} [--voice] [--rvc] [--pitch=<n>] [--method=pm|rmvpe|harvest]"
        echo "Options:"
        echo "  --voice, --with-voice         Start persistent voice daemon alongside LLM backend"
        echo "  --rvc                         Enable RVC voice conversion (Miku)"
        echo "  --pitch=<n>                   RVC pitch shift semitones (default: 8)"
        echo "  --method=<pm|rmvpe|harvest>   Pitch extraction algorithm (default: pm)"
        echo "Environment variables: BACKEND=ollama|llama.cpp, ZAKO_MODEL=zako-tease, ZAKO_RVC=1, ZAKO_RVC_PITCH=8, ZAKO_RVC_METHOD=pm"
        exit 1
        ;;
esac
