"""faster-whisper 한국어 받아쓰기 속도·결과 측정. 사용: stt_bench.py <wav> [...]"""
import os
import sys
import time
from pathlib import Path

# pip로 받은 cuBLAS·cuDNN DLL을 ctranslate2가 찾도록 경로를 더한다.
_site = Path(sys.executable).parent.parent / "Lib" / "site-packages" / "nvidia"
for sub in ("cublas", "cudnn"):
    p = _site / sub / "bin"
    if p.is_dir():
        os.add_dll_directory(str(p))
        os.environ["PATH"] = str(p) + os.pathsep + os.environ["PATH"]

from faster_whisper import WhisperModel  # noqa: E402

MODEL = os.environ.get("STT_MODEL", "large-v3-turbo")


def main(paths):
    t0 = time.perf_counter()
    model = WhisperModel(MODEL, device="cuda", compute_type="float16")
    print(f"model={MODEL} load={time.perf_counter() - t0:.2f}s")
    for path in paths:
        for run in range(2):  # 두 번째가 데움 끝난 실제 속도
            t = time.perf_counter()
            segs, info = model.transcribe(path, language="ko", beam_size=5, vad_filter=True)
            text = " ".join(s.text.strip() for s in segs)
            print(f"{Path(path).name} run{run} dur={info.duration:.2f}s took={time.perf_counter() - t:.2f}s :: {text}")


if __name__ == "__main__":
    main(sys.argv[1:])

