# MacTabs (was tabs-app) — handover log

> ## 🎸 CLOSED 2026-11-08 (evening): SIDEWAYS TAB BY DEFAULT, CAPO HANDLING, SILENCE GATE — READ THIS + THE BLOCK BELOW
>
> **Goal:** the play-mode ear (NoteJudge + Basic Pitch, block below) proven on Daniel's guitar; then v0.3.0.
>
> **⚠️ UNCOMMITTED (master):** `research/2026-11-07-charts-from-video/` only. Keep it (public vs private undecided).
> Everything else committed and pushed; HEAD == origin `69fe84c` + this block.
>
> **What shipped after the block below:**
> - `ad5f2a7` Daniel: falling lanes confuse → **Tab strip (sideways) is the default**; Design switcher (⌘,) Highway =
>   Tab strip | Printed tab | Printed, centred | Falling lanes. His saved `design.highway` was "Falling lanes"; set to
>   "Tab strip" with `defaults write`. He has not picked yet: bake his pick in, delete the fork.
> - `69fe84c` **Capo**: Sparks (capo 1) never passed chord 1 because he played open Am (log: A2 in tune, a semitone under
>   the expected A#2…F4). Header shows "capo N · c"; the Listener listens for the step a capo lower and the game says
>   "that sounded 1 fret low: no capo on? press c"; `c` / FIFO `capo` toggles. `Chart.capo` (+ JSON "capo").
> - Same commit: **Basic Pitch hallucinates in silence** (note 0.9 on zeros; it normalises input) → Hearing needs
>   NoteJudge's gate + share too (bench mode=6, −0.5 point). Feeder race fixed (a new `feed` stops the old thread).
>   `make test` 42/42 (new capo test). README hold-out numbers (94/65/74) predate the gate: a `suite --live` re-run was
>   in flight at close; re-run and update README + `Hearing.swift` doc if they moved by more than a point.
>
> **Blockers:** none. **Waiting on Daniel:** live test of the ear (card `mactabs-hybrid-ear-1108`), room recording
> (card `mactabs-room-rec-1108`), highway layout pick, research folder public/private.
>
> **Gotchas:** his Sparks session played at −50..−57 dBFS (quieter than the morning's −30..−50): closer to the mic.
> Basic Pitch output is meaningless without real signal: never drop the level gate. UI asks: options behind the
> Design switcher, `make reload`, no screenshot loop (CLAUDE.md).
>
> **Pointers:** `Sources/NoteJudge/{Hearing,NoteModel,NoteJudge,Chart}.swift`, `Sources/MacTabs/{Game,Listener}.swift`,
> `tools/guitarset-bench.py`, `tools/basicpitch-bench.py`, play logs `~/Library/Logs/MacTabs/play-*.jsonl`.
>
> Next: sessions/mactabs.md, session 2026-11-09-ear (Mon 9 Nov)

> ## 👂 GUITARSET BENCH BUILT, PLAY MODE NOW LISTENS WITH NOTEJUDGE + BASIC PITCH (2026-11-08, afternoon) — READ THIS FIRST
>
> **Goal:** a pitch judge trustworthy on Daniel's guitar, chords included, tuned on realistic simulations.
>
> **⚠️ UNCOMMITTED (master):** `research/2026-11-07-charts-from-video/` only, still held back (public vs private
> undecided). Do NOT delete it. Everything else is committed and pushed (`9d20093`, `9e2eeeb`, `eeffbd2` + this block).
>
> **What shipped:**
> - **Bench:** `tools/guitarset-bench.py prepare` turns GuitarSet (CC BY 4.0, 360 takes, hex-pickup notes) into charts +
>   48 kHz "laptop mic" audio (4th-order HP 100–150 Hz, LP 8–12 kHz, small room, levels from Daniel's play logs:
>   playing −36..−26 dBFS, room ≈ −68, mains hum 100/120 Hz + harmonics + hiss; seeded per take) in
>   `~/Library/Caches/MacTabs/guitarset` (~2 GB, outside the repo). Players 00–03 = `laptop-tune.tsv`, 04–05 = `laptop-hold.tsv`.
>   `pitchbench suite <manifest>` replays each take through the game's own wait-mode judging (arm, since, allowing,
>   0.6 s lookahead) and counts **decoys** (the step ±1 semitone, ±1 octave) as false accepts; `--why` says which test
>   stopped each missed note; `--live` runs the app's `Hearing`; `--post <dir> mode=1..5` runs Python-streamed posteriors
>   (`tools/basicpitch-bench.py` → `bp-laptop/*.bp`); `probe <wav> <midi> <t0> <t1> <armed>` prints one note hop by hop.
>   `tools/guitarset-bench.py tune [--hybrid]` is a coordinate search (objective in `score()`: mean hit over
>   single/dyad/chord − decoys (−12 at ¼ weight) − 2×premature).
> - **NoteJudge chord fix:** the overtone veto counted a chord's own notes as a lower note's harmonics (C3 E3 G3 = C2's series);
>   now skipped (`made`). Veto factored out as `NoteJudge.overtone`. Chord options added (all off by default).
> - **Hearing (the app's ear now):** `Sources/NoteJudge/{Hearing,NoteModel}.swift` + `Model/nmp.mlmodelc` (Basic Pitch,
>   Apache-2.0, 272 KB, licence bundled). A note counts when Basic Pitch's note posterior ≥ 0.25 (frames ≥ 5 old) AND
>   an onset shows (BP onset ≥ 0.4 or NoteJudge's onset test with `Config.hybrid`), and a single note is not an overtone.
>   Model warms off-queue when play opens (`NoteModel.prepare`, first GPU/ANE run ~1.5 s); NoteJudge alone until then.
>   `defaults write dev.danielslater.tabs play.ear judge` = old judge. Logs + `game` state record `ear` / `model`.
>
> **Numbers (held-out players 04–05, first pluck, single / dyad / chord):** morning judge 87 / 18 / 22 % →
> NoteJudge alone now 87 / 33 / 39 % → **Hearing 94 / 65 / 74 %** (solo 98 %, comping 77 %); wrong fret 0–2.5 %,
> overtone 0.4–4 %, premature 2.4–5 %; latency median 47 ms single / 77 ms chord (+ buffer). Real Für Elise: 98.9 %.
> CPU: ~9 % of a core live on GPU/ANE (CPU-only CoreML is ~60 %, don't).
>
> **Findings worth keeping:** Basic Pitch's onset posterior needs 4–5 frames (~50 ms) after a frame to peak; younger
> frames sit at a ~0.18 noise baseline and caused 20 %+ premature passes. Its onset head is weak on strums, its note head
> is excellent on pitch identity: hence the hybrid. Remaining misses: funk chops (36 % of notes < 0.15 s) and repeated
> same-pitch notes (some "premature" there is GuitarSet annotation ambiguity, checked by hand on two takes).
>
> **Open:** (1) Daniel's live test of the new ear (card on LeachieTok); compare `play.ear judge` if it feels worse.
> (2) Card `mactabs-room-rec-1108`: may we record 10 s of his room (FIFO `record 10 <path>`) for the bench's noise? Unanswered.
> (3) Research folder public vs private. (4) Plan step 3 (fine-tune on zulzi GPU) only if live chords still disappoint:
> GuitarSet + augmentation, the onset head on strums is the target; export CoreML. (5) Later: aligner for band mixes, v0.3.0.
>
> **Gotchas:** `pitchbench suite --live` must stay ≤ 3 takes in parallel and each CoreML run needs `autoreleasepool`
> (IOSurface exhaustion otherwise; both done). zsh: pass key=value pairs as separate words (`${=v}`).
> The tuner calls `.build/release/pitchbench` unless `PITCHBENCH=` points at a pinned copy: rebuilding mid-tune changes it.
> Every judge change: `pitchbench eval` on the real take, synth and hum=-35 (unchanged this session), plus
> `pitchbench suite <elise manifest> --live`, then `make test` (38/38).

> ## 🎸 LIVE PLAY TESTS DONE, JUDGE HARDENED → NEXT: GUITARSET SIMULATION BENCH + BASIC PITCH (2026-11-08) — READ THIS FIRST
>
> **Goal:** make the wait-mode pitch judge trustworthy on Daniel's real guitar, chords included, by
> tuning against realistic simulations (and, if needed, a trained model) instead of by hand.
>
> **⚠️ UNCOMMITTED (master):** `research/2026-11-07-charts-from-video/` only, held back on purpose
> (public vs private still undecided). Do NOT delete it. Everything else is committed and pushed; HEAD == origin.
>
> **What shipped this session (after `f5bb51a`, all on master):**
> - `9ac088e` room-hiss gates (harmonic share + min level) · `99d2234` overtone veto off, re-pluck rule, cents readout ·
>   `50ffe2f` NaN crash fix (cents → Int on the listener queue) · `9d0877a` **play any tab from its own staves**
>   (`g` / gamecontroller icon; `Chart.fromTab`, tuning + capo applied; 3+ note chords pass on lowest + highest) ·
>   `c474984` smarter overtone veto (a lower note explains the expected one away only when its OWN harmonics sound and
>   it just got louder) · `dd8c92a` learned per-bin noise profile (100 Hz mains hum), chord-aware gates, `(xN)` repeat
>   expansion, `tools/align-chart.py` (tab ↔ recording alignment), pitchbench `hum=`, overtone metric, `tabchart --json`.
> - Bench now (real Für Elise take): 85% first-pluck, ~40 ms analysis latency, overtone false accepts 7%, wrong 1.3%.
>   Synthetic Fly Me To The Moon (jazz chords) + hum: only 69%. **Chords are the weak spot.**
>
> **Daniel's live findings (logs in `~/Library/Logs/MacTabs/play-*.jsonl`):** (1) room noise advanced the highway (fixed);
> (2) re-plucks of the same note under ringing open strings were missed (fixed); (3) after that, overtones of a played
> low note were accepted, e.g. G#2 → G#4/D#4 (fixed, smarter veto); (4) Fly Me To The Moon chords barely register
> (partly fixed); (5) his room shows constant G#2/G#3/G#4 ≈ 100 Hz mains hum + harmonics (noise profile added, unverified live).
>
> **Song timing (tabs carry no rhythm):** tab-line songs play with column spacing (0.3–1 s per step). The aligner
> works on Für Elise (median 12 ms; first 10 notes 90% within 150 ms; the old chart is wrong at 6–16 s, the aligner right)
> but fails on full-band mixes: well-matched steps Down By The River 67%, Ode To Joy (some guitar video) 42%,
> Cough Syrup 23%, Cayman Islands / Wish You Were Here 14%, Californication 9%, Shallow 5%; Let Her Go yt-dlp failed.
> Outputs are in the session scratchpad only; NOTHING was installed into `~/Tabs` (only Für Elise has a real chart).
>
> **Open decisions awaiting Daniel:** research folder public vs private. (He green-lit the plan below: "go ahead".)
>
> **Next actions (agreed 2026-11-08: Mac for 1–2, zulzi GPU only for 3):**
> 1. **GuitarSet simulation bench (Mac):** download GuitarSet (CC BY 4.0, ~3 h acoustic guitar, solo + comping, per-note
>    string/fret/onset from a hex pickup; mic audio ~1 GB) into a gitignored cache. Add a pitchbench (or Python) mode
>    that replays each excerpt through a laptop-mic EQ + room noise (`hum=` model; better: a 10 s recording of Daniel's
>    room, ask first) and scores hit / false accept / latency per note AND per chord. Then tune `NoteJudge.Config`
>    automatically (grid / Bayesian) against it.
> 2. **Basic Pitch comparison (Mac):** CoreML Basic Pitch (Apache-2.0; last session ran it with `scipy<1.13`, `setuptools<70`)
>    as the detector: onset posteriors per semitone, judge = the expected notes' posteriors. Score on the same bench incl.
>    streaming latency (sliding windows). Decide DSP vs model vs hybrid.
> 3. Only if 2 is close but not enough: fine-tune / train a small model on GuitarSet + augmentation on zulzi GPU
>    (`onnxruntime-gpu==1.22.0`), export to CoreML for the app. Daniel's play logs can later add his guitar/room.
> 4. Later: better aligner features for band mixes (source separation, key/capo check), then v0.3.0 (2026-11-06 list).
>
> **Gotchas:**
> - `make reload` only reopens MacTabs if it is running; Daniel asked to have it opened, so `open ~/Applications/MacTabs.app` is fine when he is testing.
> - Every judge change: `pitchbench eval <wav> <chart> -q` on BOTH the real take (`research/.../bench/data/strip/9Ikb8QhVev0.wav`
>   + `tab-ocr/elise_chart.json`) and the seeded synth (`pitchbench synth … 48000`), plus `hum=-35`; then `make test` (37/37).
> - The bench's "premature/near" numbers are inflated by the Für Elise chart's own ±0.1–0.3 s timing errors.
> - The pluck log's "heard" list is open-ended (all candidates) and misleads; hits are judged only on expected notes.
> - Laptop mic rolls off below ~120 Hz: low E/A fundamentals are weak; the judge leans on harmonics 2+.
> - zsh does not word-split `$args`: loop over single key=value strings in sweeps.
> - `tools/align-chart.py` is a uv script (`#!/usr/bin/env -S uv run --script`); audio cache `~/Library/Caches/MacTabs/audio`.
>
> **Pointers:** `Sources/NoteJudge/NoteJudge.swift` (all thresholds in `Config`, each commented), `Sources/NoteJudge/Chart.swift`,
> `Sources/MacTabs/{Game,Listener}.swift`, `Sources/pitchbench/main.swift`, `tools/align-chart.py`, README "Play mode",
> `~/dan-hub/daniel-dev-skills/sessions/mactabs.md` (chat row added).

> ## 🎮 PLAYABLE DEMO BUILT: WAIT MODE + PITCH JUDGE, READY FOR THE GUITAR (2026-11-07, evening) — READ THIS FIRST
>
> **Goal:** first playable demo of the guitar game: Für Elise in "wait mode", heard through the Mac mic.
>
> **UNCOMMITTED:** `research/2026-11-07-charts-from-video/` (still held back on purpose; public vs
> private undecided). Everything else is committed and pushed.
>
> **What shipped (unreleased, after v0.2.1):**
> - `Sources/NoteJudge/` (library): pitch judge that answers "was the EXPECTED note just struck?" per
>   11 ms hop. It checks harmonic energy per candidate note (zero-padded FFT), an onset rise, contrast vs ±1
>   semitone on resolved harmonics only, or on the *new* energy alone when the last note still rings next
>   door (E–D# in Für Elise). It also needs harmonic 1 or 2 present (kills ghost notes below) and odd harmonics
>   present (kills "octave too low"), and rejects upper partials of a louder lower note. Also `Chart` (JSON → steps).
> - `Sources/pitchbench/`: `eval <audio> <chart> [-v|-q] [key=value] [--align <source>]`, `synth <chart> <wav> [rate] [offset]`.
> - Play mode (`Game.swift`, `Listener.swift`): `g` / gamecontroller icon / **Play** menu opens
>   `Artist - Title.chart.json` from the tabs folder. It stops at each note until the pitch is heard (0.6 s lookahead
>   for early plucks), with `space` pause, `↑↓` speed, `r` restart, `esc` leave. Voice turns off on start (shared mic).
>   Every session writes a JSONL log to `~/Library/Logs/MacTabs/play-*.jsonl` (plucks, hits, latency per hit).
> - Design forks (`hasForks = true` again): **Highway** = Falling lanes (default) | Tab strip; **Notes show** =
>   Fret (default) | Fret + note.
> - FIFO words: `play <chart>` (no mic), `note <midi…>`, `feed <wav>` (real-time into the judge), `game`
>   (state JSON), `pace <x>`, `leave`, `set <defaults key> <value>`, `record <secs> <path>` (mic to file).
> - `make test` 34/34 (deterministic: seeded synth). `~/Tabs/Beethoven - Für Elise.chart.json` copied
>   from the research chart (private, not in git); fixture `tests/fixtures/elise-opening.chart.json` is hand-written PD.
>
> **Measured offline (`pitchbench eval` on the real YouTube recording, 89 steps):** right note on the first
> pluck 84.3%, analysis latency median 40 ms / p90 64 ms (plus ~10–20 ms buffer + device input latency
> live). Semitone false fires 7% (inflated by the chart's ±0.1 s timing), other-pitch fires 11%. The
> synthetic take: 72% hit, 0.5% semitone false fires. Misses cluster on low bass notes inside chords.
>
> **NOT measured yet (the room test):** Daniel declined the speaker→mic loop tonight. The real numbers come
> from his guitar session: read the play log (hits / plucks = right-note rate; `latency_ms` per hit).
> To score a room recording: FIFO `record 70 /path.wav`, then `pitchbench eval /path.wav <chart> --align <source.wav>`.
>
> **Next: Daniel with the guitar (same session as the v0.3.0 play test):**
> 1. Quit and reopen MacTabs (or `make reload`), press `g` on any song, or **Play → Beethoven - Für Elise**.
>    Allow the mic if asked. Play; try ⌘, for the two layouts.
> 2. Read `~/Library/Logs/MacTabs/play-*.jsonl`, then tune `NoteJudge.Config` (`pitchbench` key=value sweeps).
> 3. Then the 2026-11-06 list (voice over strumming, first-run sample, import, folder setting) → v0.3.0.
>
> **Gotchas:** the offscreen `shot` render shows the header/sidebar white (render artefact, not the app).
> The research chart's times come from the video, so its gaps are uneven; wait mode hides that. The judge
> is lenient on purpose (a chord passes when each note's harmonics show, octave-doubled bass included).

> ## 🎮 GAME DIRECTION: CHARTS-FROM-VIDEO RESEARCH + PAPER DONE → NEXT A PLAYABLE DEMO (2026-11-07) — READ THIS FIRST
>
> **Goal:** turn MacTabs into an indie Guitar-Hero/Rocksmith-style game played on a real guitar
> into the Mac mic. This session researched where charts (string, fret, time) come from and wrote
> a paper; next session builds the first playable demo.
>
> **⚠️ UNCOMMITTED (master): `research/2026-11-07-charts-from-video/`** — scripts (`bench/`),
> results tables (`bench/results/`), paper (`paper/paper.tex` + `paper.pdf`, tectonic), README.
> Held back on purpose: Daniel has not yet said whether it goes in this PUBLIC repo or somewhere
> private. Do NOT delete it. `bench/data/` (YouTube videos, GuiFiR frames/crops/audio, caches,
> ~2 GB) and the 132 MB `results/e1_cv_rows.pkl` are gitignored (copyright / non-commercial data).
> No app code changed; HEAD == origin `1c9bedf` before this block.
>
> **What came out of it (details in the paper):**
> - Audio gives timing and pitch well; string/fret is the weak link. Hand position from video
>   settles it: RTMW hand pose + plain neck box + **label-free per-clip fret self-calibration**
>   → 94.8% string/fret vs 86.0% lowest-fret (song-level 5-fold CV, GuiFiR, 130 clips/35 songs).
> - On-screen tab strips in YouTube lesson videos can be read directly (`bench/strip_ocr.py`,
>   self-configuring; 7 channels, 87% digits right, 98% on clean styles, 41 ms timing).
> - **The demo chart already exists:** `research/2026-11-07-charts-from-video/tab-ocr/elise_chart.json`
>   = 107 Für Elise notes `{t, ts (snapped to audio onset), string, fret, midi}` from YouTube
>   `9Ikb8QhVev0`.
>
> **Open decisions awaiting Daniel:** where to commit the research folder (public mactabs vs private).
>
> **Next actions (the playable demo):**
> 1. **Live note detection test** (the untested risk): AVAudioEngine mic tap → pitch (YIN/McLeod on
>    vDSP, or match energy at the *expected* note's fundamental + harmonics, which is more robust).
>    Measure: right-note detection over a room with the laptop mic, and pluck→registered latency.
>    Make it a hidden/test-mode feature so `make test` stays invisible (FIFO can inject notes).
> 2. **Wait mode:** six-lane highway (lanes = strings, fret numbers on the notes) from
>    `elise_chart.json`; it stops until the right pitch is heard. Judge by **pitch, not string**.
> 3. Then hand to Daniel with the guitar. The same session covers the pending **v0.3.0 play
>    test** (voice words over strumming) — see the 2026-11-06 block below.
>
> **Gotchas:**
> - The mic is shared with voice commands (`v`), so turn voice off in play mode.
> - Never launch the app in the foreground while Daniel works; UI asks = options behind the Design switcher (CLAUDE.md).
> - zulzi GPU: `onnxruntime-gpu==1.22.0` + `onnxruntime.preload_dlls()` (1.23+ wants CUDA 13); MediaPipe can't run there (no libGLESv2) → run it on the Mac.
> - Basic Pitch on the Mac: CoreML model path + `scipy<1.13` + `setuptools<70`.
> - GuiFiR train labels disagree with audio (don't use them as ground truth).
> - The venv used is in a session scratchpad and will vanish; recreate it with `uv` (numpy, opencv-python-headless, librosa, mediapipe, basic-pitch[coreml], pandas, matplotlib, pillow).
>
> **Pointers:** `research/2026-11-07-charts-from-video/README.md` (how to rebuild everything),
> `paper/paper.pdf`, the memory note `mactabs.md`, `~/dan-hub/daniel-dev-skills/sessions/mactabs.md`.

> ## 🎸 FINISH LINE PLANNED: PLAY TEST → v0.3.0 → LAUNCH DRAFTS (2026-11-06) — READ THIS FIRST
>
> **Goal:** finish MacTabs: play test with the guitar, fix what it finds plus the new-user
> gaps, release v0.3.0, then draft the launch posts.
>
> **UNCOMMITTED WIP:** none. This chat only got its bearings and committed the 2026-10-17 block below.
> HEAD == `origin/master` after this commit.
>
> **What shipped:** nothing new in code. State is still the 2026-10-17 block below (icon row,
> PDF export, invisible tests; unreleased since v0.2.1).
>
> **Blockers:** the play test (Daniel with a guitar; the voice words have never been tried
> over real strumming). The new-user gaps can be built without him:
> 1. Empty library on first run: seed the public-domain sample into a new `~/Tabs`.
> 2. No in-app import: drag `.tab`/`.txt` files onto the window, or File > Import.
> 3. The library folder is only settable with `TABS_DIR` (`Model.swift:108`): add a
>    "Choose folder…" setting, persisted.
>
> **Gotchas:** as in the 2026-10-17 block. Keep the marketing session clear of paramaterial's
> Show HN (Tue 10 Nov 15:00).
>
> **Pointers:** `Sources/MacTabs/Model.swift` (library folder), `CLAUDE.md`, the block below.
>
> Next: sessions/mactabs.md, session 2026-11-06-playtest (Fri 6 Nov evening).

> ## 🎸 ICON ROW + PDF + INVISIBLE TESTS, READY FOR THE PLAY TEST (2026-10-17) — READ THIS FIRST
>
> **Goal:** make MacTabs pleasant to use and portfolio-ready: Daniel plays from it, then
> v0.3.0 ships to GitHub and a week of marketing gets planned.
>
> **UNCOMMITTED WIP:** only this HANDOVER block. Everything else is committed and pushed;
> HEAD `8e4eefe` == `origin/master` (`dan-slater/mactabs`, public). Keep it.
>
> **What shipped (since v0.2.1, all unreleased; the last release is v0.2.1):**
> - Daniel's 34 Ultimate Guitar favourites imported into `~/Tabs` (37 files, 35 songs).
>   Rhiannon's favourite was an "Official" (no text) tab, so the most-voted chords version was
>   taken. The UG cookie file was deleted; Daniel was told to log out of UG to kill the cookie
>   he pasted into the chat.
> - Icon row right-aligned above the song name (`TabActions.swift`): versions menu, source page
>   (the ONLY place the source link lives), chords, voice, full screen, export (Save as PDF,
>   share, copy text, Show in Finder). Toolbar title blank; the name is shown large in the pane.
> - Save as PDF (`PDFExport`, A4, aqua appearance so it is dark on white in dark mode).
> - Design switcher (`Design.swift`, ⌘, / toolbar sliders): all forks settled and removed;
>   `DesignPanel.hasForks = false` hides the button until the next UI request. Rules in `CLAUDE.md`.
> - Fixes: songs opened one line down (automatic toolbar insets, now off in `ScrollText`);
>   the sidebar folder label covered the last row.
> - Tests: `make test` runs the app INVISIBLY (`TABS_TEST_HIDDEN`: alpha 0, no Dock icon, no
>   focus) and no longer quits Daniel's open copy; `make reload` reinstalls and reopens in the
>   background. 23/23, incl. two PDF checks via the FIFO word `pdf <path>`.
>
> **Blockers:** none. Waiting on Daniel: the play test with a guitar (voice words over strumming).
>
> **Gotchas:** (1) UI work = several options behind the Design switcher, verify with
> `make reload` only, no harness or screenshot loop (`CLAUDE.md`, memory
> `ui-options-switcher-light-testing`). (2) Never launch the app in the foreground while Daniel
> works. (3) `.toolbar(removing: .title)` needs macOS 15; the app targets 14. (4) The bundle ID
> stays `dev.danielslater.tabs` on purpose (keeps prefs and mic permission).
>
> **Pointers:** `CLAUDE.md`, `README.md`, `Sources/MacTabs/TabActions.swift`, `tests/ui.sh`.
>
> Next: superseded by the 2026-11-06 block above.

> ## 🎸 RENAMED TO MACTABS + v0.2.1 (2026-10-09) — READ THIS FIRST
>
> **Done:** app, repo and folder are now **MacTabs**: GitHub `dan-slater/mactabs` (old URL
> redirects), local `~/dan-hub/mactabs`, `~/Applications/MacTabs.app` (old `Tabs.app` removed),
> target `Sources/MacTabs`, `res/MacTabs.icns`. Bundle ID kept as `dev.danielslater.tabs` so
> prefs and mic permission carry over; the library folder stays `~/Tabs`. Release **v0.2.1**
> ships `MacTabs.app.zip`; CI green. `/tab` skill symlink repointed (`daniel-dev-skills`
> `d1ebe11`). After moving the folder, `make clean` once: SwiftPM's module cache pins the path.
>
> **Bug fixed:** a launch after a force-quit showed NO window (saved state restored zero
> windows). The app now registers `ApplePersistenceIgnoreState`. The harness passes it too,
> returns focus to the previous app in the fast run, and a 20 s watchdog fails the run if the
> test FIFO never opens (it used to hang forever).
>
> **Outstanding (Daniel is using the app himself first; launch posts wait):** see the list in
> the 2026-10-09 session reply. Biggest gaps for strangers: empty library on first run, no
> in-app import, folder only settable by env var, not notarised. `bpm:` is stored, unused.

> ## 🚀 v0.2.0 PUBLIC ON GITHUB (2026-10-08, evening) — READ THIS FIRST
>
> **Done:** repo `dan-slater/tabs-app` is **PUBLIC**, MIT, description + topics set, CI
> (`.github/workflows/build.yml`, macos-15 `swift build` + `make`, green), release
> **v0.2.0** with `Tabs.app.zip` (ad-hoc signed, not notarised → right-click Open).
> README rewritten for a portfolio reader with `docs/screenshot-{light,dark}.png`.
> Sample fixture is now **House of the Rising Sun (traditional, public domain)** — the Pink
> Floyd lyrics could not ship in a public repo; `tests/fixtures/second.tab` artist is `Zed`
> so the sample still sorts first. The importer's canonical copy is `tools/tab-import.py`
> **in this repo**; `daniel-dev-skills/tab/scripts/tab-import.py` is now a symlink to it
> (`38c6cc9`). `CFBundleShortVersionString` 0.2.0; Fretboard pinned to revision `0803c34`.
>
> **Testing is now two-speed** (Daniel: "testing gets in the way of me using my Mac"):
> `make test` = FIFO leg only, 19 checks, no keystrokes, no focus steal — keep working;
> `make test-full` (`FULL=1 tests/ui.sh`) adds the System Events keystroke leg, 26 checks,
> steals focus. New FIFO words `next` (cycle version) and `chords` (toggle panel).
>
> **Next:** get stars/users — launch copy (Show HN, r/Guitar, r/macapps) is in the session
> reply of 2026-10-08; Daniel posts, agents never post. Nice-to-haves that help adoption:
> Homebrew cask (needs a stable download URL — the release asset is one), a GIF of the scroll
> + voice in the README, notarisation (needs a paid Apple Developer account, R1 700/yr-ish).
> Open from before: real-world PDF + phone scan to pilot `pdf`/`scan`; the live mic test.

> ## 🎸 v0.2: ICON + VERSIONS + SYSTEM APPEARANCE (2026-10-07/08) — READ THIS FIRST
>
> **Goal:** polish the viewer after v0.1 — app icon, one row per song with version switching,
> follow the Mac's Light/Dark setting — and keep the `/tab` importer honest against real pages.
>
> **Tree is clean; HEAD `33aeb27` == `origin/master`.** Nothing uncommitted here. (The sibling
> repo `daniel-dev-skills` carries UNRELATED uncommitted WIP from other sessions — a
> `remote-tmux-orchestrator` → `tmux-orchestrator` rename, nsuna skill edits, `marpowerpoint/`.
> Not this project's; do NOT stage it with `git add -A` there. The `tab` skill itself is
> committed and pushed, `c2b6ef7`.)
>
> **What shipped:** `f7cbad3` app icon (`res/Tabs-icon.svg` is the source → `res/Tabs.icns`
> via rsvg-convert + iconutil; `CFBundleIconFile` in `res/Info.plist`) + **song versions**:
> `Song.group` collapses same artist+title into one sidebar row with a count badge, toolbar
> segmented picker, right-click menu (+ Show in Finder), `n` cycles, last-used version
> remembered per song; `version:` frontmatter key labels them; the plain-named file sorts
> first. Library reload debounced 0.25 s + re-read at 1 s (create event fires before the
> writer finishes). `cc48a0b` + `33aeb27` appearance: forced dark REMOVED, app follows the
> system; `ScrollText` uses `labelColor` + an `NSColor(name:)` block for the stave. Harness
> 26/26 (`make test`), every keystroke goes through `key` which re-asserts frontmost.
> `/tab` skill: writes `version:`, names a repeat import `<Artist> - <Title> (<version>).tab`,
> reads capo from `tab_view.meta` (the `tab.capo` field is null on UG). `~/Tabs` holds
> The A Team (capo 2), Creep, Wish You Were Here ×2 (sample + UG tabs 104578).
>
> **Still wanted from Daniel:** a real-world tab PDF and a phone-photo scan (pdf/scan legs
> were piloted on a synthesised PDF only); the live mic→speech hand test with a guitar.
>
> **Gotchas:** (1) ` #` inside a frontmatter value starts a comment — version labels carry
> no hash. (2) Never call `withAlphaComponent()` on a dynamic NSColor: it freezes the colour
> under the appearance current at that instant (how the stave went near-black on this
> Light-mode Mac). (3) The harness drops keystrokes if ANY other window activates mid-run —
> don't drive the screen while `make test` runs; a lone failure at "space pauses" is that.
> (4) The in-app `shot` fallback is layout-only evidence; real evidence is `screencapture -l`.
> (5) Select a sidebar row from a script with System Events `set selected of row N of
> outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1 to true`.
>
> **Next actions (none urgent):** 1. Daniel plays from it; report anything that reads wrong.
> 2. Pilot `pdf`/`scan` on his real files when they arrive. 3. Nice-to-haves never asked for:
> transpose, bpm metronome. Teal chord colour is a little light on white — only if he notices.
>
> **Pointers:** `README.md` (format incl. versions, keys, harness), `tests/ui.sh`,
> `~/.claude/skills/tab/SKILL.md`, memory `tabs-app.md`.

> ## 🎸 BACKED UP + /tab SKILL BUILT (2026-10-06, evening) — READ THIS FIRST
>
> **Done this session:** private repo `dan-slater/tabs-app` created and `master` pushed (the
> earlier block below predates the remote). The `/tab` skill is built and live:
> `~/dan-hub/daniel-dev-skills/tab` (commit `1d48bd5`, pushed), symlinked at
> `~/.claude/skills/tab`. One stdlib script, `scripts/tab-import.py`, three legs: `ug <url |
> "artist - title"> [--chords]` (UG `js-store` JSON blob, browser UA; search takes the most-voted
> version of the asked type), `pdf <file>` (`pdftotext -layout`), `scan <file>` (`pdftoppm` +
> `tesseract --psm 4 tsv`, columns rebuilt from word boxes because plain tesseract trims leading
> spaces). Section headers are normalised to `[Section]`; `[tab]`/`[ch]` markup stripped.
>
> **Proven:** Wish You Were Here (URL), Creep (search, chords), Stairway (search, tabs) imported
> clean; Creep opened in the real app with chords detected and the panel showing G B C Cm
> (real `screencapture -l` shot). PDF leg faithful to ±2 chars on a PDF synthesised from the
> Creep text; scan leg keeps placement but drops isolated single-letter chords (OCR limit).
> `~/Tabs` now holds the sample + Creep + "Wish You Were Here (UG 104578)".
>
> **Still wanted from Daniel:** a real-world tab PDF and a phone-photo scan to harden the
> `pdf`/`scan` heuristics; the live mic→speech hand test with a guitar.
>
> **2026-10-07 morning:** app icon (`res/Tabs-icon.svg` → `res/Tabs.icns`, wired by
> `CFBundleIconFile`; regenerate with rsvg-convert + iconutil, the SVG is the source).
> **Song versions:** same artist+title = one sidebar row (`Song.group`), count badge, toolbar
> segmented picker, right-click menu, `n` cycles; the chosen version is remembered per song;
> `version:` frontmatter key (no `#` — it starts a comment). Library reload is debounced
> 0.25 s + re-read at 1 s, because a create event lands before the writer finishes the file.
> Harness: every keystroke now goes through `key` (re-asserts frontmost — other windows
> activating mid-run were eating keys); 26/26. The A Team imported (capo now read from
> `tab_view.meta`, not `tab`).
>
> **Appearance (2026-10-07):** the app now FOLLOWS the system (no `preferredColorScheme`);
> verified light + dark + live switch. `ScrollText` colours are dynamic (`labelColor`, a
> `NSColor(name:)` block for the stave). Never call `withAlphaComponent()` on a dynamic
> NSColor — it freezes the colour under the appearance current at that moment, which is how
> the stave once drew near-black on Daniel's Light-mode Mac.
>
> **Harness trick learned:** to select a sidebar row from a script use System Events
> `set selected of row N of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1
> of window 1 to true` — clicking the row's static text does nothing.

> ## 🎸 TABS VIEWER v0.1 SHIPPED, /tab SKILL NOT STARTED (2026-10-06) — READ THIS FIRST
>
> **Goal:** a very simple native Mac app for scrolling through guitar tabs, with a native
> `.tab` format that a future `/tab` Claude skill writes from a PDF or a browser page.
>
> **What shipped:** `d4699a4` the app (SwiftUI/AppKit, SwiftPM, dep Fretboard MIT for chord
> diagrams + chords-db) + `tests/ui.sh` harness; `5606be0` end-padding + wrap check. Tree is
> clean. Installed to `~/Applications/Tabs.app`. `~/Tabs/` holds one sample (Wish You Were
> Here). **No GitHub remote yet** — local git only, so nothing is backed up.
>
> **Definition of done (v1, as Daniel chose):** autoscroll ✅, chord diagrams ✅, voice
> faster/slower ✅ (word→action path tested; the live mic→speech leg is only hand-testable —
> press `v`, grant mic + speech, say "faster").
>
> **Open decisions awaiting Daniel:** (1) build the `/tab` skill now? (UG URL → embedded JSON
> blob; PDF → `pdftotext -layout`; scans → `tesseract`; clean → write `~/Tabs/<Artist> -
> <Title>.tab`). (2) Create a private GitHub repo `dan-slater/tabs-app`? (3) Where the skill
> lives — `daniel-dev-skills` (personal) rather than `leachie-skills` (agency).
>
> **Gotchas:** chord detection = a line whose every token matches the chord regex in
> `Chords.swift` (slash chords map to `<q>/<bass>` db suffixes, else the plain chord).
> `scroll:` in frontmatter is the ONLY key the app writes (1.5 s debounce after a speed change);
> the folder watch reloads the list, and the open tab's body only if mtime changed. Lines never
> wrap: `ScrollText.fit` shrinks the font to the longest line (min 10 pt). The in-app
> `shot` fallback (cacheDisplay) drops dark-mode text — only `screencapture -l` shots are real
> evidence. Harness FIFO needs ONE persistent writer (`exec 3>fifo`); per-echo writers lose
> lines. Writing >2 files per tool batch tripped the auto-mode classifier this session.
>
> **Next actions:** 1. Daniel tries it with a guitar (`open ~/Applications/Tabs.app`), esp. the
> voice leg. 2. `/tab` skill (needs a UG URL + a PDF to pilot on). 3. `gh repo create
> dan-slater/tabs-app --private` + push. 4. Nice-to-haves not asked for: transpose, app icon.
>
> **Pointers:** `README.md` (format, keys, harness), `tests/ui.sh`, memory `tabs-app.md`.
