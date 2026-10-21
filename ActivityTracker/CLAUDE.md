# ActivityTracker — rules for working on this project

- Documentation lives in `docs/` and is written in Russian (the owner reads it).
- **Every change must be logged** in `docs/02 - Журнал разработки.md`: add or extend the entry for the current iteration with
  what was requested, what was done and how, bugs hit and how they were found/fixed, CI run links and commit hashes.
  Record new design decisions in `docs/03 - Решения.md` (append rows; strike through superseded ones, never delete).
  Keep `docs/01 - Архитектура.md` and `docs/04 - Как сделать.md` in sync with the code.
- There is no macOS toolchain in the cloud container: every build and test runs in GitHub Actions
  (`.github/workflows/activity-tracker.yml`, `macos-15`). Push, watch the run, fix until green. A green push to `main` or
  `claude/*` publishes a release that installed apps pick up automatically — so never push something that has not been
  reviewed carefully.
- `Sources/ActivityCore` must stay free of AppKit/SwiftUI so it remains unit-testable; put logic there and test it.
- Keep the app light: no polling faster than the 5 s tracker tick, no work while windows are hidden.
- Data never leaves the Mac. The only network access is the update check against GitHub Releases.
