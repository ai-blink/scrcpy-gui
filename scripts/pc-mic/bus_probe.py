"""Voicemeeter B1~B3와 Zen Q 입력을 동시에 녹음해 어느 장치에 목소리가 실리는지 잰다. 사용: bus_probe.py [초]"""
import sys
import time

import numpy as np
import sounddevice as sd

SECONDS = int(sys.argv[1]) if len(sys.argv) > 1 else 120
WANT = ["Voicemeeter Out B1", "Voicemeeter Out B2", "Voicemeeter Out B3", "Recording 1/2(Zen Q"]

wasapi = next(i for i, h in enumerate(sd.query_hostapis()) if "WASAPI" in h["name"])
devs = {}
for i, d in enumerate(sd.query_devices()):
    if d["hostapi"] == wasapi and d["max_input_channels"] > 0:
        for w in WANT:
            if w in d["name"] and w not in devs:
                devs[w] = (i, d)

levels = {w: [] for w in devs}
streams = []
for w, (i, d) in devs.items():
    def cb(data, frames, t, status, w=w):
        levels[w].append(float(np.sqrt((data.astype(np.float32) ** 2).mean())))
    s = sd.InputStream(device=i, channels=min(2, d["max_input_channels"]),
                       samplerate=d["default_samplerate"], blocksize=int(d["default_samplerate"] // 10), callback=cb)
    s.start()
    streams.append(s)

if "--wait" in sys.argv:
    # 어느 장치든 목소리(0.02 이상)가 잡힐 때까지 최대 300초 기다린 뒤 그 시점부터 SECONDS초를 잰다.
    end = time.time() + 300
    while time.time() < end and not any(lv and max(lv[-5:]) > 0.02 for lv in levels.values()):
        time.sleep(0.1)
    for w in levels:
        levels[w].clear()
    print("목소리 감지" if time.time() < end else "5분 동안 목소리 없음")
time.sleep(SECONDS)
for s in streams:
    s.stop()
    s.close()

for w, lv in levels.items():
    a = np.array(lv) if lv else np.zeros(1)
    loud = a[a > 0.01]
    print(f"{w:28s} 평균={a.mean():.4f} 상위5%={np.percentile(a, 95):.4f} 최대={a.max():.4f} 소리구간={len(loud) / 10:.1f}초")
