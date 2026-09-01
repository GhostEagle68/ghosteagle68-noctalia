#!/usr/bin/env bash
# Rebuilds and installs whatever branch is currently checked out.
# Run from anywhere; cd's into the repo itself.
set -euo pipefail
cd "$(dirname "$0")"

echo "== branch: $(git rev-parse --abbrev-ref HEAD) =="
just build release
just test release
sudo just install release

echo "== restarting noctalia =="
pkill noctalia || true
sleep 0.5
nohup noctalia >/tmp/noctalia.log 2>&1 &
disown
echo "== running: $(which noctalia) =="
