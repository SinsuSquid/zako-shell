#!/usr/bin/env python3
"""
zako-voice.py - Audio speech synthesis for zako-shell powered by sherpa-onnx (VITS GLaDOS).
Enforces audible Hostile Ergonomics whenever Zako triggers exit code != 0.
"""

import os
import sys
import re
import tempfile
import subprocess
import numpy as np
import soundfile as sf

# Resolve directories relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(SCRIPT_DIR, "voices", "vits-piper-en_US-glados")

MODEL_PATH = os.environ.get("ZAKO_VOICE_MODEL", os.path.join(MODEL_DIR, "en_US-glados.onnx"))
TOKENS_PATH = os.environ.get("ZAKO_VOICE_TOKENS", os.path.join(MODEL_DIR, "tokens.txt"))
DATA_DIR = os.environ.get("ZAKO_VOICE_DATA", os.path.join(MODEL_DIR, "espeak-ng-data"))
VOICE_SPEED = float(os.environ.get("ZAKO_VOICE_SPEED", "1.0"))


def clean_text_for_speech(text: str) -> str:
    """
    Hijack and sanitize LLM raw output for optimal TTS phonetics.
    Replaces awkward written anime tropes (e.g., 'Haaah?', 'Zako~♡') with
    crisp, natural phonetics.
    """
    if not text:
        return ""

    # 1. Strip terminal ANSI color codes and shell formatting
    ansi_regex = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    clean = ansi_regex.sub("", text)
    clean = re.sub(r"^🐟\s*:\s*", "", clean)

    # 2. Specific word / trope hijacks for audio:
    # Transform 'Hah?', 'Haaah?', 'Haaaaaaaaaaaaah?' into calibrated 5-vowel anime gasp 'Haaaaah?'
    clean = re.sub(r"(?i)\bh+a+h*\b([?!]*)", r"__MESUGAKI_GASPH__\1", clean)

    # 3. Normalize elongated vowel/consonant screams ('Awwwww' -> 'Aww', 'Nooooo' -> 'Noo')
    clean = re.sub(r"([a-zA-Z])\1{2,}", r"\1\1", clean)
    clean = clean.replace("__MESUGAKI_GASPH__", "Haaaaah")

    # 4. Cleanse 'Zako~♡' and all '~♡' variants
    # Cleanly preserve intended punctuation (!, ?, .) without speaking 'tilde' or 'heart'
    clean = re.sub(r"~\s*[♡♥❤💕]+\s*([?!.]*)", r"\1", clean)
    clean = re.sub(r"~\s*([?!.]*)", r"\1", clean)
    clean = re.sub(r"[~♡♥❤💕]", "", clean)

    # 5. Phonetic pacing hijacks:
    # 'Zako' -> 'Zacco' (sharp, fast, clipped 'a' instead of sluggish elongated 'aa')
    clean = re.sub(r"(?i)\bzako\b", "Zacco", clean)

    # 6. Strip single/double/backtick quotes around command names so TTS doesn't say 'quote'
    clean = re.sub(r"['\"`](\w+)['\"`]", r"\1", clean)

    # 7. Fix double or awkward punctuation
    clean = re.sub(r"\s+([,.?!])", r"\1", clean)
    clean = re.sub(r"\.{2,}", ".", clean)
    clean = re.sub(r"\?+", "?", clean)
    clean = re.sub(r"!+", "!", clean)

    clean = clean.strip()
    if clean and clean[-1] not in ".!?":
        clean += "."

    return clean


def play_audio(samples, sample_rate):
    """Play audio via PipeWire/PulseAudio (pw-play/paplay) or sounddevice."""
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


def split_into_chunks(text: str) -> list[str]:
    """Split text into sentence/prosody chunks for lower latency and distinct intonation."""
    # Split on sentence boundaries (. ! ?) while keeping punctuation attached
    raw_chunks = re.split(r"(?<=[.!?])\s+", text)
    chunks = [c.strip() for c in raw_chunks if c.strip()]
    return chunks if chunks else [text]


def main():
    raw_text = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else sys.stdin.read()
    if not raw_text.strip():
        return

    text = clean_text_for_speech(raw_text)
    if not text:
        return

    if not os.path.isfile(MODEL_PATH) or not os.path.isfile(TOKENS_PATH):
        return

    chunks = split_into_chunks(text)

    try:
        import sherpa_onnx
        config = sherpa_onnx.OfflineTtsConfig(
            model=sherpa_onnx.OfflineTtsModelConfig(
                vits=sherpa_onnx.OfflineTtsVitsModelConfig(
                    model=MODEL_PATH,
                    lexicon="",
                    tokens=TOKENS_PATH,
                    data_dir=DATA_DIR,
                ),
                provider="cpu",
                num_threads=2,
            ),
        )
        tts = sherpa_onnx.OfflineTts(config)
        for chunk in chunks:
            audio = tts.generate(chunk, sid=0, speed=VOICE_SPEED)
            if audio and len(audio.samples) > 0:
                samples = np.array(audio.samples, dtype=np.float32)
                play_audio(samples, audio.sample_rate)
    except Exception:
        pass


if __name__ == "__main__":
    main()
