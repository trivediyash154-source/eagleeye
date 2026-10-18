"""Build a YOLO-format dataset of SYNTHETIC cabinet renders for detector training.

Usage:
    python scripts/build_synthetic_dataset.py --out ../artifacts/synthetic_dataset --train 520 --val 90

The images are procedurally generated (see app/demo/synth_cabinet.py). A detector trained
on them demonstrates the custom-weights path end to end; it is NOT validated on real
cabinet photographs and must not be presented as such.
"""
from __future__ import annotations

import argparse
import random
import sys
from multiprocessing import Pool
from pathlib import Path

import cv2

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.demo.synth_cabinet import CLASSES, photo_from_plate, random_layout, render_plate  # noqa: E402


def make_sample(args: tuple[int, str, Path]) -> int:
    seed, split, out = args
    rng = random.Random(seed)
    lay = random_layout(rng)
    if rng.random() < 0.5:
        plate, boxes = render_plate(lay, 2.0, rng)
        img, bx, _ = photo_from_plate(plate, boxes, rng, out_size=(1280, 960), jitter=rng.uniform(0.0, 0.07), margin=rng.uniform(0.02, 0.1))
    else:
        plate, boxes = render_plate(lay, 3.0, rng)
        big, bxb, _ = photo_from_plate(plate, boxes, rng, out_size=(2400, 1800), jitter=rng.uniform(0.0, 0.06), margin=rng.uniform(0.02, 0.08))
        cw = rng.randint(850, 1500)
        ch = int(cw * rng.uniform(0.62, 0.85))
        x0 = rng.randint(0, 2400 - cw)
        y0 = rng.randint(0, 1800 - ch)
        crop = big[y0:y0 + ch, x0:x0 + cw]
        s = min(1.0, 1024 / max(cw, ch))
        img = cv2.resize(crop, (int(cw * s), int(ch * s)), interpolation=cv2.INTER_AREA) if s < 1 else crop
        bx = []
        for (c, a, b, cc, d, t) in bxb:
            ia, ib = max(a, x0), max(b, y0)
            ic, id_ = min(cc, x0 + cw), min(d, y0 + ch)
            if ic <= ia or id_ <= ib:
                continue
            vis = (ic - ia) * (id_ - ib) / max(1e-6, (cc - a) * (d - b))
            if vis < 0.45:
                continue
            bx.append((c, (ia - x0) * s, (ib - y0) * s, (ic - x0) * s, (id_ - y0) * s, t))
    h, w = img.shape[:2]
    name = f"syn_{seed:06d}"
    (out / "images" / split).mkdir(parents=True, exist_ok=True)
    (out / "labels" / split).mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(out / "images" / split / f"{name}.jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 90])
    lines = []
    for (c, a, b, cc, d, _) in bx:
        lines.append(f"{c} {(a + cc) / 2 / w:.6f} {(b + d) / 2 / h:.6f} {(cc - a) / w:.6f} {(d - b) / h:.6f}")
    (out / "labels" / split / f"{name}.txt").write_text("\n".join(lines))
    return len(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[2] / "artifacts" / "synthetic_dataset")
    ap.add_argument("--train", type=int, default=520)
    ap.add_argument("--val", type=int, default=90)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--seed", type=int, default=1000)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    jobs = [(a.seed + i, "train", a.out) for i in range(a.train)] + [(a.seed + 100000 + i, "val", a.out) for i in range(a.val)]
    with Pool(a.workers) as pool:
        counts = pool.map(make_sample, jobs, chunksize=4)
    (a.out / "data.yaml").write_text(
        f"path: {a.out.resolve()}\ntrain: images/train\nval: images/val\nnames:\n" + "".join(f"  {i}: {n}\n" for i, n in enumerate(CLASSES))
    )
    print(f"wrote {len(jobs)} images, {sum(counts)} boxes -> {a.out}")


if __name__ == "__main__":
    main()
