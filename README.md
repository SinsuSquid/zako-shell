<div align="center">

# > zako-shell ♡

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

**An offline, zero-latency Hostile Ergonomics shell hook powered by `Ollama`**  
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

- **[`Ollama`](https://ollama.com)** (Default): `ollama` installed and running on your system (`ollama serve`).
- *(Optional legacy backend)*: **[`llama.cpp`](https://github.com/ggerganov/llama.cpp)** (`llama-server`) is still supported via `ZAKO_BACKEND=llama.cpp`.
- **`curl` & `jq`**: For querying the local daemon and formatting payloads.
- *Any shell!* (Bash, Zsh, Fish — works natively with or without prompt themes like Starship, Oh-My-Zsh, etc.)

---

## 🚀 Quick Start (Summoning the Daemon)

### 1. Setup Model via Ollama (Recommended & Default)
Pull the base model (default: `qwen2.5:1.5b`) and build the `zako-tease` model with built-in Mesugaki personality:
```bash
# Pull base model
ollama pull qwen2.5:1.5b

# Create the dedicated Zako model
ollama create zako-tease -f Modelfile
```
*(Tip: You can also use `qwen2.5:1.5b` directly without creating a custom model by setting `export ZAKO_MODEL="qwen2.5:1.5b"`!)*

### 2. Verify or Launch the Local Daemon
If Ollama is already running on your machine, you're good to go! You can verify status or start the daemon with:
```bash
# Verify status:
./zako-daemon.sh status

# Start daemon if not running:
./zako-daemon.sh start
```

*(Optional)* Install as a persistent systemd user service:
```bash
mkdir -p ~/.config/systemd/user
cp zako-daemon.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now zako-daemon
```

### 3. Install the Hook Binary
Symlink `zako.sh` into your `$PATH`:
```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/zako.sh" ~/.local/bin/zako.sh

# Run a test roast manually:
zako.sh 1 "git psh"
```

---

## ⚙️ Configuration

Tune your abuse parameters using environment variables in your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

| Variable | Default | Description |
|---|---|---|
| `ZAKO_MODEL` | `zako-tease` | The Ollama model name to tease you with |
| `ZAKO_ENDPOINT` | `http://127.0.0.1:11434/v1/chat/completions` | Local inference API endpoint |
| `ZAKO_TIMEOUT` | `3.5` | Max seconds before giving up (prevents prompt lags) |
| `ZAKO_BACKEND` | `ollama` | Backend engine (`ollama` or `llama.cpp`) |

---

## 🐚 Shell Hook Integration

No complicated prompt theme configuration required! Hook it natively into your favorite shell:

### 1. **Bash**
Add to your `~/.bashrc`:

**If you use Starship**:
```bash
_ZAKO_RAN=0
PS0='${_ZAKO_RAN:(_ZAKO_RAN=1,0):0}'"${PS0-}"
zako_hook() {
    local code=$STARSHIP_CMD_STATUS
    if [ "${_ZAKO_RAN:-0}" -eq 1 ] && [ "$code" -ne 0 ]; then
        ~/.local/bin/zako.sh "$code" "$(HISTTIMEFORMAT= history 1 2>/dev/null | sed 's/^[ ]*[0-9]*[ ]*//')"
    fi
    _ZAKO_RAN=0
}
starship_precmd_user_func="zako_hook"
```

**If you do NOT use Starship**:
```bash
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
```

### 2. **Zsh**
Add to your `~/.zshrc`:
```zsh
preexec() { _ZAKO_LAST_CMD="$1"; }
precmd() {
    local code=$?
    if [ $code -ne 0 ] && [ -n "$_ZAKO_LAST_CMD" ]; then
        ~/.local/bin/zako.sh "$code" "$_ZAKO_LAST_CMD"
        _ZAKO_LAST_CMD=""
    fi
}
```

### 3. **Fish**
Add to your `~/.config/fish/config.fish`:
```fish
function __zako_fail --on-event fish_postexec
    if test $status -ne 0
        ~/.local/bin/zako.sh $status "$argv[1]"
    end
end
```
