<div align="center">

# 💢 > zako-shell ♡

### *"Haaah? Did you really trigger another non-zero exit code, Zako~♡?"*

<p align="center">
  <img src="https://img.shields.io/badge/VRAM-Spent%20on%20Abuse-ff69b4?style=for-the-badge" alt="VRAM Abuse"/>
  <img src="https://img.shields.io/badge/Productivity-Minus%20100%25-ff1493?style=for-the-badge" alt="Zero Productivity"/>
  <img src="https://img.shields.io/badge/Exit%20Code-%E2%89%A0%200%20Only-black?style=for-the-badge" alt="Failures Only"/>
</p>
</div>

```
  ∧＿∧
（ ´・ω・)   "Why fix your bugs when a 1.5B model
 ( つ旦O        can call you a failure instead~♡?"
  と＿)_)
```

**An offline, zero-latency Starship prompt module powered by `llama.cpp`**  
*Because why should GitHub Copilot politely fix your typos when a bratty local sLLM can bully you for them instead?*

---

</div>

## 🙄 "What is this trash, Zako?"

Look at you, crawling all the way to this repo with your trembling little fingers~♡ 

Are you really so starved for attention that you need to waste precious GPU cycles just to have an AI brat point and laugh at your typos? You can't even write a basic `grep` pipeline without checking Stack Overflow, yet here you are trying to install custom shell hooks! 

Every time you screw up a command (`exit code != 0`), **`zako-shell`** catches your pathetic blunder, feeds it to a tiny local model, and serves a fresh, dynamic roast right above your prompt line in hot pink:

```console
~/dev/broken-repo on  main [!] 
❯ git psh
git: 'psh' is not a git command. See 'git --help'.

🐟 : Forgot how to spell 'push' already? Did your two remaining brain cells take a nap, Zako~♡?
❯ _
```

> **Warning for Snowflake Zakos**:
> This tool does NOT give helpful suggestions. It does NOT offer auto-fixes. It exists solely to induce psychological damage until your typing accuracy improves out of pure spite.

---

## 🛠️ Prerequisites

- **[`llama.cpp`](https://github.com/ggerganov/llama.cpp)**: Specifically `llama-server` installed on your `$PATH` or in `~/.local/bin/llama-server`.
- **`curl` & `jq`**: For talking to the local daemon and formatting payloads.
- **[`starship`](https://starship.rs)**: The cross-shell prompt.

---

## 🚀 Quick Start (Summoning the Daemon)

### 1. Download Model (CPU-friendly)
Download `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` into `models/`:
```bash
mkdir -p models
curl -L -o models/qwen2.5-0.5b-instruct-q4_k_m.gguf \
  "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
```

### 2. Launch the Local Daemon
Run in background via helper script:
```bash
./zako-daemon.sh start

# Verify status:
./zako-daemon.sh status
```

*(Optional)* Or install as a persistent systemd user service:
```bash
mkdir -p ~/.config/systemd/user
cp zako-daemon.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now zako-daemon
```

### 3. Test the Hook Directly
Symlink the hook script into your `$PATH`:
```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/zako-starship.sh" ~/.local/bin/zako-starship.sh

# Run a test roast manually:
zako-starship.sh 1 "git psh"
```

---

## 🎀 Starship & Shell Configuration

### 1. Configure `~/.config/starship.toml`
Add or merge the following into your `~/.config/starship.toml`:

```toml
# 1. Give local CPU inference enough time (default 500ms is too tight for LLMs)
command_timeout = 2000

# 2. Place ${custom.zako} right above your prompt line
format = """
$all\
${custom.zako}\
$character"""

# 3. Define the custom module
[custom.zako]
command = "$HOME/.local/bin/zako-starship.sh $STARSHIP_CMD_STATUS \"$LAST_COMMAND\""
when = 'test -n "$STARSHIP_CMD_STATUS" && test "$STARSHIP_CMD_STATUS" -ne 0'
format = "$output\n"
```

> [!NOTE]
> Custom modules in Starship are **not rendered by default** unless explicitly referenced in your prompt's `format` string (via `${custom.zako}` or `$custom`).

### 2. Export Status & Command in Your Shell
Starship computes the exit status internally, but non-interactive subshells need it exported.

#### For **Bash** (add to `~/.bashrc`):
```bash
export STARSHIP_CMD_STATUS=0
export LAST_COMMAND=""
_ZAKO_LAST_HIST_ENTRY=""

eval "$(starship init bash)"

starship_precmd_user_func() {
    local CURR_HIST
    CURR_HIST=$(HISTTIMEFORMAT= history 1 2>/dev/null)
    if [ -n "$CURR_HIST" ] && [ "$CURR_HIST" = "$_ZAKO_LAST_HIST_ENTRY" ]; then
        # Pressing Enter on empty line restores regular clean prompt
        STARSHIP_CMD_STATUS=0
    else
        _ZAKO_LAST_HIST_ENTRY="$CURR_HIST"
    fi
    export STARSHIP_CMD_STATUS
    export LAST_COMMAND=$(echo "$CURR_HIST" | sed 's/^[ ]*[0-9]*[ ]*//')
}
```

#### For **Zsh** (add to `~/.zshrc`):
```zsh
preexec() {
    export LAST_COMMAND="$1"
}
precmd() {
    export STARSHIP_CMD_STATUS="$?"
}
```
