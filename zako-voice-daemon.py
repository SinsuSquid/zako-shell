#!/usr/bin/env python3
"""
zako-voice-daemon.py - Persistent background audio daemon for zako-shell.
Preloads sherpa-onnx (GLaDOS) and optional RVC voice conversion (Miku, pitch +7)
to eliminate model load latency and deliver instant vocal roasts.
"""

import os
import sys
import tempfile
import subprocess
import threading
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
import soundfile as sf
import numpy as np

# Ensure torch.load can load legacy weights if torch / RVC is used
try:
    import torch
    _orig_torch_load = torch.load

    def _patched_torch_load(*args, **kwargs):
        if "weights_only" not in kwargs:
            kwargs["weights_only"] = False
        return _orig_torch_load(*args, **kwargs)

    torch.load = _patched_torch_load
except ImportError:
    pass

# Import text sanitization and chunking from zako-voice
import importlib.util
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
voice_spec = importlib.util.spec_from_file_location("zako_voice", os.path.join(SCRIPT_DIR, "zako-voice.py"))
zako_voice = importlib.util.module_from_spec(voice_spec)
voice_spec.loader.exec_module(zako_voice)

# Configuration
HOST = os.environ.get("ZAKO_VOICE_HOST", "127.0.0.1")
PORT = int(os.environ.get("ZAKO_VOICE_PORT", "11435"))
ENABLE_RVC = os.environ.get("ZAKO_RVC", "0").lower() in ("1", "true", "yes")

# Base TTS (sherpa-onnx) paths
MODEL_DIR = os.path.join(SCRIPT_DIR, "voices", "vits-piper-en_US-glados")
MODEL_PATH = os.environ.get("ZAKO_VOICE_MODEL", os.path.join(MODEL_DIR, "en_US-glados.onnx"))
TOKENS_PATH = os.environ.get("ZAKO_VOICE_TOKENS", os.path.join(MODEL_DIR, "tokens.txt"))
DATA_DIR = os.environ.get("ZAKO_VOICE_DATA", os.path.join(MODEL_DIR, "espeak-ng-data"))
VOICE_SPEED = float(os.environ.get("ZAKO_VOICE_SPEED", "1.0"))

# RVC Paths & Settings (default: local voices/infamous_miku_v2 with fallback)
LOCAL_RVC_DIR = os.path.join(SCRIPT_DIR, "voices", "infamous_miku_v2")
EXT_RVC_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "Open-LLM-VTuber_RVC", "models", "rvc", "infamous_miku_v2"))
DEFAULT_RVC_DIR = LOCAL_RVC_DIR if os.path.isdir(LOCAL_RVC_DIR) else EXT_RVC_DIR
RVC_MODEL_PATH = os.environ.get("ZAKO_RVC_MODEL", os.path.join(DEFAULT_RVC_DIR, "infamous_miku_v2.pth"))
RVC_INDEX_PATH = os.environ.get("ZAKO_RVC_INDEX", os.path.join(DEFAULT_RVC_DIR, "added_IVF2983_Flat_nprobe_1_infamous_miku_v2_v2.index"))
RVC_PITCH = int(os.environ.get("ZAKO_RVC_PITCH", "8"))
RVC_DEVICE = os.environ.get("ZAKO_RVC_DEVICE", "cpu:0")
RVC_METHOD = os.environ.get("ZAKO_RVC_METHOD", "pm")


class VoiceServer:
    def __init__(self):
        self.tts = None
        self.rvc = None
        self.lock = threading.Lock()
        self._init_engines()

    def _init_engines(self):
        print(f"[*] Initializing sherpa-onnx (GLaDOS)...")
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
        self.tts = sherpa_onnx.OfflineTts(config)
        print("  ✓ Base TTS engine ready.")

        if ENABLE_RVC:
            if not os.path.isfile(RVC_MODEL_PATH):
                print(f"[!] Warning: RVC model not found at '{RVC_MODEL_PATH}'. Running without RVC.")
                return

            print(f"[*] Initializing RVC engine via infer_rvc_python (Miku, pitch={RVC_PITCH}, method={RVC_METHOD})...")
            try:
                from infer_rvc_python import BaseLoader
                self.rvc = BaseLoader(only_cpu=True)
                self.rvc.apply_conf(
                    tag="miku",
                    file_model=RVC_MODEL_PATH,
                    pitch_algo=RVC_METHOD,
                    pitch_lvl=RVC_PITCH,
                    file_index=RVC_INDEX_PATH if os.path.isfile(RVC_INDEX_PATH) else "",
                    index_influence=0.75,
                )
                # Warm up pipeline with 0.1s silence
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as w_in:
                    sf.write(w_in.name, np.zeros(16000, dtype=np.float32), 16000)
                    warm_out = self.rvc(audio_files=w_in.name, tag_list="miku", show_progress=False)
                    if os.path.exists(w_in.name):
                        os.remove(w_in.name)
                    if warm_out and len(warm_out) > 0 and os.path.exists(warm_out[0]):
                        os.remove(warm_out[0])
                print("  ✓ RVC engine preloaded and warmed up!")
            except Exception as e:
                print(f"[!] Error loading RVC engine: {e}. Running without RVC.")
                self.rvc = None

    def speak(self, text: str):
        """Process and speak text chunk-by-chunk."""
        with self.lock:
            cleaned = zako_voice.clean_text_for_speech(text)
            chunks = zako_voice.split_into_chunks(cleaned)

            for chunk in chunks:
                audio = self.tts.generate(chunk, sid=0, speed=VOICE_SPEED)
                if not audio or len(audio.samples) == 0:
                    continue

                samples = np.array(audio.samples, dtype=np.float32)

                if self.rvc:
                    # Convert via RVC
                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as in_tmp:
                        in_path = in_tmp.name
                        sf.write(in_path, samples, audio.sample_rate)

                    out_path = None
                    try:
                        res = self.rvc(audio_files=in_path, tag_list="miku", show_progress=False)
                        if res and len(res) > 0 and os.path.exists(res[0]):
                            out_path = res[0]
                            subprocess.run(["pw-play", out_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    finally:
                        if os.path.exists(in_path):
                            os.remove(in_path)
                        if out_path and os.path.exists(out_path):
                            os.remove(out_path)
                else:
                    zako_voice.play_audio(samples, audio.sample_rate)


voice_server = None


class VoiceHTTPHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Quiet standard HTTP access logs
        pass

    def do_GET(self):
        if self.path in ("/health", "/status"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            status_data = {
                "status": "ok",
                "rvc_enabled": voice_server.rvc is not None,
                "rvc_pitch": RVC_PITCH if voice_server.rvc else 0,
                "rvc_method": RVC_METHOD if voice_server.rvc else None,
            }
            self.wfile.write(json.dumps(status_data).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/speak":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8", errors="replace")

            # Try to parse JSON or treat as raw text
            text = body
            try:
                data = json.loads(body)
                if isinstance(data, dict) and "text" in data:
                    text = data["text"]
            except Exception:
                pass

            if text.strip():
                # Speak in background thread so the HTTP request unblocks immediately
                threading.Thread(target=voice_server.speak, args=(text,), daemon=True).start()

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"speaking"}')
        else:
            self.send_response(404)
            self.end_headers()


def main():
    global voice_server
    voice_server = VoiceServer()
    server = HTTPServer((HOST, PORT), VoiceHTTPHandler)
    print(f"[*] zako-voice-daemon listening on http://{HOST}:{PORT} (RVC={'ON' if ENABLE_RVC else 'OFF'}) ♡")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping zako-voice-daemon...")
    except Exception as e:
        print(f"\nServer error: {e}")
    finally:
        print("[*] Server shutdown completed.")
        server.server_close()


if __name__ == "__main__":
    main()
