"""받아쓰기 시험 창: 버튼을 누르고 있는 동안 PC 기본 마이크를 듣고, 떼면 한국어로 받아 적어 클립보드에 복사한다.
실행: pythonw stt_window.py  (결과는 stt_log.tsv에 녹음 길이·인식 시간과 함께 쌓인다)"""
import os
import sys
import threading
import time
import tkinter as tk
from pathlib import Path

_site = Path(sys.executable).parent.parent / "Lib" / "site-packages" / "nvidia"
for sub in ("cublas", "cudnn"):
    p = _site / sub / "bin"
    if p.is_dir():
        os.add_dll_directory(str(p))
        os.environ["PATH"] = str(p) + os.pathsep + os.environ["PATH"]
os.environ.setdefault("HF_HOME", r"C:\dev\cache\huggingface")

import numpy as np  # noqa: E402
import sounddevice as sd  # noqa: E402

RATE = 16000
LOG = Path(__file__).with_name("stt_log.tsv")


class App:
    def __init__(self, root):
        self.root = root
        self.model = None
        self.chunks = []
        self.stream = None
        self.busy = False
        root.title("PC 마이크 받아쓰기 시험")
        root.attributes("-topmost", True)
        dev = sd.query_devices(kind="input")
        tk.Label(root, text=f"마이크: {dev['name']}", anchor="w").pack(fill="x", padx=10, pady=(10, 0))
        self.status = tk.Label(root, text="모델 불러오는 중…", fg="#a60", anchor="w")
        self.status.pack(fill="x", padx=10)
        self.button = tk.Button(root, text="누르고 있는 동안 말하기", height=3, state="disabled",
                                font=("Malgun Gothic", 14, "bold"))
        self.button.pack(fill="x", padx=10, pady=10)
        self.button.bind("<ButtonPress-1>", self.start)
        self.button.bind("<ButtonRelease-1>", self.stop)
        self.text = tk.Text(root, height=5, wrap="word", font=("Malgun Gothic", 12))
        self.text.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        threading.Thread(target=self.load, daemon=True).start()

    def load(self):
        from faster_whisper import WhisperModel
        t = time.perf_counter()
        self.model = WhisperModel("large-v3-turbo", device="cuda", compute_type="float16")
        # 첫 인식의 GPU 준비 시간을 미리 치른다.
        list(self.model.transcribe(np.zeros(RATE, dtype=np.float32), language="ko")[0])
        self.ui(lambda: (self.status.config(text=f"준비됨 ({time.perf_counter() - t:.1f}초)", fg="#070"),
                         self.button.config(state="normal")))

    def ui(self, fn):
        self.root.after(0, fn)

    def start(self, _):
        if self.model is None or self.busy:
            return
        self.chunks = []
        self.stream = sd.InputStream(samplerate=RATE, channels=1, dtype="float32",
                                     callback=lambda d, *_: self.chunks.append(d.copy()))
        self.stream.start()
        self.status.config(text="듣는 중… (떼면 받아 적기)", fg="#c00")

    def stop(self, _):
        if self.stream is None:
            return
        self.stream.stop()
        self.stream.close()
        self.stream = None
        audio = np.concatenate(self.chunks)[:, 0] if self.chunks else np.zeros(0, np.float32)
        self.busy = True
        self.status.config(text="받아 적는 중…", fg="#a60")
        threading.Thread(target=self.transcribe, args=(audio,), daemon=True).start()

    def transcribe(self, audio):
        dur = len(audio) / RATE
        t = time.perf_counter()
        text = ""
        if dur >= 0.3:
            segs, _ = self.model.transcribe(audio, language="ko", beam_size=5, vad_filter=True)
            text = " ".join(s.text.strip() for s in segs).strip()
        took = time.perf_counter() - t
        with LOG.open("a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%H:%M:%S')}\t{dur:.2f}\t{took:.2f}\t{text}\n")

        def done():
            self.busy = False
            self.text.delete("1.0", "end")
            self.text.insert("1.0", text)
            if text:
                self.root.clipboard_clear()
                self.root.clipboard_append(text)
                self.status.config(text=f"복사됨 — scrcpy 화면에서 Ctrl+V  (말 {dur:.1f}초 · 인식 {took:.2f}초)", fg="#070")
            else:
                self.status.config(text="알아들은 말이 없습니다", fg="#a60")
        self.ui(done)


if __name__ == "__main__":
    root = tk.Tk()
    root.geometry("460x300")
    App(root)
    root.mainloop()
