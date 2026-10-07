# tabs-app — handover log

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
> **Light-mode trap (fixed):** Daniel's Mac is in system Light mode; `NSColor.textColor
> .withAlphaComponent()` resolves against the SYSTEM appearance, so the stave lines drew
> near-black on the dark app. `ScrollText` now uses fixed `ink`/`stave` colours. Never derive
> from a dynamic NSColor in this app. (Same root cause as the in-app `shot` fallback dropping
> dark-mode text.)
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
