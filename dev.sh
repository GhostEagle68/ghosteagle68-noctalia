#!/usr/bin/env bash
# Build the debug binary and run it in place of the current shell, with debug logging on.
# No sudo, no install. Personal tooling; excluded from git.
set -euo pipefail
cd "$(dirname "$0")"

just build
pkill noctalia || true
sleep 1
setsid nohup env NOCTALIA_LOG_LEVEL=debug ./build-debug/noctalia >/tmp/noctalia.log 2>&1 </dev/null &

echo "== debug build running from $(git rev-parse --abbrev-ref HEAD) =="
echo "   log:  tail -f /tmp/noctalia.log"
echo "   back: nrestart"
