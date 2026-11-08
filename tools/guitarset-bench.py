#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy<2.3", "scipy", "soundfile"]
# ///
"""GuitarSet as a laptop-mic bench for the pitch judge.

GuitarSet (Xi et al., ISMIR 2018; CC BY 4.0; zenodo.org/records/3371780) is 360 half-minute
takes of acoustic guitar, six players, five styles, each played as comping and as a solo, with
every note's string, fret and onset taken from a hexaphonic pickup. Its mic track is a studio
condenser, so `prepare` makes it sound like MacTabs hears a guitar: a laptop mic's bass roll-off
and top cut, a small room, the levels in Daniel's play logs (playing -36..-26 dBFS, quiet room
about -68 dBFS) and his 100 Hz mains hum with harmonics plus hiss. Each take gets its own seeded
draw of those, so the bench is the same every run.

  tools/guitarset-bench.py prepare [--variant laptop|clean] [--limit N]
  tools/guitarset-bench.py run [key=value …]            pitchbench suite on tune + hold
  tools/guitarset-bench.py tune [--trials N]             coordinate search over NoteJudge.Config

Data lives in ~/Library/Caches/MacTabs/guitarset (never in the repo):
  annotation/*.jams, mic/*_mic.wav       the download (unzipped)
  charts/<take>.chart.json               notes as MacTabs charts (string 1 = high e)
  <variant>/<take>.wav                   48 kHz mono, degraded
  <variant>-{tune,hold,all}.tsv          pitchbench manifests; players 00-03 tune, 04-05 hold out
"""
import argparse, hashlib, json, subprocess, sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

ROOT = Path.home() / "Library/Caches/MacTabs/guitarset"
REPO = Path(__file__).resolve().parent.parent
BENCH = REPO / ".build/release/pitchbench"
OPEN = [40, 45, 50, 55, 59, 64]          # GuitarSet data_source 0 = low E … 5 = high e
FS = 48000
STRUM = 0.06                             # notes starting within this of a step's first note join it


def chart(jams_path: Path) -> dict:
    j = json.loads(jams_path.read_text())
    notes = []
    for a in j["annotations"]:
        if a["namespace"] != "note_midi":
            continue
        s = int(a["annotation_metadata"]["data_source"])
        for o in a["data"]:
            if o["duration"] < 0.04:     # clicks and slides the pickup caught, not playable notes
                continue
            midi = int(round(o["value"]))
            notes.append({"t": o["time"], "dur": o["duration"], "string": 6 - s,
                          "fret": max(0, midi - OPEN[s]), "midi": midi})
    notes.sort(key=lambda n: n["t"])
    # Strums: every note of one stroke gets the stroke's first onset, so the chart sees one step.
    start = None
    for n in notes:
        if start is None or n["t"] - start >= STRUM:
            start = n["t"]
        n["spread"] = round(n["t"] - start, 4)
        n["t"] = start
    return {"title": jams_path.stem, "artist": "GuitarSet", "timing": "hex pickup onsets", "notes": notes}


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(int(hashlib.sha1(name.encode()).hexdigest()[:8], 16))


def rms_db(x, n=4096):
    m = len(x) // n * n
    r = np.sqrt((x[:m].reshape(-1, n) ** 2).mean(1) + 1e-20)
    return 20 * np.log10(r)


def laptop(x: np.ndarray, name: str) -> tuple[np.ndarray, dict]:
    r = rng_for(name)
    p = {"hp_hz": r.uniform(100, 150), "lp_hz": r.uniform(8000, 12000), "rt60": r.uniform(0.25, 0.5),
         "wet_db": r.uniform(-14, -8), "play_db": r.uniform(-36, -26), "hum_db": r.uniform(-76, -64),
         "hiss_db": r.uniform(-80, -68), "mains": r.choice([50.0, 50.0, 60.0]) * r.uniform(0.998, 1.002)}
    # Laptop mic: steep roll-off under ~120 Hz (the low E fundamental is nearly gone), soft top.
    y = signal.sosfilt(signal.butter(4, p["hp_hz"], "highpass", fs=FS, output="sos"), x)
    y = signal.sosfilt(signal.butter(2, p["lp_hz"], "lowpass", fs=FS, output="sos"), y)
    # Small room: exponentially decaying noise tail behind the direct sound.
    n = int(p["rt60"] * FS)
    ir = r.standard_normal(n) * np.exp(-6.9 * np.arange(n) / n)
    ir = signal.sosfilt(signal.butter(1, 4000, "lowpass", fs=FS, output="sos"), ir)
    ir *= 10 ** (p["wet_db"] / 20) / np.sqrt((ir ** 2).sum())
    ir[0] += 1
    y = signal.fftconvolve(y, ir)[: len(y)]
    # Playing level: the loud end (95th percentile of 85 ms windows) at play_db.
    y *= 10 ** ((p["play_db"] - np.percentile(rms_db(y), 95)) / 20)
    # Room: mains hum (100 or 120 Hz with harmonics, as in Daniel's room) and hiss through the same mic.
    t = np.arange(len(y)) / FS
    f = 2 * p["mains"]
    hum = sum(w * np.sin(2 * np.pi * f * k * t + r.uniform(0, 6.28)) for k, w in [(1, 1), (2, .7), (3, .4), (4, .5), (6, .2)])
    hum *= 10 ** (p["hum_db"] / 20) / np.sqrt((hum ** 2).mean())
    hiss = signal.lfilter([1], [1, -0.9], r.standard_normal(len(y)))      # tilted toward the bass, like a fan
    hiss = signal.sosfilt(signal.butter(4, p["hp_hz"] * 0.6, "highpass", fs=FS, output="sos"), hiss)
    hiss *= 10 ** (p["hiss_db"] / 20) / np.sqrt((hiss ** 2).mean())
    return y + hum + hiss, {k: round(float(v), 3) for k, v in p.items()}


def prepare(a):
    takes = sorted((ROOT / "annotation").glob("*.jams"))[: a.limit or None]
    (ROOT / "charts").mkdir(exist_ok=True)
    out = ROOT / a.variant
    out.mkdir(exist_ok=True)
    meta, rows = {}, []
    for k, jp in enumerate(takes):
        name = jp.stem
        cp = ROOT / "charts" / f"{name}.chart.json"
        cp.write_text(json.dumps(chart(jp)))
        wp = out / f"{name}.wav"
        if not wp.exists():
            x, fs = sf.read(ROOT / "mic" / f"{name}_mic.wav", dtype="float64")
            if x.ndim > 1:
                x = x.mean(1)
            x = signal.resample_poly(x, FS, fs)
            if a.variant == "laptop":
                y, meta[name] = laptop(x, name)
            else:
                y = x * 10 ** ((-30 - np.percentile(rms_db(x), 95)) / 20)
            sf.write(wp, np.clip(y, -1, 1).astype(np.float32), FS, subtype="PCM_16")
        kind = "comp" if name.endswith("_comp") else "solo"
        rows.append((name[:2], f"{wp}\t{cp}\t{kind}"))
        print(f"\r{k + 1}/{len(takes)} {name}", end="", file=sys.stderr)
    print(file=sys.stderr)
    if meta:
        (out / "params.json").write_text(json.dumps(meta, indent=1))
    for split, keep in [("tune", {"00", "01", "02", "03"}), ("hold", {"04", "05"}), ("all", None)]:
        (ROOT / f"{a.variant}-{split}.tsv").write_text("".join(r + "\n" for p, r in rows if keep is None or p in keep))


def suite(manifest: Path, kv: list[str]) -> dict:
    j = ROOT / f".suite-{manifest.stem}.json"
    subprocess.run([str(BENCH), "suite", str(manifest), *kv, "--json", str(j)], check=True, capture_output=True)
    return json.loads(j.read_text())


def run(a):
    for split in ["tune", "hold"]:
        print(f"== {a.variant}-{split}")
        subprocess.run([str(BENCH), "suite", str(ROOT / f"{a.variant}-{split}.tsv"), *a.kv], check=True)


# The tuning objective: hits, mean over single notes, dyads and chords (equal weight, so chords
# count), minus false accepts. A step passing before it was played moves the highway on its own,
# the worst error, so it costs double. A wrong fret (±1 semitone) or a lower note's overtone (+12)
# accepted costs in full; the chord an octave down (−12) only a quarter: a laptop mic loses the
# fundamentals that tell those apart, and a player rarely makes that mistake.
W = {"-1": 1, "+1": 1, "-12": 0.25, "+12": 1}


def score(r: dict) -> float:
    kinds = ["single", "dyad", "chord"]
    hit = np.mean([r[k]["hit"] for k in kinds])
    fa = np.mean([sum(w * np.nan_to_num(r[k][f"decoy{s}"]) for s, w in W.items()) / 2 for k in kinds])
    prem = np.mean([r[k]["premature"] for k in kinds])
    return float(hit - fa - 2 * prem)


# Search space: every Config threshold, with the steps to try around the current value.
SPACE = {
    "rise": [3, 4, 5, 6, 7, 8, 10], "risesec": [0.06, 0.08, 0.12, 0.16, 0.2],
    "contrast": [2, 3, 4, 5, 6, 7], "gate": [12, 16, 19, 22, 25, 28], "share": [6, 8, 10, 12, 15, 20],
    "minrms": [-70, -65, -60, -55], "noiseover": [1, 1.5, 2, 3], "odd": [-20, -17, -14, -11, -8],
    "lowerrise": [1, 2, 3, 5], "unique": [4, 6, 8, 10, 12], "repluck": [1, 2, 3, 4],
    "diffcontrast": [6, 8, 11, 14], "buried": [3, 6, 9, 12], "difflag": [0.05, 0.08, 0.12],
    "chordcontrast": [-2, -1, 0, 1, 2, 3], "chordlow": [8, 11, 14, 18, 22], "low": [5, 8, 11, 14],
    "lowest": [0, 38, 40], "repluckrise": [1, 2, 3, 5], "noiserise": [1, 3, 6],
}


def tune(a):
    cur = dict(kv.split("=") for kv in a.kv)
    tm = ROOT / f"{a.variant}-tune.tsv"
    best = score(suite(tm, [f"{k}={v}" for k, v in cur.items()]))
    print(f"start {best:.4f} {cur}", flush=True)
    for rnd in range(a.rounds):
        improved = False
        for key, vals in SPACE.items():
            for v in vals:
                trial = {**cur, key: str(v)}
                if trial == cur:
                    continue
                s = score(suite(tm, [f"{k}={x}" for k, x in trial.items()]))
                if s > best + 0.002:
                    best, cur, improved = s, trial, True
                    print(f"  round {rnd} {key}={v}: {best:.4f}", flush=True)
        if not improved:
            break
    print("best", best, " ".join(f"{k}={v}" for k, v in cur.items()))
    for split in ["tune", "hold"]:
        r = suite(ROOT / f"{a.variant}-{split}.tsv", [f"{k}={v}" for k, v in cur.items()])
        print(split, f"score {score(r):.4f}", {k: {m: round(r[k][m], 3) for m in ["hit", "premature", "decoy-1", "decoy+1", "decoy-12", "decoy+12"]} for k in ["single", "dyad", "chord"]})


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["prepare", "run", "tune"])
    ap.add_argument("kv", nargs="*")
    ap.add_argument("--variant", default="laptop")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--rounds", type=int, default=3)
    a = ap.parse_args()
    {"prepare": prepare, "run": run, "tune": tune}[a.cmd](a)
