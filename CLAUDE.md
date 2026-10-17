# MacTabs — working notes for Claude

Read `HANDOVER.md` (top block) and `README.md` first.

## UI changes: options first, light checks (Daniel, 2026-10-16)

When Daniel asks for a UI change, ship **several options at once** behind the global
**Design** switcher, not one guess:

- The switcher is `Sources/MacTabs/Design.swift`: one enum per open choice, an
  `@AppStorage("design.…")` key, one row in `DesignPanel`. It opens from the toolbar sliders
  icon (a popover) and from ⌘, (the Settings window). Every choice switches live on his songs.
- Give each request 2–4 real variants. Keep the current look as one of them, and make it
  the default.
- When he picks one, bake it in and delete that enum and its row. Do not let old forks pile up.

Verification for a UI change is: `make reload`, then tell him what to click. `make reload`
installs and, only if MacTabs is already running, reopens it in the background (`open -g`),
so it never jumps in front of what he is doing. **No `make test` and no screenshot loop**
for UI-only work.

Run `make test` when behaviour changes: the parser, scrolling, versions, export, the folder
watch, voice. It runs the app invisibly (`TABS_TEST_HIDDEN=1`: alpha-0 window, no Dock icon,
no focus) and drives it through the FIFO only. Run `make test-full` (visible, real
keystrokes, steals focus) only before a release, and only when he is away from the Mac.
Never launch the app in the foreground while he is working (2026-10-17: "why does the
program keep opening on my screen while you are developing?").

## Repo hygiene

- Stage named paths; this is a public repo (`dan-slater/mactabs`). Fixtures must be public domain.
- After moving the folder, `make clean` once: SwiftPM's module cache pins the absolute path.
- Commit trailer: as the session's attribution reminder says.
