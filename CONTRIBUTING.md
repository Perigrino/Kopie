# Contributing to Kopie

Thanks for wanting to contribute! Kopie is a small, focused app — a menu-bar
clipboard manager that runs entirely on your Mac. Contributions that keep it
fast, simple, and local-only are welcome.

## Code of Conduct

Be respectful and constructive. Harassment, personal attacks, and unrelated
criticism are not tolerated. By participating you agree to uphold a welcoming
environment for everyone.

## Ways to contribute

- **Report bugs** — open an issue with steps to reproduce, what you expected,
  and what happened. Include the macOS version.
- **Suggest features** — open an issue describing the problem you're trying to
  solve. Kopie favors small, well-scoped changes over big redesigns.
- **Submit code** — follow the workflow below.

## Project overview

- **Stack**: Swift + SwiftUI + AppKit, a SwiftPM package, no third-party deps.
- **Layout**: `Sources/Kopie/` (app/UI), `Sources/KopieCore/` (engine, no AppKit
  dependencies where possible), `Tests/KopieCoreTests/` (core unit tests).
- **Design constraints** (see `docs/superpowers/specs/`):
  - Local-only. Kopie never uploads or shares clipboard content.
  - Menu-bar first, keyboard-first, fast.
  - The core (`KopieCore`) should stay testable without a window session.

## Development setup

```bash
swift test        # core engine unit tests
npm run dev       # debug build + assemble + open Kopie.app
npm run build     # release build (dist/Kopie.app)
npm run package   # release build + dist/Kopie.dmg
bash scripts/acceptance.sh   # headless full workflow
```

## Pull request workflow

1. Fork the repo and create a branch:
   `git checkout -b feature/my-change`
2. Make your change. Keep it focused — one logical change per PR.
3. Add or update tests in `Tests/KopieCoreTests/` for any core change.
4. Run the full suite: `swift test` and `bash scripts/acceptance.sh`.
5. Commit with a clear message following Conventional Commits
   (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`).
6. Open a PR describing what you changed and why.

### Before you submit

- Code compiles warning-free.
- Tests pass: `swift test`.
- New core behavior has test coverage.
- No secrets, local paths, or machine-specific state are committed.
- The `.freebuff/*.db*` runtime database files are never committed.

## Code style

- Follow the style of surrounding code (spacing, naming, structure).
- No unnecessary comments; prefer expressive names.
- Keep `KopieCore` free of UI dependencies so it stays unit-testable.
- Respect the Reduce Motion accessibility setting for any animation work.

## Questions?

Open a discussion or issue and a maintainer will respond.

Thanks again for helping make Kopie better.