#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy<2.3", "librosa==0.10.2.post1", "soundfile"]
# ///
"""Give a tab's notes real timing by lining them up with a recording of the song.

The tab already says which notes, on which string and fret, in which order. A recording says
when notes start. This finds the note onsets in the audio, describes each by the pitches that
just appeared (constant-Q spectrum, new energy only), and aligns the tab's steps to them with
subsequence dynamic time warping: steps keep their order, the recording may have extra notes
(other instruments, ornaments) and may start before the tab does.

  tools/align-chart.py <chart.json> <audio file | YouTube URL | "ytsearch1:artist title"> [-o out.json]
  tools/align-chart.py --check <timed chart.json> <audio>     # strip the times, re-align, score

Make an untimed chart from a .tab with `pitchbench tabchart <file.tab> 0 --json chart.json`.
Downloaded audio is cached in ~/Library/Caches/MacTabs/audio (never in the repo).
"""
import json, subprocess, sys, hashlib, argparse
from pathlib import Path

import numpy as np
import librosa

SR, HOP, LOW, BINS = 22050, 256, 36, 72          # CQT from C2, six octaves, 11.6 ms hops
import os
SKIP, DOUBLE = float(os.environ.get("ALIGN_SKIP", 0.05)), float(os.environ.get("ALIGN_DOUBLE", 0.6))
CACHE = Path.home() / "Library/Caches/MacTabs/audio"


def fetch(src: str) -> Path:
    p = Path(src).expanduser()
    if p.exists():
        return p
    CACHE.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha1(src.encode()).hexdigest()[:12]
    out = CACHE / f"{key}.m4a"
    if not out.exists():
        subprocess.run(["yt-dlp", "-q", "--no-playlist", "-f", "bestaudio[ext=m4a]/bestaudio",
                        "-o", str(out), src], check=True)
        title = subprocess.run(["yt-dlp", "--no-playlist", "--get-title", src], capture_output=True, text=True).stdout.strip()
        (CACHE / f"{key}.txt").write_text(f"{src}\n{title}\n")
    return out


def steps_of(notes, tol=0.035):
    steps = []
    for n in sorted(notes, key=lambda n: n.get("ts", n["t"])):
        t = n.get("ts", n["t"])
        if steps and t - steps[-1]["t"] < tol:
            steps[-1]["notes"].append(n)
        else:
            steps.append({"t": t, "notes": [n]})
    return steps


def template(midis):
    v = np.zeros(BINS)
    for m in set(midis):
        for h, w in ((1, 1.0), (2, 0.7), (3, 0.5), (4, 0.35)):
            b = int(round(m + 12 * np.log2(h))) - LOW
            if 0 <= b < BINS:
                v[b] += w
    return v / (np.linalg.norm(v) + 1e-9)


def onset_features(y):
    C = np.abs(librosa.cqt(y, sr=SR, hop_length=HOP, fmin=librosa.midi_to_hz(LOW), n_bins=BINS, bins_per_octave=12))
    L = np.log1p(30 * C / (C.max() + 1e-9))
    env = librosa.onset.onset_strength(y=y, sr=SR, hop_length=HOP)
    on = librosa.onset.onset_detect(onset_envelope=env, sr=SR, hop_length=HOP, delta=0.03, wait=3, backtrack=False)
    feats = []
    for f in on:
        after = L[:, f:f + 6].max(axis=1)
        before = L[:, max(0, f - 5):max(1, f - 1)].mean(axis=1)
        v = np.maximum(0, after - before) + 0.15 * after      # mostly what is new, a little of what sounds
        feats.append(v / (np.linalg.norm(v) + 1e-9))
    return librosa.frames_to_time(on, sr=SR, hop_length=HOP), np.array(feats)


def align(steps, times, feats):
    T = np.array([template([n["midi"] for n in s["notes"]]) for s in steps])
    cost = 1 - T @ feats.T                                    # steps x onsets
    # Diagonal = one step per onset; (0,1) = skip an onset (extra note in the audio); (1,0) = two
    # steps on one onset (an onset the detector missed). Skips are cheap, doubling is not.
    D, wp = librosa.sequence.dtw(C=cost, subseq=True, step_sizes_sigma=np.array([[1, 1], [0, 1], [1, 0]]),
                                 weights_add=np.array([0, SKIP, DOUBLE]), weights_mul=np.array([1, 0.2, 1]))
    wp = wp[::-1]
    best = {}
    for i, j in wp:                                           # each step: its cheapest matched onset
        if i not in best or cost[i, j] < cost[i, best[i]]:
            best[i] = j
    out, sims, last = [], [], -1.0
    for i in range(len(steps)):
        j = best.get(i)
        t = float(times[j]) if j is not None else last + 0.2
        if t <= last:
            t = last + 0.05
        out.append(t)
        sims.append(1 - cost[i, j] if j is not None else 0)
        last = t
    return out, float(np.median(sims)), float(np.mean(np.array(sims) > 0.5))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("chart")
    ap.add_argument("audio")
    ap.add_argument("-o", "--out")
    ap.add_argument("--check", action="store_true", help="score against the chart's own times")
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    chart = json.load(open(a.chart))
    steps = steps_of(chart["notes"])
    truth = [s["t"] for s in steps]
    audio = fetch(a.audio)
    y, _ = librosa.load(str(audio), sr=SR, mono=True)
    times, feats = onset_features(y)
    got, med, good = align(steps, times, feats)
    print(f"{len(steps)} steps, {len(times)} onsets in {len(y) / SR:.0f} s of audio; "
          f"median match {med:.2f}, {100 * good:.0f}% of steps match well")
    if a.check:
        err = np.abs(np.array(got) - np.array(truth))
        print(f"vs the chart's own times: median error {1000 * np.median(err):.0f} ms, "
              f"{100 * np.mean(err < 0.05):.0f}% within 50 ms, {100 * np.mean(err < 0.1):.0f}% within 100 ms, "
              f"{100 * np.mean(err < 0.3):.0f}% within 300 ms; first 10: {100 * np.mean(err[:10] < 0.15):.0f}% within 150 ms")
        if "-v" in sys.argv:
            for i, (s, g, t) in enumerate(zip(steps, got, truth)):
                print(f"{i:3d} {t:6.2f} -> {g:6.2f}  {'+'.join(str(n['midi']) for n in s['notes'])}  {'  <-- off' if abs(g - t) > 0.1 else ''}")
    if a.out:
        notes = []
        for s, t in zip(steps, got):
            for n in s["notes"]:
                notes.append({"t": round(t, 3), "string": n["string"], "fret": n["fret"], "midi": n["midi"]})
        src = (CACHE / f"{Path(audio).stem}.txt")
        res = {k: v for k, v in chart.items() if k not in ("notes", "timing")}
        res.update({"timing": f"aligned to {src.read_text().splitlines()[0] if src.exists() else a.audio}",
                    "match": round(med, 2), "notes": notes})
        json.dump(res, open(a.out, "w"), ensure_ascii=False, indent=0)
        print("wrote", a.out)


if __name__ == "__main__":
    main()
