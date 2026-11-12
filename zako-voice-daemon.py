#!/usr/bin/env python3
"""
zako-voice-daemon.py - Persistent background audio daemon for zako-shell.
Powered exclusively by Kasane Teto (重音テト) RVC v2:
- Base TTS: Microsoft Edge-TTS (en-US-AvaNeural)
- Ultra-Fast Direct In-Memory Pipeline:
  * Preloaded HuBERT feature extractor
  * Preloaded RMVPE deep pitch estimator (studio quality)
  * Preloaded FAISS vector retrieval index (zero disk reload lag)
  * Optimized ONNX Runtime engine (KasaneTeto.onnx, 6 threads, ORT_ENABLE_ALL)
- Pitch: +2 (The Calibrated Sweet Spot)
Delivers instant, audible psychological damage (~1.1s latency) whenever exit code != 0.
"""

import os
import sys
import time
import tempfile
import subprocess
import threading
import json
import asyncio
from http.server import HTTPServer, BaseHTTPRequestHandler
import soundfile as sf
import numpy as np

# Ensure torch.load can load weights smoothly
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

# Server Configuration
HOST = os.environ.get("ZAKO_VOICE_HOST", "127.0.0.1")
PORT = int(os.environ.get("ZAKO_VOICE_PORT", "11435"))
ENABLE_RVC = os.environ.get("ZAKO_RVC", "1").lower() in ("1", "true", "yes")

# Base TTS Engine: Edge-TTS
EDGE_VOICE = os.environ.get("ZAKO_EDGE_VOICE", "en-US-AvaNeural")

# Model Paths: Kasane Teto & RMVPE
TETO_ONNX_PATH = os.environ.get("ZAKO_TETO_MODEL", os.path.join(SCRIPT_DIR, "voices", "KasaneTeto.onnx"))
TETO_INDEX_PATH = os.environ.get("ZAKO_TETO_INDEX", os.path.join(SCRIPT_DIR, "voices", "KasaneTeto.index"))
RMVPE_PATH = os.environ.get("ZAKO_RMVPE_PATH", os.path.join(SCRIPT_DIR, "rmvpe.pt"))

# RVC Parameters (Default: +2 pitch, rmvpe method)
RVC_PITCH = int(os.environ.get("ZAKO_RVC_PITCH", "2"))
RVC_METHOD = os.environ.get("ZAKO_RVC_METHOD", "rmvpe")
INDEX_RATE = float(os.environ.get("ZAKO_INDEX_RATE", "0.75"))
CPU_THREADS = int(os.environ.get("ZAKO_CPU_THREADS", "6"))


class DirectOnnxNetG:
    """Zero-overhead ONNX generator caller."""
    def __init__(self, session):
        self.session = session

    def infer(self, phone, phone_lengths, pitch, nsff0, sid, rate=None):
        inputs = {
            "phone": phone.cpu().float().numpy(),
            "phone_lengths": phone_lengths.cpu().numpy(),
            "pitch": pitch.cpu().numpy(),
            "nsff0": nsff0.cpu().float().numpy(),
            "sid": sid.cpu().numpy() if hasattr(sid, "cpu") else np.array([sid], dtype=np.int64),
            "rate": np.array([rate if rate is not None else 1.0], dtype=np.float32),
        }
        out = self.session.run(None, inputs)
        return (torch.from_numpy(out[0]),)


class VoiceServer:
    def __init__(self):
        self.hubert = None
        self.rmvpe = None
        self.pipe = None
        self.net_g = None
        self.index = None
        self.big_npy = None
        self.lock = threading.Lock()
        self._init_engine()

    def _init_engine(self):
        if not ENABLE_RVC:
            print("[*] RVC is disabled by configuration. Running in raw Edge-TTS mode.")
            return

        if not os.path.isfile(TETO_ONNX_PATH):
            print(f"[!] Warning: KasaneTeto.onnx not found at '{TETO_ONNX_PATH}'. Running without RVC.")
            return

        print(f"[*] Preloading Kasane Teto In-Memory Engine (Ava, pitch=+{RVC_PITCH}, method={RVC_METHOD})...")
        t_start = time.time()
        try:
            import onnxruntime as ort
            import faiss
            from scipy import signal
            from infer_rvc_python.lib.audio import load_audio
            from infer_rvc_python.root_pipe import VC, bh, ah
            from infer_rvc_python.main import load_hu_bert, Config
            from infer_rvc_python.lib.rmvpe import RMVPE

            self.load_audio = load_audio
            self.signal = signal
            self.bh = bh
            self.ah = ah

            config = Config(only_cpu=True)
            print("  [1/4] Loading HuBERT feature extractor...")
            self.hubert = load_hu_bert(config, None)

            if "rmvpe" in RVC_METHOD and os.path.isfile(RMVPE_PATH):
                print(f"  [2/4] Loading RMVPE pitch estimator from '{os.path.basename(RMVPE_PATH)}'...")
                self.rmvpe = RMVPE(RMVPE_PATH, is_half=False, device="cpu")
            else:
                self.rmvpe = None

            print(f"  [3/4] Optimizing ONNX Runtime ({CPU_THREADS} threads)...")
            opts = ort.SessionOptions()
            opts.intra_op_num_threads = CPU_THREADS
            opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            onnx_session = ort.InferenceSession(TETO_ONNX_PATH, opts)
            self.net_g = DirectOnnxNetG(onnx_session)

            print("  [4/4] Pre-caching FAISS retrieval index...")
            if os.path.isfile(TETO_INDEX_PATH):
                self.index = faiss.read_index(TETO_INDEX_PATH)
                self.big_npy = self.index.reconstruct_n(0, self.index.ntotal)
                has_index = True
            else:
                self.index = None
                self.big_npy = None
                has_index = False

            self.pipe = VC(40000, config)
            if self.rmvpe:
                self.pipe.model_rmvpe = self.rmvpe

            # Warmup pass
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as w_in:
                sf.write(w_in.name, np.zeros(16000, dtype=np.float32), 16000)
                try:
                    self._fast_convert(w_in.name, pitch_shift=RVC_PITCH)
                finally:
                    if os.path.exists(w_in.name):
                        os.remove(w_in.name)

            dur = time.time() - t_start
            index_str = "with FAISS index" if has_index else "without index"
            print(f"  ✓ Kasane Teto In-Memory Engine warmed up in {dur:.2f}s ({index_str})! 🥖✨")
        except Exception as e:
            print(f"[!] Error preloading Kasane Teto engine: {e}")
            import traceback
            traceback.print_exc()
            self.net_g = None

    def _fast_convert(self, in_wav_path: str, pitch_shift: int) -> str:
        """Direct zero-disk-reload in-memory RVC conversion."""
        audio = self.load_audio(in_wav_path, 16000)
        audio_max = np.abs(audio).max() / 0.95
        if audio_max > 1:
            audio /= audio_max

        audio = self.signal.filtfilt(self.bh, self.ah, audio)
        audio_pad = np.pad(audio, (self.pipe.t_pad, self.pipe.t_pad), mode="reflect")
        p_len = audio_pad.shape[0] // self.pipe.window

        pitch, pitchf = self.pipe.get_f0(
            in_wav_path, audio_pad, p_len, pitch_shift, RVC_METHOD, 3, None
        )
        pitch = pitch[:p_len]
        pitchf = pitchf[:p_len]
        pitch = torch.tensor(pitch, device="cpu").unsqueeze(0).long()
        pitchf = torch.tensor(pitchf, device="cpu").unsqueeze(0).float()

        audio_opt = self.pipe.vc(
            self.hubert,
            self.net_g,
            0,
            audio_pad,
            pitch,
            pitchf,
            [0, 0, 0],
            self.index,
            self.big_npy,
            INDEX_RATE if self.index else 0.0,
            "v2",
            0.33,
        )
        output_samples = audio_opt[self.pipe.t_pad_tgt : -self.pipe.t_pad_tgt]

        out_tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        sf.write(out_tmp.name, output_samples, 40000)
        out_tmp.close()
        return out_tmp.name

    def _synthesize_edge_tts(self, text: str, out_wav: str) -> bool:
        """Synthesize base audio using Microsoft Edge-TTS."""
        try:
            import edge_tts
            mp3_tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
            mp3_path = mp3_tmp.name
            mp3_tmp.close()

            async def _run():
                communicate = edge_tts.Communicate(text, EDGE_VOICE)
                await communicate.save(mp3_path)

            asyncio.run(_run())

            subprocess.run(
                ["ffmpeg", "-y", "-i", mp3_path, "-ar", "16000", "-ac", "1", out_wav],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            if os.path.exists(mp3_path):
                os.remove(mp3_path)
            return True
        except Exception as e:
            print(f"[!] Edge-TTS synthesis failed: {e}")
            return False

    def speak(self, text: str):
        """Process and speak text chunk-by-chunk with instant pipelined playback."""
        with self.lock:
            cleaned = zako_voice.clean_text_for_speech(text)
            chunks = zako_voice.split_into_chunks(cleaned)

            for chunk in chunks:
                if not chunk.strip():
                    continue

                in_path = None
                out_path = None
                try:
                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as in_tmp:
                        in_path = in_tmp.name

                    success = self._synthesize_edge_tts(chunk, in_path)
                    if not success:
                        continue

                    if self.net_g:
                        out_path = self._fast_convert(in_path, pitch_shift=RVC_PITCH)
                        subprocess.run(["pw-play", out_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        subprocess.run(["pw-play", in_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                except Exception as e:
                    print(f"[!] Playback error: {e}")
                finally:
                    if in_path and os.path.exists(in_path):
                        os.remove(in_path)
                    if out_path and os.path.exists(out_path):
                        os.remove(out_path)


voice_server = None


class VoiceHTTPHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path in ("/health", "/status"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            status_data = {
                "status": "ok",
                "character": "teto",
                "rvc_enabled": (voice_server.net_g is not None) if voice_server else False,
                "rvc_pitch": RVC_PITCH,
                "rvc_method": RVC_METHOD,
                "tts_backend": f"edge-tts ({EDGE_VOICE})",
                "engine": "fast-in-memory-onnx",
            }
            self.wfile.write(json.dumps(status_data).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/speak":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8", errors="replace")

            text = body
            try:
                data = json.loads(body)
                if isinstance(data, dict) and "text" in data:
                    text = data["text"]
            except Exception:
                pass

            if text.strip():
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
    print(f"[*] zako-voice-daemon listening on http://{HOST}:{PORT} (Kasane Teto 🥖 RMVPE, RVC={'ON' if ENABLE_RVC else 'OFF'}) ♡")
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
