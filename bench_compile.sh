#!/usr/bin/env bash
# Times cold rebuilds of the noctalia_core static lib in the given Meson build dir.
# Usage: ./bench_compile.sh <builddir> [reps=3]
# The builddir must have been fully built at least once, so third_party objects
# and generated protocol headers are warm and only the ~570 core TUs are timed.
# Prints per-run wall time + peak process RSS (largest compiler), then the median wall time.
set -euo pipefail
builddir="${1:?usage: bench_compile.sh <builddir> [reps]}"
reps="${2:-3}"

times=()
for i in $(seq 1 "$reps"); do
  # Force every object to recompile without a full reconfigure (keeps the
  # ninja graph and any generated protocol headers intact).
  rm -rf "$builddir/libnoctalia_core.a.p" "$builddir/libnoctalia_core.a"
  line=$(python3 - ninja -C "$builddir" libnoctalia_core.a <<'PY'
import resource
import subprocess
import sys
import time

t0 = time.monotonic()
proc = subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL)
ru = resource.getrusage(resource.RUSAGE_CHILDREN)
print(f"wall={time.monotonic() - t0:.1f}s peak_rss={ru.ru_maxrss / 1024:.0f}MiB")
sys.exit(proc.returncode)
PY
  )
  echo "run ${i}/${reps}: ${line}"
  times+=("$(echo "$line" | grep -oE 'wall=[0-9.]+' | cut -d= -f2)")
done

median=$(printf '%s\n' "${times[@]}" | sort -n | awk '{a[NR]=$1} END {print (NR % 2) ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2}')
echo "median cold build of libnoctalia_core.a over ${reps} runs: ${median}s"
