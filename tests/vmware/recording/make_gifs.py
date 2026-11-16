"""게스트에서 받은 장면별 PNG 프레임을 GIF로 만든다.

사용: python make_gifs.py <풀어 둔 게스트 결과 폴더> <출력 폴더> [--max-side 960] [--max-seconds 10]
- 장면 폴더마다 crop.json(화면 좌표)으로 잘라 내고, 파일 이름의 시각(ms)으로 프레임 길이를 정한다.
- 모든 프레임에서 뽑은 공통 팔레트를 써서 장면 내 색 깜박임을 막고, 같은 프레임은 합친다.
"""
import argparse
import json
import pathlib

from PIL import Image, ImageChops


def build(scene: pathlib.Path, out: pathlib.Path, max_side: int, max_ms: int) -> dict:
    crop = json.loads(scene.joinpath("crop.json").read_text(encoding="utf-8-sig"))
    files = sorted(scene.glob("*.png"))
    if not files:
        return {"scene": scene.name, "error": "no frames"}
    stamps = [int(f.stem.split("_")[1]) for f in files]
    first = Image.open(files[0])
    W, H = first.size
    box = (max(0, crop["x"]), max(0, crop["y"]), min(W, crop["x"] + crop["width"]), min(H, crop["y"] + crop["height"]))
    bw, bh = box[2] - box[0], box[3] - box[1]
    scale = min(1.0, max_side / max(bw, bh))
    size = (round(bw * scale), round(bh * scale))
    # keep 영역 밖은 단색으로 칠한다(뒤 창이 비치지 않게)
    mask = None
    if crop.get("keep"):
        mask = Image.new("L", (W, H), 0)
        for k in crop["keep"]:
            mask.paste(255, (k["x"], k["y"], k["x"] + k["width"], k["y"] + k["height"]))
        backdrop = Image.new("RGB", (W, H), (24, 26, 30))
    frames, durations = [], []
    for i, f in enumerate(files):
        if stamps[i] - stamps[0] > max_ms:
            break
        im = Image.open(f).convert("RGB")
        if mask is not None:
            im = Image.composite(im, backdrop, mask)
        im = im.crop(box)
        if scale < 1:
            im = im.resize(size, Image.LANCZOS)
        nxt = stamps[i + 1] if i + 1 < len(stamps) else stamps[i] + 800
        dur = max(20, nxt - stamps[i])
        if frames and ImageChops.difference(frames[-1], im).getbbox() is None:
            durations[-1] += dur
            continue
        frames.append(im)
        durations.append(dur)
    # 공통 팔레트: 프레임 표본을 세로로 붙여 한 번에 양자화
    sample = frames[:: max(1, len(frames) // 12)]
    sheet = Image.new("RGB", (size[0], size[1] * len(sample)))
    for k, im in enumerate(sample):
        sheet.paste(im, (0, size[1] * k))
    palette = sheet.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    pframes = [im.quantize(palette=palette, dither=Image.Dither.NONE) for im in frames]
    target = out / f"{scene.name}.gif"
    pframes[0].save(target, save_all=True, append_images=pframes[1:], duration=durations, loop=0, optimize=False, disposal=1)
    return {"scene": scene.name, "gif": str(target), "frames": len(pframes), "seconds": round(sum(durations) / 1000, 2),
            "size": list(size), "bytes": target.stat().st_size}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--max-side", type=int, default=960)
    ap.add_argument("--max-seconds", type=float, default=10)
    a = ap.parse_args()
    run, out = pathlib.Path(a.run_dir), pathlib.Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    results = [build(d, out, a.max_side, int(a.max_seconds * 1000)) for d in sorted(run.iterdir()) if d.joinpath("crop.json").exists()]
    out.joinpath("gifs.json").write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
