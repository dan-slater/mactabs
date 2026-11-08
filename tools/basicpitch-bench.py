#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10,<3.12"
# dependencies = ["basic-pitch", "scipy<1.13", "setuptools<70", "soundfile"]
# ///
"""Basic Pitch (Spotify, Apache-2.0) as a streaming detector, for comparison with NoteJudge.

Basic Pitch reads 2 s windows at 22.05 kHz and gives onset and note posteriors per semitone every
256 samples (11.6 ms). Offline it sees the future; in the game it cannot. So this slides the
window along each take, ending it every `--stride` frames as a live input would, runs the CoreML
model, and keeps only the newest `--keep` frames of each window. `pitchbench suite --post <dir>`
then plays the same wait-mode game on those posteriors that it plays with NoteJudge.

  tools/basicpitch-bench.py <manifest.tsv> <out dir> [--stride 2] [--keep 16] [--jobs 3]

Output per take: <out>/<take>.bp (format in pitchbench's PosteriorEar).
"""
import argparse, os, sys, time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

SR, HOP, WIN = 22050, 256, 22050 * 2 - 256


def model():
    import coremltools as ct
    from basic_pitch import ICASSP_2022_MODEL_PATH
    p = Path(ICASSP_2022_MODEL_PATH)
    return ct.models.MLModel(str(p if p.suffix == ".mlpackage" else p.parent / "nmp.mlpackage"))


def take(args):
    wav, out, stride, keep = args
    if out.exists():
        return out.name, 0.0
    m = model()
    name = m.get_spec().description.input[0].name
    x, fs = sf.read(wav, dtype="float32")
    if x.ndim > 1:
        x = x.mean(1)
    x = signal.resample_poly(x, SR, fs).astype(np.float32)
    x = np.concatenate([np.zeros(WIN, np.float32), x])          # silence before the take starts
    ends = np.arange(WIN + HOP * stride, len(x), HOP * stride)
    on = np.zeros((len(ends), keep, 88), np.float16)
    nt = np.zeros_like(on)
    t0 = time.time()
    for i, e in enumerate(ends):
        r = m.predict({name: x[e - WIN:e].reshape(1, WIN, 1)})
        on[i] = r["Identity_2"][0, -keep:]
        nt[i] = r["Identity_1"][0, -keep:]
    head = np.array([len(ends), keep, 88, HOP * stride], np.int32)
    with open(out, "wb") as f:
        f.write(head.tobytes()); f.write((ends - WIN).astype(np.int32).tobytes()); f.write(on.tobytes()); f.write(nt.tobytes())
    return out.name, time.time() - t0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest"); ap.add_argument("out")
    ap.add_argument("--stride", type=int, default=2); ap.add_argument("--keep", type=int, default=16)
    ap.add_argument("--jobs", type=int, default=3)
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    wavs = [Path(l.split("\t")[0]) for l in Path(a.manifest).read_text().splitlines() if l and not l.startswith("#")]
    jobs = [(w, out / (w.stem + ".bp"), a.stride, a.keep) for w in wavs]
    with ProcessPoolExecutor(a.jobs) as ex:
        for k, (n, dt) in enumerate(ex.map(take, jobs)):
            print(f"\r{k + 1}/{len(jobs)} {n} {dt:.1f}s", end="", file=sys.stderr)
    print(file=sys.stderr)
