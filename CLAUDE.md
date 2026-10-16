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

Verification for a UI change is: `make install`, relaunch the app, tell him what to click.
**No `make test` and no screenshot loop** for UI-only work. It is too slow and it takes
over his Mac.

Run `make test` (FIFO only, no focus steal) when behaviour changes: the parser, scrolling,
versions, the folder watch, voice. Run `make test-full` only before a release, and only
when he is away from the Mac.

## Repo hygiene

- Stage named paths; this is a public repo (`dan-slater/mactabs`). Fixtures must be public domain.
- After moving the folder, `make clean` once: SwiftPM's module cache pins the absolute path.
- Commit trailer: as the session's attribution reminder says.
