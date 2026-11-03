#!/usr/bin/env python3
"""
zako-voice.py - Audio speech synthesis for zako-shell powered by Kokoro-ONNX.
Enforces audible Hostile Ergonomics whenever Zako triggers exit code != 0.
"""

import os
import sys
import re

# Resolve directories relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(SCRIPT_DIR, "voices")
DEFAULT_MODEL_PATH = os.path.join(MODEL_DIR, "kokoro-v1.0.onnx")
DEFAULT_VOICES_PATH = os.path.join(MODEL_DIR, "voices-v1.0.bin")

MODEL_PATH = os.environ.get("ZAKO_VOICE_MODEL", DEFAULT_MODEL_PATH)
VOICES_PATH = os.environ.get("ZAKO_VOICE_BIN", DEFAULT_VOICES_PATH)
VOICE_NAME = os.environ.get("ZAKO_VOICE_SPEAKER", "af_bella")
VOICE_SPEED = float(os.environ.get("ZAKO_VOICE_SPEED", "1.1"))


def clean_text_for_speech(text: str) -> str:
    """Strip ANSI escape codes and clean characters that phoneticize awkwardly."""
    # Strip terminal ANSI color codes
    ansi_regex = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    clean = ansi_regex.sub("", text)
    # Strip daemon prefix if present
    clean = re.sub(r"^🐟\s*:\s*", "", clean)
    # Tilde / heart formatting for smoother vocal landing
    clean = clean.replace("~♡", "...").replace("♡", "")
    # General cleanup
    clean = clean.strip()
    return clean


def play_audio(samples, sample_rate):
    """Play audio via PipeWire/PulseAudio (pw-play/paplay) or sounddevice."""
    import tempfile
    import subprocess
    import soundfile as sf

    # Prefer pw-play / paplay on Linux to route directly to active PipeWire/Bluetooth sink
    for player in ["pw-play", "paplay"]:
        if subprocess.call(["which", player], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                tmp_path = tmp.name
                sf.write(tmp_path, samples, sample_rate)
            try:
                subprocess.run([player, tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            finally:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
            return

    # Fallback to sounddevice
    try:
        import sounddevice as sd
        sd.play(samples, sample_rate)
        sd.wait()
    except Exception:
        pass


def main():
    if len(sys.argv) < 2 or not sys.argv[1].strip():
        return

    raw_text = sys.argv[1]
    text = clean_text_for_speech(raw_text)
    if not text:
        return

    if not os.path.isfile(MODEL_PATH) or not os.path.isfile(VOICES_PATH):
        # Gracefully exit if model files are not yet downloaded
        return

    try:
        from kokoro_onnx import Kokoro
        kokoro = Kokoro(MODEL_PATH, VOICES_PATH)
        samples, sample_rate = kokoro.create(text, voice=VOICE_NAME, speed=VOICE_SPEED, lang="en-us")
        play_audio(samples, sample_rate)
    except Exception as e:
        # In hostile ergonomics, audio errors fail silently to never block the terminal prompt
        pass


if __name__ == "__main__":
    main()
