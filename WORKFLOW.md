# Local dev workflow (personal notes — not part of any PR)

Remotes: `origin` = your fork (GhostEagle68/ghosteagle68-noctalia), `upstream` = noctalia-dev/noctalia.

`WORKFLOW.md`, `sync.sh`, `topic.sh`, `dev.sh` and `install-daily-driver.sh` are listed in
`.git/info/exclude`, so they never show up in a PR.

## Branch roles

- **main** — pure mirror of `upstream/main`. Never commit here directly.
- **topic branches** (`fix/...`, `feat/...`) — one per feature/fix, forked off `main`. These are
  what you open PRs from. Once a topic is merged into `daily-driver`, don't rebase it anymore —
  only add new commits on top.
- **daily-driver** — integration branch you actually run. `main` plus every topic branch not yet
  landed upstream, combined with `git merge`. Disposable: no unique commits, always safe to
  delete and rebuild.

`rerere.enabled` is on, so a merge conflict you resolve once gets reapplied automatically.

## One-time setup: run your build without installing

`/usr/local/bin` comes before `/usr/bin` in `$PATH`, so a symlink there wins over the distro
package (`noctalia` from the CachyOS repo, installed to `/usr/bin`).
Point it at the build tree once and every later rebuild is picked up with no `sudo`.

Per the README, enable native CPU optimizations for a machine-local release build:

```sh
just configure release
meson configure build-release -Dnative_optimizations=true
just build release
```

Then drop any previously installed copy and symlink instead:

```sh
sudo just uninstall release
sudo ln -sfn "$PWD/build-release/noctalia" /usr/local/bin/noctalia
```

Assets resolve from the source tree automatically (`assets/` one level above the executable), so
they stay current too.

Back to the stock distro build at any time:

```sh
sudo rm /usr/local/bin/noctalia
```

Check what is actually running with `nver` (fish function).

## Build caching (ccache)

ccache is installed system-wide; Meson picks it up from `$PATH` whenever a builddir is first
configured, so new builddirs get it automatically. Clean rebuilds drop from ~163 s to ~45 s
(what remains is the LTO link):

```sh
./bench_compile.sh build-release 3   # per-run wall time + peak compiler RSS + median
```

- Cache lives in `~/.cache/ccache`, shared with other C/C++ projects, 5 GiB cap — raise
  `max_size` in `~/.config/ccache/ccache.conf` if evictions appear.
- Builddirs bake `ccache` into their ninja rules: if ccache is ever uninstalled, builds fail
  with "ccache not found" until you `just clean <mode> && just configure <mode>`.
- Editing a widely-included header rebuilds dependents as cache misses (no speedup the first
  time); the win is clean rebuilds, branch switching, and `sync.sh`.

## Daily use

```sh
./sync.sh                    # fetch upstream, rebase main, rebuild daily-driver, build release
nrestart
```

`sync.sh` derives the topic list itself: any local `feat/*` or `fix/*` branch that is not yet an
ancestor of `upstream/main`. Branches that landed upstream are reported and dropped — delete them
afterwards with `git branch -D <name>`.

If a merge conflicts, `sync.sh` stops mid-merge. Resolve, `git add`, `git commit --no-edit`, then
re-run it.

## Never restart into the stock build

Config migrations are one-way. A binary older than the one that last wrote `settings.toml` does not
recognise renamed or moved keys, drops them, and saves the result — settings gone.

That is why you restart with `nrestart` (fish function, alongside `nver`) rather than a bare
`noctalia`: it resolves an absolute path and refuses to start if the binary is missing. A bare
`noctalia` after a failed or mid-flight build falls through `$PATH` to the stock distro
`/usr/bin/noctalia`, which is usually older than `daily-driver`.

```sh
nrestart          # daily driver (/usr/local/bin/noctalia -> build-release)
nrestart -d       # debug build, with debug logging
```

`sync.sh` snapshots `settings.toml` to `~/.local/state/noctalia/settings-backups/` on every run and
keeps the last 20. To recover:

```sh
ls -1t ~/.local/state/noctalia/settings-backups/
cp ~/.local/state/noctalia/settings-backups/settings-YYYYMMDD-HHMMSS.toml \
   ~/.local/state/noctalia/settings.toml
```

`sync.sh` also aborts if the release build fails, rather than leaving `daily-driver` without a
binary for the next restart to trip over.

Check with `nver` after any restart — it reports the binary actually running.

## Start a feature or fix

```sh
./topic.sh feat/whatever     # syncs main, then branches off it
# ...work...
just format && just build && just test
git add -u && git commit -m "feat(scope): what changed"
```

Commit style follows upstream: `type(scope): lowercase summary`, subject line only, no body
(except `Closes: #123`).

## Iterate on a change

```sh
./dev.sh                     # debug build, restarts noctalia from build-debug, debug logging on
tail -f /tmp/noctalia.log
```

The debug build shows a red `debug` pill in the bar, so you always know which binary is live.
`./dev.sh` runs whatever branch is checked out — handy for testing a topic in isolation before it
goes anywhere near `daily-driver`.

Runtime log level without a restart: `noctalia msg log-level-set debug` (resets to `info` on
restart).

## Open a PR

```sh
git push -u origin feat/whatever
gh pr create --repo noctalia-dev/noctalia --base main --head GhostEagle68:feat/whatever --draft
```

Rebase the branch onto current `main` *before* the first push. After it is pushed, add commits on
top instead — rebasing means force-pushing and invalidates review comments.

## When a PR is merged upstream

Just run `./sync.sh`. It notices the branch is now an ancestor of `upstream/main`, drops it from
`daily-driver`, and prints the branch name so you can retire it:

```sh
git branch -D feat/whatever
git push origin --delete feat/whatever
```

## Git tooling

`delta` is the global pager for `git diff/log/show` (line numbers on, `n`/`N` jump between
diff hunks; flip `delta.dark` in `~/.gitconfig` if syntax colors look wrong for a light
terminal). `difftastic` shows structural diffs, `git-absorb` folds fixes into the right
commit before the pre-push rebase, `lazygit` is the TUI for the branch dance:

```sh
git difft                      # structural diff (difftastic via difftool)
git absorb                     # uncommitted fixes -> fixup! commits on the right parents
lazygit                        # TUI overview
```

## Backing up these files

Everything listed in `.git/info/exclude` (this file, the scripts, HANDOFF/PR-BODY notes)
exists only on this machine. `./backup-workflow.sh` snapshots them to the
`personal/workflow` branch on `origin` — run it after changing any of them:

```sh
./backup-workflow.sh
```

## Escape hatches

```sh
sudo rm /usr/local/bin/noctalia    # back to the stock distro build immediately
git checkout daily-driver          # sync.sh leaves you here
git merge --abort                  # bail out of a conflicted sync
sudo just uninstall release        # remove files installed by `just install release`
```
