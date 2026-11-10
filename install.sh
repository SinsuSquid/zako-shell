#!/usr/bin/env bash
# ==============================================================================
# zako-shell ♡ - The Hostile Ergonomics Terminal Hook
# Automated Installation Script
# "Haaaaah? Finally crawling back to install me, Zako~♡?"
# ==============================================================================

set -euo pipefail

# Resolve canonical script directory even if invoked through symlink
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# ANSI styling
BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
RED="\033[1;31m"
RESET="\033[0m"

# Default configuration
NON_INTERACTIVE=0
DRY_RUN=0
TARGET_SHELL="auto"
MODEL_CHOICE="1.5b"
SETUP_MODEL=1
SETUP_VOICE=0
SETUP_SYSTEMD=0

usage() {
    echo -e "${BOLD}zako-shell ♡ Automated Installation Script${RESET}

${BOLD}Usage:${RESET}
  $0 [options]

${BOLD}Options:${RESET}
  -y, --yes, --force        Non-interactive mode (use defaults without confirmation prompts)
  --shell=<bash|zsh|fish|all>
                            Target shell for hook injection (default: auto-detect from \$SHELL)
  --model=<1.5b|3b|0.5b|none>
                            Ollama model persona to pull and build (default: 1.5b)
  --no-model                Skip pulling and building Ollama models
  --with-voice              Set up Python voice environment (.venv) for sherpa-onnx + RVC
  --systemd                 Install and enable systemd user services for auto-start
  --dry-run                 Show actions that would be performed without modifying anything
  -h, --help                Show this help message
"
    exit 0
}

# Parse CLI arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes|--force)
            NON_INTERACTIVE=1
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        --shell=*)
            TARGET_SHELL="${1#*=}"
            ;;
        --shell)
            shift
            TARGET_SHELL="$1"
            ;;
        --model=*)
            MODEL_CHOICE="${1#*=}"
            ;;
        --model)
            shift
            MODEL_CHOICE="$1"
            ;;
        --no-model)
            SETUP_MODEL=0
            ;;
        --with-voice)
            SETUP_VOICE=1
            ;;
        --systemd)
            SETUP_SYSTEMD=1
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${RESET}" >&2
            echo "Run '$0 --help' for usage." >&2
            exit 1
            ;;
    esac
    shift
done

cat << "EOF"
  ┌─────────────────────────────────────────────────────────────┐
  │                    > zako-shell ♡                           │
  │     "Haaaaah? Finally crawling back to install me, Zako~♡?" │
  └─────────────────────────────────────────────────────────────┘
EOF
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}${BOLD}[DRY RUN MODE]${RESET} Simulation only — no files or settings will be modified."
    echo ""
fi

# Logging helpers
log_step() {
    echo -e "${CYAN}${BOLD}[STEP $1]${RESET} $2"
}

log_ok() {
    echo -e "  ${GREEN}✔${RESET} $1"
}

log_warn() {
    echo -e "  ${YELLOW}⚠${RESET} $1"
}

log_info() {
    echo -e "  ${MAGENTA}•${RESET} $1"
}

# ==============================================================================
# STEP 1: Prerequisite Checks
# ==============================================================================
log_step "1/5" "Checking prerequisites..."

# Check jq and curl
missing_deps=()
for dep in curl jq; do
    if command -v "$dep" >/dev/null 2>&1; then
        log_ok "Found '$dep'"
    else
        missing_deps+=("$dep")
    fi
done

if [ ${#missing_deps[@]} -gt 0 ]; then
    log_warn "Missing required utility: ${missing_deps[*]}"
    echo "  -> Please install using your package manager (e.g. 'sudo apt install curl jq' or 'brew install curl jq')."
fi

# Check Ollama
OLLAMA_BIN="$(command -v ollama 2>/dev/null || echo "$HOME/.local/bin/ollama")"
if [ -x "$OLLAMA_BIN" ]; then
    log_ok "Found Ollama: $OLLAMA_BIN"
else
    log_info "Ollama binary not found in standard PATH (optional if using remote/llama.cpp backend)."
fi

# Ensure script permissions
if [ -f "$SCRIPT_DIR/zako.sh" ] && [ ! -x "$SCRIPT_DIR/zako.sh" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
        chmod +x "$SCRIPT_DIR/zako.sh"
    fi
fi
if [ -f "$SCRIPT_DIR/zako-daemon.sh" ] && [ ! -x "$SCRIPT_DIR/zako-daemon.sh" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
        chmod +x "$SCRIPT_DIR/zako-daemon.sh"
    fi
fi

# ==============================================================================
# STEP 2: Install Hook Binary Symlink (~/.local/bin/zako.sh)
# ==============================================================================
echo ""
log_step "2/5" "Setting up hook binary symlink..."

BIN_DIR="$HOME/.local/bin"
TARGET_LINK="$BIN_DIR/zako.sh"

if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[Dry-Run] Would create directory $BIN_DIR"
    log_info "[Dry-Run] Would symlink $SCRIPT_DIR/zako.sh -> $TARGET_LINK"
else
    mkdir -p "$BIN_DIR"
    ln -sf "$SCRIPT_DIR/zako.sh" "$TARGET_LINK"
    log_ok "Symlinked $SCRIPT_DIR/zako.sh -> $TARGET_LINK"
fi

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    log_warn "$BIN_DIR is not currently in your \$PATH!"
    echo "  -> Make sure to add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your shell profile."
fi

# ==============================================================================
# STEP 3: Shell Hook Integration
# ==============================================================================
echo ""
log_step "3/5" "Configuring shell hooks..."

# Detect shell
detected_shell="bash"
user_shell="$(basename "${SHELL:-bash}")"
if [[ "$user_shell" =~ (zsh|fish|bash) ]]; then
    detected_shell="$user_shell"
fi

chosen_shell="$TARGET_SHELL"
if [ "$chosen_shell" = "auto" ]; then
    chosen_shell="$detected_shell"
fi

install_bash_hook() {
    local rc_file="$1"
    if [ ! -f "$rc_file" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[Dry-Run] Would create $rc_file"
        else
            touch "$rc_file"
        fi
    fi

    if grep -qE "zako\.sh|_zako_precmd|# >>> zako-shell >>>" "$rc_file" 2>/dev/null; then
        log_ok "Bash hook already present in $rc_file (skipping)."
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[Dry-Run] Would append Bash hook block to $rc_file"
    else
        # Backup before appending
        local timestamp
        timestamp="$(date +%Y%m%d_%H%M%S)"
        cp "$rc_file" "$rc_file.bak.$timestamp" 2>/dev/null || true

        cat >> "$rc_file" << 'HOOK_EOF'

# >>> zako-shell >>>
_ZAKO_RAN=0
PS0='${_ZAKO_RAN:(_ZAKO_RAN=1,0):0}'"${PS0-}"
_zako_precmd() {
    local code=$?
    if [ "${_ZAKO_RAN:-0}" -eq 1 ] && [ "$code" -ne 0 ]; then
        ~/.local/bin/zako.sh "$code" "$(HISTTIMEFORMAT= history 1 2>/dev/null | sed 's/^[ ]*[0-9]*[ ]*//')"
    fi
    _ZAKO_RAN=0
}
PROMPT_COMMAND="_zako_precmd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
# <<< zako-shell <<<
HOOK_EOF
        log_ok "Injected Bash hook into $rc_file (backup saved: $(basename "$rc_file.bak.$timestamp"))"
    fi
}

install_zsh_hook() {
    local rc_file="$1"
    if [ ! -f "$rc_file" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[Dry-Run] Would create $rc_file"
        else
            touch "$rc_file"
        fi
    fi

    if grep -qE "zako\.sh|_ZAKO_LAST_CMD|# >>> zako-shell >>>" "$rc_file" 2>/dev/null; then
        log_ok "Zsh hook already present in $rc_file (skipping)."
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[Dry-Run] Would append Zsh hook block to $rc_file"
    else
        local timestamp
        timestamp="$(date +%Y%m%d_%H%M%S)"
        cp "$rc_file" "$rc_file.bak.$timestamp" 2>/dev/null || true

        cat >> "$rc_file" << 'HOOK_EOF'

# >>> zako-shell >>>
preexec() { _ZAKO_LAST_CMD="$1"; }
precmd() {
    local code=$?
    if [ $code -ne 0 ] && [ -n "$_ZAKO_LAST_CMD" ]; then
        ~/.local/bin/zako.sh "$code" "$_ZAKO_LAST_CMD"
        _ZAKO_LAST_CMD=""
    fi
}
# <<< zako-shell <<<
HOOK_EOF
        log_ok "Injected Zsh hook into $rc_file (backup saved: $(basename "$rc_file.bak.$timestamp"))"
    fi
}

install_fish_hook() {
    local rc_file="$1"
    local config_dir
    config_dir="$(dirname "$rc_file")"

    if [ ! -f "$rc_file" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[Dry-Run] Would create directory $config_dir and $rc_file"
        else
            mkdir -p "$config_dir"
            touch "$rc_file"
        fi
    fi

    if grep -qE "zako\.sh|__zako_fail|# >>> zako-shell >>>" "$rc_file" 2>/dev/null; then
        log_ok "Fish hook already present in $rc_file (skipping)."
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[Dry-Run] Would append Fish hook block to $rc_file"
    else
        local timestamp
        timestamp="$(date +%Y%m%d_%H%M%S)"
        cp "$rc_file" "$rc_file.bak.$timestamp" 2>/dev/null || true

        cat >> "$rc_file" << 'HOOK_EOF'

# >>> zako-shell >>>
function __zako_fail --on-event fish_postexec
    if test $status -ne 0
        ~/.local/bin/zako.sh $status "$argv[1]"
    end
end
# <<< zako-shell <<<
HOOK_EOF
        log_ok "Injected Fish hook into $rc_file (backup saved: $(basename "$rc_file.bak.$timestamp"))"
    fi
}

case "$chosen_shell" in
    bash)
        install_bash_hook "$HOME/.bashrc"
        ;;
    zsh)
        install_zsh_hook "$HOME/.zshrc"
        ;;
    fish)
        install_fish_hook "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
        ;;
    all)
        install_bash_hook "$HOME/.bashrc"
        install_zsh_hook "$HOME/.zshrc"
        install_fish_hook "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
        ;;
    *)
        log_warn "Unrecognized shell '$chosen_shell', defaulting to Bash hook in ~/.bashrc."
        install_bash_hook "$HOME/.bashrc"
        ;;
esac

# ==============================================================================
# STEP 4: Ollama Model Setup
# ==============================================================================
echo ""
log_step "4/5" "Setting up persona model..."

if [ "$MODEL_CHOICE" = "none" ] || [ "$SETUP_MODEL" -eq 0 ]; then
    log_info "Skipping model setup as requested."
else
    if [ -x "$OLLAMA_BIN" ]; then
        if [ "$NON_INTERACTIVE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
            echo -e "  Select your preferred Mesugaki model scale:"
            echo -e "    1) ${BOLD}1.5b${RESET} (Recommended default: rich wit & zero latency)"
            echo -e "    2) ${BOLD}3b${RESET}   (High wit & devastating nuance)"
            echo -e "    3) ${BOLD}0.5b${RESET} (Ultra-lightweight / low RAM)"
            echo -e "    4) Skip model build"
            read -rp "  Enter choice [1-4] (default: 1): " mc
            case "$mc" in
                2|3b|3B) MODEL_CHOICE="3b" ;;
                3|0.5b|0.5B) MODEL_CHOICE="0.5b" ;;
                4|skip|none) MODEL_CHOICE="none" ;;
                *) MODEL_CHOICE="1.5b" ;;
            esac
        fi

        if [ "$MODEL_CHOICE" != "none" ]; then
            # Check if Ollama daemon is currently responsive
            ollama_running=0
            if curl -s --max-time 1 "http://127.0.0.1:11434/" 2>/dev/null | grep -q "Ollama is running"; then
                ollama_running=1
            fi

            target_base="qwen2.5:$MODEL_CHOICE"
            target_model="zako-tease"
            modelfile="$SCRIPT_DIR/Modelfiles/Modelfile.1.5b"
            if [ "$MODEL_CHOICE" = "3b" ]; then
                target_model="zako-tease:3b"
                modelfile="$SCRIPT_DIR/Modelfiles/Modelfile.3b"
            elif [ "$MODEL_CHOICE" = "0.5b" ]; then
                target_model="zako-tease:0.5b"
                modelfile="$SCRIPT_DIR/Modelfiles/Modelfile.0.5b"
            fi

            if [ "$DRY_RUN" -eq 1 ]; then
                log_info "[Dry-Run] Would run: '$OLLAMA_BIN pull $target_base'"
                log_info "[Dry-Run] Would run: '$OLLAMA_BIN create $target_model -f $modelfile'"
            else
                if [ "$ollama_running" -eq 0 ]; then
                    log_warn "Ollama daemon is not currently running on port 11434."
                    echo "  -> Start it with '$OLLAMA_BIN serve' or './zako-daemon.sh start'."
                    echo "  -> Then run: 'ollama pull $target_base && ollama create $target_model -f $modelfile'"
                else
                    log_info "Pulling base model '$target_base'..."
                    "$OLLAMA_BIN" pull "$target_base"
                    log_info "Creating personalized '$target_model' model..."
                    "$OLLAMA_BIN" create "$target_model" -f "$modelfile"
                    log_ok "Model '$target_model' successfully built and ready ♡"
                fi
            fi
        fi
    else
        log_info "Ollama not installed. Skipping model build (run with BACKEND=llama.cpp or install Ollama)."
    fi
fi

# ==============================================================================
# STEP 5: Voice Setup & Systemd Services (Optional)
# ==============================================================================
echo ""
log_step "5/5" "Configuring optional services..."

# Voice environment
if [ "$SETUP_VOICE" -eq 1 ]; then
    log_info "Setting up Python voice environment (.venv)..."
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[Dry-Run] Would create .venv and install voice dependencies (sherpa-onnx, soundfile, infer-rvc-python)"
    else
        if command -v uv >/dev/null 2>&1; then
            uv venv --python 3.10 "$SCRIPT_DIR/.venv" || uv venv "$SCRIPT_DIR/.venv"
            uv pip install --python "$SCRIPT_DIR/.venv" "sherpa-onnx==1.10.46" soundfile numpy "setuptools<82" "librosa>=0.10" infer-rvc-python
        elif command -v python3 >/dev/null 2>&1; then
            python3 -m venv "$SCRIPT_DIR/.venv"
            "$SCRIPT_DIR/.venv/bin/pip" install --upgrade pip
            "$SCRIPT_DIR/.venv/bin/pip" install "sherpa-onnx==1.10.46" soundfile numpy "setuptools<82" "librosa>=0.10" infer-rvc-python
        else
            log_warn "python3 not found; could not create .venv."
        fi
        log_ok "Voice environment prepared in $SCRIPT_DIR/.venv."
    fi
else
    log_info "Voice synthesis (.venv) skipped (enable anytime with './install.sh --with-voice')."
fi

# Systemd user services
if [ "$SETUP_SYSTEMD" -eq 1 ]; then
    SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[Dry-Run] Would install and enable systemd user units in $SYSTEMD_USER_DIR"
    else
        mkdir -p "$SYSTEMD_USER_DIR"
        
        # Customize zako-voice.service with dynamic SCRIPT_DIR
        if [ -f "$SCRIPT_DIR/zako-voice.service" ]; then
            sed "s|%h/Projects/zako-shell|$SCRIPT_DIR|g" "$SCRIPT_DIR/zako-voice.service" > "$SYSTEMD_USER_DIR/zako-voice.service"
            log_ok "Installed $SYSTEMD_USER_DIR/zako-voice.service"
        fi

        # Install zako-daemon.service
        if [ -f "$SCRIPT_DIR/zako-daemon.service" ]; then
            # Adjust ollama path if needed
            if [ -x "$OLLAMA_BIN" ]; then
                sed "s|%h/.local/bin/ollama|$OLLAMA_BIN|g" "$SCRIPT_DIR/zako-daemon.service" > "$SYSTEMD_USER_DIR/zako-daemon.service"
            else
                cp "$SCRIPT_DIR/zako-daemon.service" "$SYSTEMD_USER_DIR/zako-daemon.service"
            fi
            log_ok "Installed $SYSTEMD_USER_DIR/zako-daemon.service"
        fi

        if command -v systemctl >/dev/null 2>&1; then
            systemctl --user daemon-reload
            systemctl --user enable --now zako-daemon zako-voice 2>/dev/null || true
            log_ok "Enabled and started systemd user units."
        fi
    fi
else
    log_info "Systemd background units skipped (enable anytime with './install.sh --systemd')."
fi

# ==============================================================================
# FINISHED!
# ==============================================================================
echo ""
echo -e "${GREEN}${BOLD}================================================================${RESET}"
if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}${BOLD}  Dry-run simulation completed! No changes were made.${RESET}"
else
    echo -e "${GREEN}${BOLD}  zako-shell has been installed successfully! ♡${RESET}"
fi
echo -e "${GREEN}${BOLD}================================================================${RESET}"
echo ""
echo -e "${CYAN}${BOLD}To activate zako-shell immediately in your current terminal session, run:${RESET}"
case "$chosen_shell" in
    zsh)  echo -e "  ${BOLD}source ~/.zshrc${RESET}" ;;
    fish) echo -e "  ${BOLD}source ~/.config/fish/config.fish${RESET}" ;;
    *)    echo -e "  ${BOLD}source ~/.bashrc${RESET}" ;;
esac
echo ""
echo -e "${CYAN}${BOLD}Test roast directly:${RESET}"
echo -e "  ${BOLD}~/.local/bin/zako.sh 1 \"git psh\"${RESET}"
echo ""
echo -e "${MAGENTA}${BOLD}\"Fwahaha~ You're all set up! Try typing a garbage command and see what happens, Zako~♡!\"${RESET}"
echo ""
