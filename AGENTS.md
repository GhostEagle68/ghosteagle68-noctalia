# Local agent instructions

This file is local to this fork (listed in `.git/info/exclude`; never commit it). Read it before taking action.

## What this repo is

Fork of `noctalia-dev/noctalia`: a native Wayland desktop shell in C++23 (Meson + Ninja). **No Qt/QML** — custom retained scene graph (`src/render/scene/`, `src/ui/`), hand-rolled Wayland client, GLES2 rendering, sdbus-c++ for D-Bus, Luau for plugins.

## Fork workflow (details in WORKFLOW.md)

- `main` mirrors `upstream/main` exactly — never commit to it. PRs are opened from topic branches against upstream.
- Every change (`feat/*`, `fix/*`, `refactor/*`, …) gets its own topic branch, one logical change each, always cut from freshly rebased `main` (= upstream/main): `./topic.sh feat/my-change`. Never reuse or stack topic branches.
- `daily-driver` is a disposable integration branch (`main` + every unlanded topic, merged). Rebuilt from scratch by `./sync.sh`; once a topic is merged into it, stop rebasing it.
- `./sync.sh` also retires topics already landed upstream (delete them afterwards) and backs up settings before running a new build.
- Runs without installing: `/usr/local/bin/noctalia` symlinks to `build-release/noctalia` (setup in WORKFLOW.md).
- `WORKFLOW.md`, `dev.sh`, `topic.sh`, `sync.sh`, `install-daily-driver.sh`, `HANDOFF-*.md`, `PR-BODY-*.md` and this file are git-excluded personal files — never include them in commits or PRs.
- PR descriptions must follow [upstream's `.github/PULL_REQUEST_TEMPLATE.md`](https://github.com/noctalia-dev/noctalia/blob/main/.github/PULL_REQUEST_TEMPLATE.md) (Summary, Motivation, Type of Change, Related Issue, Testing, Manual Coverage, Screenshots/Videos if UI-related, Checklist, Additional Notes).

## Collaboration preference

AI acts as reviewer and guide — not the code author. The user writes code edits and creates commits manually. Provide guidance with precise WHERE and WHY:
- WHERE: full path from repo root plus line numbers, and quote the existing code being changed (enough surrounding lines to locate it uniquely) before showing what to replace it with.
- WHY: rationale for the change, including why over alternatives considered.
Only edit files, commit, or open PRs when explicitly authorized. The user opens PRs themselves — AI should not run `gh pr create`. Keep steps granular — one small commit per step. Never dispatch subagents to write code.

When the user says "done" after a step: review the code they wrote, run the automated checks (`just build`, `just test`, `just lint`/`format` as applicable — anything not requiring manual verification), report findings, and generate a commit message for the step. The user creates the commit.

Before guessing, research first (search the codebase, docs, upstream issues) or ask clarifying questions — guessing does nothing. If trial and error is genuinely needed (e.g. build/test cycles), be deliberate: form a hypothesis, test it, and learn from the result rather than flailing.

## Build & test

- `just configure [debug|release|asan]` — also symlinks root `compile_commands.json` for clangd/clang-tidy.
- `just build [mode]` builds only the shell binary; `just test [mode]` runs unit tests (auto-enables `-Dtests=enabled` for release/asan).
- Single test: `meson test -C build-debug <name>`.
- Registration traps (silently ignored otherwise):
  - New source file must be added to `_noctalia_sources` in the root `meson.build`.
  - New test needs both `tests/<name>_test.cpp` and `<name>` in `_cpp_test_names` in `meson.build`; tests link `noctalia_core_dep`.
- Special tests: `upower_charge_limit_integration` runs under `dbus-run-session`; `config_validate_cli` drives the installed binary with fixture env dirs from `tests/config_validate/`.
- `just format` before committing (clang-format; lefthook pre-commit re-runs it — install with `lefthook install`). `.clang-format` / `.clang-tidy` are committed; do not override locally.
- `just lint` = clang-tidy over `src/` with `-warnings-as-errors=*`; `just fix` = tidy autofix + format.

## Conventions

- Keep code simple and easy to maintain: minimal abstractions, no speculative generality, no "AI fluff" (redundant comments, defensive boilerplate, over-engineering). Stay within the scope of the task — no drive-by refactors or unrequested extras.
- Code style, naming table, and project layout: [CONTRIBUTING.md](CONTRIBUTING.md) is authoritative. Gotcha: D-Bus wire-protocol string literals stay snake_case even though C++ identifiers are camelCase.
- Target compiles with `-Wall -Wextra -Wpedantic -Wconversion -Wshadow` — conversion warnings are errors-in-practice.
- Vendored `third_party/` (fzy, luau, material_color_utilities, wuffs) compiles with warnings off; don't restyle it.
- Wayland protocol XMLs live in `protocols/`; headers are generated at build time by `wayland-scanner` (the layer-shell header gets `namespace` renamed to `name_space`).
- Commits match upstream style: `type(scope): imperative summary` with scope = domain directory (e.g. `feat(audio): …`, `fix(pipewire): …`).
- Translations: only add/update English strings in `assets/translations/en.json`; never touch other locales in feature PRs. After key changes run `python3 tools/i18n-check.py`.

## Debugging

- Runtime debug D-Bus service `dev.noctalia.Debug`: toggle verbose logs via `gdbus call --session --dest dev.noctalia.Debug …` (exact commands in CONTRIBUTING.md).
- `./dev.sh` rebuilds debug and relaunches with `NOCTALIA_LOG_LEVEL=debug`, logging to `/tmp/noctalia.log`.

## Docs sync

User-facing changes keep `README.md`, `BUILDING.md`, `CONTRIBUTING.md`, and `example.toml` accurate; the full config reference lives at docs.noctalia.dev. Version is set in `meson.build` `project(... version: ...)`.
