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

# tabs-app — handover log

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
