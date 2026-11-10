#!/usr/bin/env bash
# ==============================================================================
# zako-shell ♡ - The Hostile Ergonomics Terminal Hook
# Uninstallation & Complete Cleanup Script
# "Haaaaah? Giving up and ragequitting already, Zako~♡?"
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

# Options
NON_INTERACTIVE=0
DRY_RUN=0
PURGE_MODELS=0
KEEP_MODELS=0
PURGE_VENV=0
KEEP_VENV=0

usage() {
    echo -e "${BOLD}zako-shell ♡ Uninstallation Script${RESET}

${BOLD}Usage:${RESET}
  $0 [options]

${BOLD}Options:${RESET}
  -y, --yes, --force     Non-interactive mode (proceed without confirmation prompts)
  --all, --purge-all     Full purge: removes services, binary symlink, shell hooks,
                         runtime logs/PIDs, Ollama models (zako-tease*), and .venv
  --purge-models         Remove Ollama models (zako-tease*) without prompting
  --keep-models          Preserve Ollama models (do not delete or prompt)
  --purge-venv           Remove Python voice environment (.venv) without prompting
  --keep-venv            Preserve Python voice environment (.venv)
  --dry-run              Show what would be cleaned without modifying anything
  -h, --help             Show this help message
"
    exit 0
}

# Parse CLI arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes|--force)
            NON_INTERACTIVE=1
            ;;
        --all|--purge-all)
            NON_INTERACTIVE=1
            PURGE_MODELS=1
            PURGE_VENV=1
            ;;
        --purge-models)
            PURGE_MODELS=1
            ;;
        --keep-models)
            KEEP_MODELS=1
            ;;
        --purge-venv)
            PURGE_VENV=1
            ;;
        --keep-venv)
            KEEP_VENV=1
            ;;
        --dry-run)
            DRY_RUN=1
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
  │    "Haaaaah? Giving up and ragequitting already, Zako~♡?"   │
  └─────────────────────────────────────────────────────────────┘
EOF
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}${BOLD}[DRY RUN MODE]${RESET} Simulation only — no files or settings will be modified."
    echo ""
fi

# Confirmation prompt for interactive mode
if [ "$NON_INTERACTIVE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    echo -e "${MAGENTA}${BOLD}Are you sure you want to uninstall zako-shell and restore your peaceful terminal?${RESET}"
    read -rp "Uninstall zako-shell? [y/N]: " confirm_choice
    case "$confirm_choice" in
        [yY]|[yY][eE][sS])
            echo ""
            ;;
        *)
            echo -e "${CYAN}Aborted! The abuse continues as scheduled, Zako~♡ (๑˃ᴗ˂)ﻭ${RESET}"
            exit 0
            ;;
    esac
fi

# Helper functions
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
# STEP 1: Systemd User Services
# ==============================================================================
log_step "1/6" "Stopping and removing systemd user services..."
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICES=("zako-voice.service" "zako-daemon.service")

if command -v systemctl >/dev/null 2>&1; then
    for s in "${SERVICES[@]}"; do
        if systemctl --user is-active --quiet "$s" 2>/dev/null || systemctl --user is-enabled --quiet "$s" 2>/dev/null; then
            if [ "$DRY_RUN" -eq 1 ]; then
                log_info "[Dry-Run] Would stop & disable systemd user unit: $s"
            else
                systemctl --user stop "$s" 2>/dev/null || true
                systemctl --user disable "$s" 2>/dev/null || true
                log_ok "Stopped & disabled $s"
            fi
        fi
    done
fi

for s in "${SERVICES[@]}"; do
    target_unit="$SYSTEMD_USER_DIR/$s"
    if [ -f "$target_unit" ] || [ -L "$target_unit" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[Dry-Run] Would remove unit file: $target_unit"
        else
            rm -f "$target_unit"
            log_ok "Removed $target_unit"
        fi
    fi
done

if command -v systemctl >/dev/null 2>&1 && [ "$DRY_RUN" -eq 0 ]; then
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user reset-failed 2>/dev/null || true
fi
log_ok "Systemd user services check complete."

# ==============================================================================
# STEP 2: Background Daemons & Runtime / Temporary Files
# ==============================================================================
echo ""
log_step "2/6" "Stopping background daemons and cleaning runtime files..."

# Invoke zako-daemon.sh stop if script exists
if [ -x "$SCRIPT_DIR/zako-daemon.sh" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[Dry-Run] Would invoke $SCRIPT_DIR/zako-daemon.sh stop"
    else
        "$SCRIPT_DIR/zako-daemon.sh" stop >/dev/null 2>&1 || true
        log_ok "Invoked zako-daemon.sh stop"
    fi
fi

# Clean runtime PIDs / logs
RUNTIME_FILES=(
    "/tmp/zako-daemon.pid"
    "/tmp/zako-daemon.log"
    "/tmp/zako-voice-daemon.pid"
    "/tmp/zako-voice-daemon.log"
    "/tmp/.zako_last_cmd"
)

for rf in "${RUNTIME_FILES[@]}"; do
    if [ -f "$rf" ]; then
        # If it's a PID file, ensure process is terminated
        if [[ "$rf" == *.pid ]]; then
            pid=$(cat "$rf" 2>/dev/null || echo "")
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                if [ "$DRY_RUN" -eq 1 ]; then
                    log_info "[Dry-Run] Would kill lingering daemon process (PID: $pid)"
                else
                    kill "$pid" 2>/dev/null || true
                    sleep 0.2
                    kill -9 "$pid" 2>/dev/null || true
                    log_ok "Terminated process PID $pid"
                fi
            fi
        fi

        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[Dry-Run] Would remove runtime file: $rf"
        else
            rm -f "$rf"
            log_ok "Removed $rf"
        fi
    fi
done

# Clean any ephemeral wav files in /tmp created by zako-voice
if [ "$DRY_RUN" -eq 1 ]; then
    wav_count=$(find /tmp -maxdepth 1 -name "zako_voice_*.wav" 2>/dev/null | wc -l)
    if [ "$wav_count" -gt 0 ]; then
        log_info "[Dry-Run] Would clean $wav_count temporary audio file(s) in /tmp"
    fi
else
    find /tmp -maxdepth 1 -name "zako_voice_*.wav" -delete 2>/dev/null || true
fi
log_ok "Runtime and daemon processes cleaned."

# ==============================================================================
# STEP 3: Binary Symlink & Executable
# ==============================================================================
echo ""
log_step "3/6" "Removing hook binary symlink..."
BIN_PATHS=(
    "$HOME/.local/bin/zako.sh"
    "$HOME/.local/bin/zako"
)

found_bin=0
for bp in "${BIN_PATHS[@]}"; do
    if [ -L "$bp" ] || [ -f "$bp" ]; then
        found_bin=1
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[Dry-Run] Would remove binary / symlink: $bp"
        else
            rm -f "$bp"
            log_ok "Removed $bp"
        fi
    fi
done

if [ "$found_bin" -eq 0 ]; then
    log_ok "No symlinks found in ~/.local/bin/."
fi

# ==============================================================================
# STEP 4: Shell Configuration Hooks
# ==============================================================================
echo ""
log_step "4/6" "Cleaning shell configuration hooks..."

TARGET_SHELL_FILES=(
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.zshrc"
    "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
)

# Use Python 3 for safe, AST-level/clean regex block removal with automatic timestamped backup
clean_shell_with_python() {
    python3 - "$1" "$DRY_RUN" << 'PYEOF'
import os, sys, re, shutil
from datetime import datetime

filepath = sys.argv[1]
dry_run = sys.argv[2] == "1"

if not os.path.isfile(filepath):
    sys.exit(0)

with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
    orig = f.read()

# 1. Tagged block removal if marked
content = re.sub(r'#\s*>>>\s*zako-shell\s*>>>.*?#\s*<<<\s*zako-shell\s*<<<\n?', '', orig, flags=re.DOTALL)

lines = content.splitlines(keepends=True)
out = []
i = 0
modified = (content != orig)

while i < len(lines):
    line = lines[i]

    # Bash precmd block
    if '# zako-shell:' in line or '_ZAKO_RAN=0' in line:
        window = ''.join(lines[i:i+15])
        if '_zako_precmd' in window and 'zako.sh' in window:
            modified = True
            while i < len(lines):
                curr = lines[i]
                i += 1
                if 'PROMPT_COMMAND=' in curr and '_zako_precmd' in curr:
                    break
                if curr.strip() == '}' and i < len(lines) and 'PROMPT_COMMAND=' not in lines[i]:
                    break
            continue

    # Zsh preexec/precmd block
    if 'preexec()' in line and '_ZAKO_LAST_CMD' in line:
        window = ''.join(lines[i:i+15])
        if 'precmd()' in window and 'zako.sh' in window:
            modified = True
            brace_count = 0
            started = False
            while i < len(lines):
                curr = lines[i]
                brace_count += curr.count('{') - curr.count('}')
                i += 1
                if 'precmd()' in curr:
                    started = True
                if started and brace_count == 0:
                    break
            continue

    # Fish function __zako_fail block
    if 'function __zako_fail' in line:
        modified = True
        depth = 1
        i += 1
        while i < len(lines) and depth > 0:
            curr = lines[i]
            if any(curr.strip().startswith(kw) for kw in ['if ', 'for ', 'while ', 'switch ', 'function ']):
                depth += 1
            elif curr.strip() == 'end':
                depth -= 1
            i += 1
        continue

    # Environment variables: export ZAKO_*
    if re.match(r'^\s*export\s+ZAKO_[A-Za-z0-9_]+=.*$', line):
        modified = True
        i += 1
        continue

    # Standalone command execution referencing zako.sh
    if 'zako.sh' in line and not line.strip().startswith('#'):
        modified = True
        i += 1
        continue

    out.append(line)
    i += 1

cleaned = ''.join(out)
cleaned = re.sub(r'\n{3,}', '\n\n', cleaned)

if cleaned != orig:
    modified = True

if modified:
    if dry_run:
        print(f"DRY_RUN:{filepath}")
    else:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        bak_file = f"{filepath}.bak.{timestamp}"
        shutil.copy2(filepath, bak_file)
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(cleaned)
        print(f"CLEANED:{filepath}:{bak_file}")
PYEOF
}

cleaned_any=0
for sf in "${TARGET_SHELL_FILES[@]}"; do
    if [ -f "$sf" ]; then
        if grep -qE "zako\.sh|_ZAKO_RAN|_zako_precmd|__zako_fail|ZAKO_VOICE|ZAKO_MODEL|zako-shell" "$sf" 2>/dev/null; then
            res=$(clean_shell_with_python "$sf")
            if [[ "$res" == DRY_RUN:* ]]; then
                log_info "[Dry-Run] Would remove zako-shell hook block from $sf"
                cleaned_any=1
            elif [[ "$res" == CLEANED:* ]]; then
                bak_path=$(echo "$res" | cut -d: -f3)
                log_ok "Cleaned $sf (backup saved to $(basename "$bak_path"))"
                cleaned_any=1
            fi
        fi
    fi
done

if [ "$cleaned_any" -eq 0 ]; then
    log_ok "No zako-shell hooks found in shell configuration files."
fi

# ==============================================================================
# STEP 5: Ollama Models (Optional / Interactive)
# ==============================================================================
echo ""
log_step "5/6" "Checking Ollama custom models..."

if command -v ollama >/dev/null 2>&1; then
    # List models matching zako-tease
    models_found=$(ollama list 2>/dev/null | awk '{print $1}' | grep -E '^zako-tease(:.*)?$' || true)
    if [ -n "$models_found" ]; then
        echo -e "  Found Ollama models:"
        while IFS= read -r m; do
            echo -e "    ${MAGENTA}•${RESET} $m"
        done <<< "$models_found"

        remove_models=0
        if [ "$PURGE_MODELS" -eq 1 ]; then
            remove_models=1
        elif [ "$KEEP_MODELS" -eq 1 ]; then
            remove_models=0
        elif [ "$NON_INTERACTIVE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
            read -rp "  Delete these Ollama zako models to reclaim disk space? [y/N]: " model_choice
            case "$model_choice" in
                [yY]|[yY][eE][sS]) remove_models=1 ;;
                *) remove_models=0 ;;
            esac
        fi

        if [ "$remove_models" -eq 1 ]; then
            while IFS= read -r m; do
                if [ -n "$m" ]; then
                    if [ "$DRY_RUN" -eq 1 ]; then
                        log_info "[Dry-Run] Would delete Ollama model: $m"
                    else
                        ollama rm "$m" >/dev/null 2>&1 || true
                        log_ok "Deleted Ollama model $m"
                    fi
                fi
            done <<< "$models_found"
        else
            log_info "Retained Ollama models."
        fi
    else
        log_ok "No zako-tease models found in Ollama."
    fi
else
    log_ok "Ollama not installed or not in PATH."
fi

# ==============================================================================
# STEP 6: Virtual Environment (.venv) Cleanup
# ==============================================================================
echo ""
log_step "6/6" "Checking Python voice virtual environment (.venv)..."

if [ -d "$SCRIPT_DIR/.venv" ]; then
    remove_venv=0
    if [ "$PURGE_VENV" -eq 1 ]; then
        remove_venv=1
    elif [ "$KEEP_VENV" -eq 1 ]; then
        remove_venv=0
    elif [ "$NON_INTERACTIVE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
        read -rp "  Delete local Python voice environment ($SCRIPT_DIR/.venv)? [y/N]: " venv_choice
        case "$venv_choice" in
            [yY]|[yY][eE][sS]) remove_venv=1 ;;
            *) remove_venv=0 ;;
        esac
    fi

    if [ "$remove_venv" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[Dry-Run] Would delete directory: $SCRIPT_DIR/.venv"
        else
            rm -rf "$SCRIPT_DIR/.venv"
            log_ok "Deleted $SCRIPT_DIR/.venv"
        fi
    else
        log_info "Retained .venv."
    fi
else
    log_ok "No local .venv found in $SCRIPT_DIR."
fi

# ==============================================================================
# FINISHED!
# ==============================================================================
echo ""
echo -e "${GREEN}${BOLD}================================================================${RESET}"
if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}${BOLD}  Dry-run simulation completed! No changes were made.${RESET}"
else
    echo -e "${GREEN}${BOLD}  zako-shell has been completely uninstalled! ♡${RESET}"
fi
echo -e "${GREEN}${BOLD}================================================================${RESET}"
echo ""
echo -e "${CYAN}${BOLD}To apply changes to your current terminal session immediately, run:${RESET}"
echo -e "  ${BOLD}source ~/.bashrc${RESET}   # (or restart your shell session)"
echo ""
echo -e "${MAGENTA}${BOLD}\"Fwahaha~ Enjoy your quiet, boring terminal where nobody laughs at your typos, Zako~♡!\"${RESET}"
echo ""
