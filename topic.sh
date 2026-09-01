#!/usr/bin/env bash
# Start a topic branch off a freshly synced main. Personal tooling; excluded from git.
set -euo pipefail
cd "$(dirname "$0")"

[[ $# -eq 1 ]] || {
  echo "usage: ${0##*/} feat/thing" >&2
  exit 1
}

git fetch upstream --quiet
git checkout --quiet main
git rebase --quiet upstream/main
git checkout -b "$1" main
echo "== $1 created off main ($(git rev-parse --short main)) =="
