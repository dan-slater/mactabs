# tabs-app — handover log

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
