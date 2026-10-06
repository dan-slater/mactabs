# tabs-app — autoscrolling tab viewer for the Mac

One window: the tabs in `~/Tabs` on the left, the open tab in big monospace on the right,
chord diagrams beside it. Space starts it scrolling at the speed saved in the file; say
"faster" or "slower" with your hands on the guitar. SwiftUI + AppKit, one dependency
([Fretboard](https://github.com/itsmeichigo/Fretboard), MIT — the chord diagrams and the
tombatossals chords-db).

## Build and run

```bash
make            # build/Tabs.app   (swift build + bundle + ad-hoc sign)
make run        # build and launch
make install    # copy to ~/Applications (then it is in Spotlight)
make test       # build + drive the app through tests/ui.sh
```

Reads `~/Tabs`; set `TABS_DIR=/path` to point elsewhere. The folder is watched, so a file
dropped in (or written by the `/tab` skill) appears in the sidebar at once.

## The file format

`~/Tabs/<Artist> - <Title>.tab`, UTF-8, a small frontmatter block then plain monospace text:

```
---
title: Wish You Were Here
artist: Pink Floyd
tuning: EADGBE
capo: 0
bpm: 60
scroll: 0.6        # lines per second; the app writes this back when you change speed
source: https://... or the PDF it came from
---
[Intro]
    Em7            G
e|--3-----3-----3-----3-----|
B|----3-----3-----3-----3---|

[Verse 1]
C                      D
So, so you think you can tell
```

- `[Section]` on its own line is a section header (orange; `[` `]` jump between them).
- A line made only of chord names (`C  G/B  Am7`) is a chord line (teal) and feeds the
  chord panel. Everything else is shown as is. Lines never wrap: the font shrinks to fit
  the longest line, down to 10 pt, and anything wider scrolls sideways.
- Only `scroll` is written by the app; every other key is yours. No frontmatter is fine too.

## Keys

| Key | Does |
| --- | --- |
| space | start / stop scrolling |
| ↑ ↓ | faster / slower (×1.15 per press, saved to the file after 1.5 s) |
| [ ] | previous / next `[Section]` |
| t / 0 | back to the top |
| + − | bigger / smaller text (upper bound; lines still fit) |
| c | show / hide the chord panel |
| v | voice commands on / off |

## Voice

`v` starts on-device speech recognition (Apple `Speech`; the first time macOS asks for the
microphone and speech permissions). Words that act: **faster**, **slower**, **stop**
(pause, wait), **go** (start, play, scroll), **top** (restart). Recognition sessions are
capped at about a minute, so the app rolls them over every 50 s while listening.

## Getting tabs in: the `/tab` skill

The importer lives in `dan-slater/daniel-dev-skills` as the `tab` skill (symlinked at
`~/.claude/skills/tab`). One stdlib Python script writes `~/Tabs/<Artist> - <Title>.tab`:

```bash
T=~/.claude/skills/tab/scripts/tab-import.py
python3 -I $T ug  'https://tabs.ultimate-guitar.com/tab/...'   # a UG page (its js-store JSON)
python3 -I $T ug  'Radiohead - Creep' [--chords]                # UG search, most-voted version
python3 -I $T pdf song.pdf                                      # pdftotext -layout
python3 -I $T scan song.pdf|png                                 # tesseract, columns rebuilt from word boxes
```

Or just tell Claude `/tab <url>`. The file appears in the sidebar as soon as it is written.

## Testing

`tests/ui.sh` launches the built bundle against a throwaway library and drives it two ways:

- through `TABS_TEST_FIFO` — a FIFO the app reads command words from, which go through the
  same `Voice.apply` the recogniser calls, so the voice path is tested without a microphone;
  `state` writes a JSON line (running, speed, scroll y, wrapped lines, …) to `$FIFO.out`;
- through real keystrokes with System Events (needs Accessibility for the terminal — that
  leg is skipped with a warning otherwise).

It also checks the speed round-trips into the file's frontmatter, that the folder watch
picks up a new file, and that no tab line wraps. Screenshots of the live window land in
`tests/shots/` (needs Screen Recording for the terminal; falls back to an in-app render
that does not apply dark mode — treat those as layout-only).
