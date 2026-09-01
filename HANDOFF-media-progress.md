# Handoff — media widget playback progress fill

Working doc for an AI assistant picking up this task mid-stream. Not tracked by git
(listed in `.git/info/exclude`); do not commit it into the PR.

Written 2026-08-05 by Claude Opus 5, mid-step-3.

---

## 1. The task

Add an **opt-in background fill** behind the bar's media widget that grows left→right as the
current track plays, so the pill itself reads as a progress indicator.

Repo: `/home/jacob/Projects/noctalia` (fork of `noctalia-dev/noctalia`).
Branch: `feat/media-progress-fill`, cut off freshly-rebased `upstream/main`.

**No upstream issue or PR covers this.** Searched: #2744 is a control-center scrub-*thumb* bug
(closed, unrelated); #3630 migrated this widget to typed widget definitions (merged, and is the
schema style used here); #3306 / #3536 / #3317 / #3522 are recent merged media-widget options and
are good precedent for the size and shape of this PR.

## 2. Critical context about the codebase

**This is a C++23 native Wayland shell, NOT QML/Quickshell.** `find . -name "*.qml"` returns zero
files. It has a custom retained-mode scene graph in `src/render/scene` + `src/ui`, meson build,
~550 `.cpp` files. MPRIS is a hand-rolled sdbus client, not `Quickshell.Services.Mpris`. An earlier
exploration pass in this session assumed QML and was wrong — don't repeat that.

Mental model: a retained tree of `Node`s you mutate in a layout pass. Not immediate-mode, not
reactive.

Naming (CONTRIBUTING.md:106-119): files/dirs `snake_case`, types `PascalCase`, functions
`camelCase`, **private members `m_camelCase`**, enum values `SCREAMING_SNAKE_CASE`.

## 2b. Build and dev environment (from README.md / CONTRIBUTING.md)

Requires [`just`](https://github.com/casey/just) and [meson](https://mesonbuild.com/).

```sh
just configure          # configure debug build in build-debug/
just build              # build the noctalia executable (debug)
just run                # run the local debug build
just test               # unit tests — NOT built by `just build`, must be run explicitly
just format             # clang-format
just lint               # clang-tidy
just fix                # clang-tidy with fixes applied
just rebuild            # clean + build
```

All recipes take an optional mode argument (`just build release`). Release install:
`just configure release && just build release && sudo just install release`. `install`/`uninstall`
require an explicit mode so debug builds aren't installed by accident.

Notes that matter here:
- **Unit tests are not compiled by `just build`.** Production sources compile once into an internal
  static library shared by the shell and test executables, so `just test` is a separate step.
- `just configure` creates a root `compile_commands.json` symlink for clangd. If clangd
  autocomplete misbehaves, re-run it.
- `lefthook install` installs the pre-commit hook that runs `just format` and refreshes the git
  index. It's already active in this checkout.
- Noctalia needs the shipped `assets/` tree at runtime; the binary alone is not enough.
- Debug logging is over D-Bus at runtime, not a build flag:
  ```sh
  gdbus call --session --dest dev.noctalia.Debug --object-path /dev/noctalia/Debug \
    --method dev.noctalia.Debug.SetVerboseLogs true
  ```
  See CONTRIBUTING.md §Debugging for the full set (`GetVerboseLogs`, `EmitInternalNotification`).
- CONTRIBUTING.md also has: Design Principles, Stack, Runtime Assets (asset lookup order), Code
  Style, Naming Conventions, Translations, Project Layout, Debugging.

### Documentation: nothing to update in-repo for this feature

Checked deliberately — **no docs change belongs in this PR**:
- `README.md` (348 lines) is install/dependencies/build only. It documents no widget settings.
- `example.toml` lists widget *names* per bar section (`end = ["media", "tray", ...]`), not
  per-widget settings.
- No existing media widget setting (`hide_album_art`, `album_art_only`, `title_scroll`,
  `hide_when_no_media`, `art_size`, …) appears in any `.md` or `.toml` in the repo.

The user-facing config reference lives on the **external site docs.noctalia.dev/v5/**, which is a
separate workflow from this repo. Documenting `show_progress` there is a reasonable follow-up but is
out of scope for this branch. Translations are the one "docs-like" artifact that *is* in scope —
`assets/translations/en.json`, step 6.

## 3. Working agreement with the user

The user is learning C++ (background in Rust) and is doing this deliberately as practice.

- **The user writes ALL the code.** Never edit source files for them, and never dispatch an
  implementer subagent to do it. This is a firmly held, repeatedly restated preference.
- **The user makes ALL the commits.** Suggest the message; they run `git commit`.
- Guidance style, per explicit correction: **give the exact code block to write**, anchored to
  surrounding lines, **top to bottom**. Do not describe it in prose and make them assemble the
  syntax. Explain briefly — "explain but not like a professor."
- **On "done": run `just build` FIRST** and lead with the compiler's actual error. Do not review by
  eye and describe a suspected problem first.
- **No open decisions inside a step.** State the recommended choice as the instruction; the
  alternative gets at most one line.
- **Re-check twice before claiming a file is unchanged.** The user's editor saves can lag the chat
  message by seconds. One disagreement in this session was pure save lag, nothing more.
- Commits are conventional with the `media` scope. Upstream's last 400 commits: 135 `fix`, 91
  `feat`, 36 `chore`, **zero `wip`**. `feat(media): ...` is the established form for this widget.
- `lefthook` pre-commit runs `just format`, so clang-format normalization happens at commit time.
  Don't nag about indentation.

## 4. Design decisions already made (do not re-litigate)

| Decision | Choice | Why |
|---|---|---|
| Where the fill lives | **Widget-owned node** inside the media widget's own root | See below |
| Direction | **Elapsed**, grows left→right | User's choice; matches `ProgressBar`'s default `Horizontal` |
| Update mechanism | **Adaptive one-shot timer**, re-armed from its own callback | See §6 |
| Default | **Off** — new `show_progress` boolean, opt-in | |
| Art-only / vertical bar | **Fill hidden** | `ProgressBar` draws rects only; it can't ring a circular disc |
| Reading track length | Call `m_mpris->activePlayer()` directly in `doLayout` | It's a cached projection, not a D-Bus round trip |

### Why widget-owned and not the bar capsule

The rounded pill behind a bar widget is **not** drawn by the widget. The bar owns it:
`addSingleCapsule` (`src/shell/bar/bar.cpp:2499-2541`) wraps the widget root in a clipping shell and
prepends a `ui::box` with `zIndex(-1)`; geometry is finalized in `finalizeCapsules`
(`bar.cpp:901-1054`). Two reasons not to write into it:

1. **Capsules merge.** Adjacent widgets sharing a group ID collapse into one `BarCapsuleRun`, so
   "the capsule" may span several widgets — a fill sized to the shell would bleed over neighbours.
2. **Capsules can be disabled** (`addPlainWidget`, `bar.cpp:2483-2497`), and then there is no pill
   at all — the feature would silently do nothing.

Cost of the widget-owned approach: the fill sits inset by the capsule's padding rather than
flooding the whole pill. The user accepted this tradeoff explicitly.

## 5. Existing primitives being reused

**`ProgressBar`** — `src/ui/controls/progress_bar.h` / `.cpp`. A track rect plus a *full-size* fill
rect revealed through a clip node (see `updateGeometry`, "Anchored fill" branch). That construction
is why the leading end keeps its rounded corner instead of squaring off at low progress.
API: `setTrack`, `setFill`, `setRadius`, `setProgress(0..1)`, `setOrientation`.
Builder: `ui::progressBar(...)`, `src/ui/builders.h:624`; props struct `ProgressBarProps` at
`builders.h:583-598`.
Other users to crib from: `sysmon_widget.cpp:258` and `:499`; `osd_overlay.cpp:693-702`.

**MPRIS** — `src/dbus/mpris/mpris_service.h:28-52`. `MprisPlayerInfo` carries `positionUs`,
`lengthUs`, `playbackStatus`, `canSeek`, `trackId`. `MprisService::activePlayer()`
(`mpris_service.cpp:381-392`) returns `std::optional<MprisPlayerInfo>` — a **projected** snapshot:
`projectedPositionUs` (`:642+`) adds wall-clock elapsed since the last authoritative D-Bus sample,
and returns 0 when `Stopped`. So every re-read has already advanced; you never poll D-Bus yourself,
you just need something to make you re-read.

The service's change callback (`application_services.cpp:1407-1417`) fires on metadata/status
changes only, **not** every second — so continuous motion must be self-driven.

**`Timer`** — `src/core/timer_manager.h`. RAII handle: `start(delay, cb)` one-shot,
`startRepeating(interval, cb)`, `stop()`; destructor cancels. Move-only (deleted copy ctor).
Reference usage: `media_tab.cpp:605-615` (control-center's 1s progress poll).

**Non-layout overlay pattern** — `workspaces_widget.cpp:703-713`
(`setParticipatesInLayout(false)`, `setHitTestVisible(false)`).

**Widget options plumbing** — `src/shell/bar/widget_definition.h:398-480`. A `bool` option needs
exactly *one* struct member and *one* `field<>()` entry. The default is read from the struct's
default member initializer (`:416-419`). i18n keys are derived from the config key by replacing
`_` with `-` (`detail::settingTranslationSegment`, `:390-394`). No edits needed to
`widget_settings_registry.cpp`, `bar_widget_editor.cpp`, or any JSON schema — `field<>()` generates
the schema entry, the settings-UI toggle, and the translation lookup.

## 6. The smoothness argument (why a timer, not a frame tick)

The fill only moves in whole pixels. The widget is ~80–220 px wide, so one pixel of travel takes
`lengthSeconds / widthPixels` — about 0.9 s for a 3-minute track in a 200 px widget. A 1 s timer is
therefore *already* roughly pixel-accurate, and `needsFrameTick()`/`onFrameTick()` would redraw ~60×
more often to produce an identical image. Upstream has had CPU complaints about exactly this
(issue #3029).

So derive the interval from geometry:

```
intervalMs ≈ clamp( (lengthUs / 1000) / max(fillWidthPx, 1), 250, 1000 )
```

Use one-shot `Timer::start()` re-armed from inside its own callback so the interval tracks the
current track and widget width. `startRepeating` locks a fixed interval; `sysmon_widget.cpp:698,706`
uses the re-arming one-shot form for the same reason. **Leave `needsFrameTick()`/`onFrameTick()`
alone entirely.**

## 7. Where things stand

Branch `feat/media-progress-fill`, two commits ahead of `upstream/main`:

```
12c3dccbd feat(media): add progress fill node to media widget     (step 2)
e64fbca05 feat(media): add progress bar support to media widget   (step 1)
```

### Step 1 — DONE, committed. `src/shell/bar/widgets/media_widget.h`
- `#include "core/timer_manager.h"` (value member needs the complete type)
- `class ProgressBar;` forward declaration (pointer member only needs the name)
- `bool showProgress = false;` in `struct Options` — **this `false` IS the config default**
- `bool m_showProgress = false;` private member
- `ProgressBar* m_progressBar = nullptr;` — note the name, **not** `m_progress`
- `void syncProgress();` private method declaration
- `Timer m_progressTimer;` declared **last**, after `m_aliveGuard`, so reverse-order destruction
  cancels the timer *before* the state a queued callback might touch

### Step 2 — DONE, committed. `media_widget.cpp`
- `m_showProgress(options.showProgress)` appended to the constructor init list
- A `ui::progressBar({...})` child added to the input area in `create()`, **before** the
  `ui::image` child:

```cpp
  area->addChild(
    ui::progressBar({
      .out = &m_progressBar,
      .fill = colorSpecFromRole(ColorRole::Primary, 0.25F),
      .track = clearColorSpec(),
      .visible = false,
      .participatesInLayout = false,
      .configure =
        [](ProgressBar& bar) {
          bar.setZIndex(-1);
          bar.setHitTestVisible(false);
        }
    })
);
```

Node is built unconditionally and toggled via `setVisible()` in layout, so the pointer is always
valid — same treatment as `m_emptyGlyph`.

### Step 3 — IN PROGRESS. `media_widget.cpp`, `doLayout`

Three edits. **1 is done, 2 is truncated and won't compile, 3 not started.**

**Edit 1 (done)** — null guard extended:
```cpp
  if (rootNode == nullptr || m_art == nullptr || m_label == nullptr || m_emptyGlyph == nullptr || m_progressBar == nullptr) {
```

**Edit 2 (INCOMPLETE)** — currently on disk after the `minLength` const:
```cpp
  const auto progressPlayer = m_mpris != nullptr ? m_mpris->activePlayer() : std::nullopt;
  const bool showProgressFill        // <-- no initializer, no semicolon
```
Should be:
```cpp
  const auto progressPlayer = m_mpris != nullptr ? m_mpris->activePlayer() : std::nullopt;
  const bool showProgressFill =
      m_showProgress && !artOnly && progressPlayer.has_value() && progressPlayer->lengthUs > 0;
```

**Edit 3 (not started)** — insert before `doLayout`'s closing brace, after the whole
`if (artOnly) {...} else {...}` chain so it covers all three `rootNode->setSize` paths:
```cpp
  m_progressBar->setVisible(showProgressFill);
  if (showProgressFill) {
    const float fillWidth = rootNode->width();
    const float fillHeight = rootNode->height();
    m_progressBar->setPosition(0.0F, 0.0F);
    m_progressBar->setSize(fillWidth, fillHeight);
    m_progressBar->setRadius(std::min(fillWidth, fillHeight) * 0.5F);
  }
```

No new includes: `<algorithm>` is already included for `std::min`, and `std::nullopt` is already
used in `syncState`.

Commit when green: `feat(media): size progress fill to media widget bounds`

## 8. Remaining steps

### Step 4 — `media_widget.cpp`: value + timer, in `syncProgress()` called from `syncState`

**The trap:** `syncState` early-returns when text/art/status are all unchanged (the
`if (!textChanged && !artChanged && !playbackChanged && !artAwaitingDecode) return;` guard). The
progress update **must run before that guard** or it gets skipped on exactly the frames that matter.
This is the #1 cause of "why isn't it moving?".

- Read `positionUs` / `lengthUs` / `playbackStatus` from `m_mpris->activePlayer()`.
- Guard `lengthUs > 0` before dividing — live streams report 0.
- `static_cast<float>(positionUs) / static_cast<float>(lengthUs)` — both are `int64_t`; integer
  division would floor to 0 or 1. `ProgressBar::setProgress` clamps to [0,1] internally.
- Call `requestRedraw()` when the value changed (repaint). `requestUpdate()` re-runs layout and
  isn't needed — geometry doesn't change.
- Timer lifecycle: arm only when `m_showProgress` **and** status is `"Playing"` **and**
  `lengthUs > 0`; `stop()` otherwise. A paused track must not keep the bar awake.
  Callback body: re-read → `setProgress` → `requestRedraw` → re-arm with a freshly computed interval.

**Do not** copy the anti-jitter machinery from `media_tab.cpp:815-880` (`m_progressSettleUntil`,
`m_positionTrackSignature`). That exists because the control-center slider is *interactive* and has
to survive a user scrub racing a D-Bus update. A read-only fill has no such race.

Commit: `feat(media): drive progress fill from mpris position`

### Step 5 — `media_widget_definition.cpp`: expose the setting

One entry near the existing `hide_when_no_media` field:
```cpp
field<&Options::showProgress>({
    .key = "show_progress",
    .presentation = settings::WidgetSettingPresentation{.horizontalBarOnly = true},
}),
```
`.horizontalBarOnly = true` follows from the step-3 decision to hide the fill on vertical bars.
See the existing `hide_album_art` entry for the `WidgetSettingPresentation` shape.

Commit: `feat(media): add show_progress widget setting`

### Step 6 — `assets/translations/en.json`

Add, **alphabetically sorted**, under `settings.widgets.settings`:
```json
"show-progress": {
  "description": "...",
  "label": "Show Playback Progress"
},
```
Key = the config key with `_`→`-`. **Edit `en.json` only** — the other ~30 locales are machine-synced
via `tools/i18n-pull.sh`. No `meson.build` change (no new source files).

Commit: `feat(media): add show-progress translation strings`

### Step 7 — verify, tune, squash

Squash steps 1–6 into `feat(media): show playback progress as a background fill`.

## 9. Verification

```
just build                      # debug build
just test                       # widget_definition_test / config_schema_roundtrip_test cover the option plumbing
just format                     # clang-format (also runs via lefthook pre-commit)
python3 tools/i18n-check.py     # translation key validation
```

Then `just run` and check by eye:

1. Enable **Show Playback Progress** in Settings → Bar → Widgets. A missing i18n key renders as the
   raw key — that's the label check.
2. Play something; the fill advances and the title stays legible over it. Tune the 0.25 alpha here.
3. **Pause** — fill freezes *and* the timer stops. Confirm idle CPU returns to baseline in `htop`.
   This is the regression issue #3029 was about.
4. **Seek** from another player or the control center — the bar fill jumps to match.
5. **Live stream / unknown length** (`lengthUs == 0`) — hidden, not full, not NaN.
6. Option **off** — no fill, no timer.
7. **Vertical bar** — fill hidden, art-only rendering unchanged.
8. Widget **capsule disabled** in settings — fill still renders sensibly standalone.

## 10. Gotchas that cost time in this session

- **Builder nesting.** `ui::foo({...})` is struct-initialization, not named arguments. Three layers:
  `addChild(` → `ui::foo({` → the `.field =` list; the tail is always `})` then `);`. Four passes
  were lost to this. When a builder call doesn't end that way, the nesting is wrong.
- **Designated initializers must appear in declaration order** (C++20 requirement, stricter than
  Rust's struct literals). Skipping fields is fine; reordering is a compile error.
- **The error lands downstream.** An unclosed paren in one builder call reports at the *next*
  statement's `);`, often 10+ lines later.
- **Lambda bodies need statements**, each ending in `;`, and member calls need the parameter as
  receiver (`bar.setZIndex(-1)`, not `setZIndex(-1)`). A comma-separated version compiles as a
  comma-operator expression and "works" while reading as a bug.
- **`m_` prefix is for private members only** — `Options` fields are bare camelCase.
- **`ProgressBar` is the type, `ui::progressBar` is the builder function.** Case matters.
- **Editor save lag.** The user's writes can land seconds after they say "done". Re-stat before
  asserting a file is unchanged; check `stat -c '%y'` rather than trusting one read.
