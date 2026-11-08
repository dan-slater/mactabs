# MacTabs — an autoscrolling guitar-tab viewer for the Mac

[![build](https://github.com/dan-slater/mactabs/actions/workflows/build.yml/badge.svg)](https://github.com/dan-slater/mactabs/actions/workflows/build.yml) · [Download](../../releases/latest) · MIT

Put your hands on the guitar, hit space, and the tab scrolls at a speed you set once per song.
Say "faster" or "slower" to adjust it without letting go of the neck. Chord diagrams for every
chord in the song sit beside the text.

![MacTabs in light mode](docs/screenshot-light.png)

Plain text in, plain text out: a song is a `.tab` file in `~/Tabs` with a few lines of
frontmatter above ordinary ASCII tab. No account, no database, no sync. Native SwiftUI + AppKit,
one dependency ([Fretboard](https://github.com/itsmeichigo/Fretboard), MIT, for the chord
diagrams and the chords-db it bundles). Follows the system Light/Dark setting.

![MacTabs in dark mode](docs/screenshot-dark.png)

## Install

**Download:** grab `MacTabs.app.zip` from the [latest release](../../releases/latest), unzip, and
drop `MacTabs.app` into `~/Applications`. The app is signed ad hoc, not notarised, so the first
launch is a right-click → Open (or `xattr -d com.apple.quarantine MacTabs.app`). macOS 14 or later.

**Build from source** (Xcode command-line tools are enough):

```bash
git clone https://github.com/dan-slater/mactabs && cd mactabs
make install        # swift build → build/MacTabs.app → ~/Applications
```

`make run` builds and launches; `make` alone just builds. The app reads `~/Tabs`; set
`TABS_DIR=/path` to point it elsewhere. The folder is watched, so a file dropped in appears in
the sidebar at once.

## The icon row

Above the song's name: versions (a menu, with the count), the source page, chord diagrams,
voice, full screen, and export (save as PDF, share the file, copy the text, show in Finder).

## Keys

| Key | Does |
| --- | --- |
| space | start / stop scrolling |
| ↑ ↓ | faster / slower (×1.15 per press, saved to the file after 1.5 s) |
| [ ] | previous / next `[Section]` |
| t / 0 | back to the top |
| + − | bigger / smaller text (upper bound; lines never wrap) |
| c | show / hide the chord panel |
| n | next version of this song (when there is more than one) |
| v | voice commands on / off |
| g | play mode for this song's chart (see below) |
| ⌘, | design options (also the sliders icon in the toolbar) |

## Voice

`v` starts on-device speech recognition (Apple `Speech`; the first time macOS asks for the
microphone and speech permissions). Words that act: **faster**, **slower**, **stop** (pause,
wait), **go** (start, play, scroll), **top** (restart). Nothing leaves the Mac. Recognition
sessions are capped at about a minute, so the app rolls them over every 50 s while listening.

## Play mode (wait mode, early demo)

Open a song and press `g` (or click the game controller in the icon row). Any tab with ASCII
tab lines (`e|---0---`) plays straight from those lines, with the file's `tuning:` and `capo:`
applied; a chord sheet has nothing to play. A hand-made or generated chart next to your tabs,
`Artist - Title.chart.json`, takes priority and is also listed in the **Play** menu. Six lanes scroll the notes
towards a hit line, fret numbers on the notes; the highway stops at each note until you play
that pitch into the Mac's microphone. It judges **pitch, not string**: any string and fret that
sounds the note counts. Voice commands switch off while you play (they share the mic).

Keys in play mode: `space` pause, `↑ ↓` speed, `r` restart, `esc` leave. The Design panel (⌘,)
switches between falling lanes and a tab strip.

A chart is JSON: `{"title": …, "artist": …, "notes": [{"t": 3.36, "string": 1, "fret": 0}]}`,
with string 1 the high e. `midi` is filled in from standard tuning when missing.

How notes are heard (`Sources/NoteJudge`): no open-ended pitch tracking; the game only asks
"was the *expected* note just struck?". Two listeners answer together (`Hearing`):

- **NoteJudge** (DSP): every 11 ms it measures the energy at each candidate note's harmonics
  and calls the note struck when that energy jumps, stands clear of the semitones either side,
  and is not just an upper partial of a lower note.
- **Basic Pitch** (Spotify's small note-transcription model, Apache-2.0, bundled as CoreML,
  272 KB): a 2 s window ending now, run every 23 ms on the GPU / Neural Engine. Its *note*
  posterior says which pitches sound and rarely mistakes a fret or an overtone.

A note counts when Basic Pitch hears it sounding and a new pluck shows (Basic Pitch's onset
posterior, or NoteJudge's onset test, which catches re-strums of a ringing chord); a single
note must also not be just the overtone of a lower note that was plucked.
`defaults write dev.danielslater.tabs play.ear judge` listens with NoteJudge alone.

Measured on a laptop-mic simulation of GuitarSet (360 takes of acoustic guitar with
per-string annotations, played through a bass roll-off, a small room and mains hum; see
`tools/guitarset-bench.py`), on players the tuning never saw:

| first pluck heard | single notes | two-note steps | chords | wrong fret accepted | overtone accepted |
| --- | --- | --- | --- | --- | --- |
| NoteJudge + Basic Pitch (default) | 94% | 65% | 74% | 0–2.5% | 0.4–4% |
| NoteJudge alone | 87% | 33% | 39% | 0.2–4% | 0.5–6% |

Median latency is 47 ms for a single note and 77 ms for a chord (analysis only; add the audio
buffer). Solos are heard 98% of the time; fast funk comping is the hardest. On a real recording
of Für Elise it hears every note. Each play session
writes a log to `~/Library/Logs/MacTabs/`.

### The bench

```bash
tools/guitarset-bench.py prepare        # GuitarSet (CC BY 4.0) into ~/Library/Caches/MacTabs/guitarset
tools/basicpitch-bench.py ~/Library/Caches/MacTabs/guitarset/laptop-all.tsv ~/Library/Caches/MacTabs/guitarset/bp-laptop
.build/release/pitchbench suite ~/Library/Caches/MacTabs/guitarset/laptop-hold.tsv --live   # the app's Hearing
.build/release/pitchbench suite ~/Library/Caches/MacTabs/guitarset/laptop-hold.tsv --why    # NoteJudge, why notes are missed
tools/guitarset-bench.py tune [--hybrid]                                                    # coordinate search
```

`suite` replays each take through the game's own wait-mode judging and also asks for decoy
steps (the same notes ±1 semitone and ±1 octave) to count false accepts. Players 00–03 tune,
04–05 are held out. `pitchbench eval <audio> <chart>` scores a single recording.

## The file format

`~/Tabs/<Artist> - <Title>.tab`, UTF-8, an optional frontmatter block then plain monospace text:

```
---
title: House of the Rising Sun
artist: Traditional
tuning: EADGBE
capo: 0
bpm: 80
scroll: 0.6        # lines per second; the app writes this back when you change speed
source: where it came from
---
[Intro]
    Am           C            D            F
e|-----0-----|-----0-----|-----2-----|-----1-----|
B|---1---1---|---1---1---|---3---3---|---1---1---|

[Verse 1]
Am       C        D         F
There is a house in New Orleans
```

- `[Section]` on its own line is a section header; `[` and `]` jump between them.
- A line made only of chord names (`C  G/B  Am7`) is a chord line and feeds the chord panel.
  Everything else is shown as is. Lines never wrap: the font shrinks to fit the longest line,
  down to 10 pt, and anything wider scrolls sideways.
- When `source` is a web link, the song's sidebar row gets a small ↗ icon (and a right-click
  item) that opens that page in your browser, e.g. the Ultimate Guitar page it was imported from.
- `scroll` is the only key the app writes. Every other key is yours; no frontmatter is fine too.
- **Versions.** Files with the same `artist` + `title` are one song: one sidebar row with a
  count badge, a dropdown in the toolbar, the versions in the row's right-click menu, and `n`
  cycles them. The label is the `version:` key (`UG chords 4169`, `capo 2`, `live`), else the
  `(…)` suffix of the file name. The plain `<Artist> - <Title>.tab` always sorts first. Note
  that ` #` inside a frontmatter value starts a comment, so write `UG tabs 104578`, not `#104578`.

The full example is [`tests/fixtures/sample.tab`](tests/fixtures/sample.tab).

## Getting tabs in

`tools/tab-import.py` writes a cleaned `.tab` file from the places tabs usually live. Python 3,
standard library only; the `pdf` and `scan` legs shell out to `pdftotext` / `pdftoppm` / `tesseract`
(`brew install poppler tesseract`).

```bash
T=tools/tab-import.py
python3 $T ug  'https://tabs.ultimate-guitar.com/tab/...'   # one Ultimate Guitar page
python3 $T ug  'Radiohead - Creep' [--chords]                # UG search, most-voted version
python3 $T pdf song.pdf                                      # text PDF
python3 $T scan song.pdf|png|jpg                             # scanned page (OCR; check the result)
```

Section headers are normalised to `[Section]`, `[tab]`/`[ch]` markup is stripped, capo and
tuning land in the frontmatter, and a second import of the same song becomes a version
(`<Artist> - <Title> (<version>).tab`). Flags: `--title --artist --tuning --capo --bpm --scroll
--out <dir> --dry-run`. Fetching a page from Ultimate Guitar is for your own use of a tab you
can already read in a browser; it is not an API and may break when the site changes.

If you use [Claude Code](https://claude.com/claude-code), the same script is wrapped as a `/tab`
skill in [dan-slater/daniel-dev-skills](https://github.com/dan-slater/daniel-dev-skills), so
`/tab <url>` does the import for you.

## Testing

```bash
make test        # build + the FIFO harness, app invisible (no window, no Dock icon, no focus)
make test-full   # visible, + the real-keystroke leg (steals focus, leave the Mac alone)
```

`tests/ui.sh` launches the built bundle against a throwaway library and drives it two ways:

- through `TABS_TEST_FIFO`, a FIFO the app reads command words from. They go through the same
  `Voice.apply` the recogniser calls, so the voice path is tested without a microphone;
  `state` writes a JSON line (running, speed, scroll y, wrapped lines, …) to `$FIFO.out`.
- through real keystrokes with System Events (`FULL=1`; needs Accessibility for the terminal).

Play mode is tested the same way: `play <chart>` opens a chart without the mic, `note 64`
injects a heard pitch, `game` writes the play state, and `feed <wav>` streams a recording into
the real pitch judge in real time (the harness renders a plucked-string take of a public-domain
chart with `pitchbench synth` and checks that every note is heard).

It also checks that the speed round-trips into the file's frontmatter, that the folder watch
picks up a new file, that versions cycle, and that no tab line wraps. Screenshots of the live
window land in `tests/shots/` (needs Screen Recording for the terminal; otherwise an in-app
render that does not apply dark mode).

## Licence

MIT. The sample tab is a traditional song in the public domain.
