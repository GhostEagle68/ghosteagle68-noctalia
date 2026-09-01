#!/usr/bin/env bash
# Sync main with upstream, rebuild daily-driver from every topic branch that has not landed
# upstream yet, and build the release binary. Personal tooling; excluded from git.
set -euo pipefail
cd "$(dirname "$0")"

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia"
if [[ -f "$state_dir/settings.toml" ]]; then
  backup_dir="$state_dir/settings-backups"
  mkdir -p "$backup_dir"
  backup="$backup_dir/settings-$(date +%Y%m%d-%H%M%S).toml"
  cp "$state_dir/settings.toml" "$backup"
  # Config migrations are one-way; a binary older than the one that last wrote settings.toml
  # silently drops keys it does not recognise. Keep the last 20 snapshots to recover from that.
  echo "== backed up settings.toml -> ${backup##*/} =="
  ls -1t "$backup_dir"/settings-*.toml | tail -n +21 | xargs -r rm --
fi

git fetch upstream --quiet

echo "== syncing main with upstream =="
git checkout --quiet main
git rebase --quiet upstream/main

topics=()
while read -r branch; do
  if git merge-base --is-ancestor "$branch" upstream/main; then
    echo "   retired (already upstream): $branch"
    continue
  fi
  topics+=("$branch")
done < <(git for-each-ref --format='%(refname:short)' 'refs/heads/feat/*' 'refs/heads/fix/*')

echo "== rebuilding daily-driver from: ${topics[*]:-<nothing>} =="
git branch -D daily-driver >/dev/null 2>&1 || true
git checkout --quiet -b daily-driver main
for branch in "${topics[@]}"; do
  echo "   merging $branch"
  if ! git merge --no-edit --quiet "$branch"; then
    if [[ -z "$(git diff --name-only --diff-filter=U)" ]]; then
      echo "   (rerere auto-resolved conflicts, committing)"
      git commit --no-edit --quiet
    else
      echo "   CONFLICT in $branch — rerere couldn't fully resolve it, fix manually" >&2
      exit 1
    fi
  fi
done

echo "== building release =="
just configure release
if ! just build release; then
  echo >&2
  echo "   BUILD FAILED — daily-driver is at $(git rev-parse --short HEAD) but has no binary." >&2
  echo "   Do NOT restart noctalia: 'noctalia' would fall through PATH to the stock /usr/bin" >&2
  echo "   build, whose older config migrations silently drop settings." >&2
  echo "   Fix the build, or demote the offending branch to wip/* and re-run." >&2
  exit 1
fi

echo "== done: daily-driver at $(git rev-parse --short HEAD) =="
echo "   restart noctalia to pick it up:  nrestart"
