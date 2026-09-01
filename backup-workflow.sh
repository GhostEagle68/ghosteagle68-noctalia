#!/usr/bin/env bash
# Snapshot the git-excluded personal workflow files to the personal/workflow branch on origin.
# Uses a throwaway index, so the working tree and the checked-out branches are untouched.
set -euo pipefail
cd "$(dirname "$0")"

branch=personal/workflow
files=(WORKFLOW.md AGENTS.md dev.sh sync.sh topic.sh install-daily-driver.sh
  bench_compile.sh backup-workflow.sh)

# Transient notes: include when present, skip silently when not.
shopt -s nullglob
for f in HANDOFF-*.md PR-BODY-*.md; do files+=("$f"); done
shopt -u nullglob

index=$(mktemp)
trap 'rm -f "$index"' EXIT
export GIT_INDEX_FILE="$index"

if git rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
  git read-tree "$branch"
else
  git read-tree --empty
fi

for f in "${files[@]}"; do
  if [[ -f "$f" ]]; then
    # -f: these files are excluded via .git/info/exclude on purpose.
    git add -f -- "$f"
  else
    echo "   skipping missing $f" >&2
  fi
done
# Carry the exclude list itself, so a fresh clone knows what to re-exclude.
exclude_blob=$(git hash-object -w .git/info/exclude)
git update-index --add --cacheinfo "100644,${exclude_blob},git-info-exclude"

tree=$(git write-tree)
if git rev-parse -q --verify "refs/heads/$branch" >/dev/null &&
  [[ "$(git rev-parse "$tree")" == "$(git rev-parse "$branch^{tree}")" ]]; then
  echo "== nothing changed since the last snapshot"
  exit 0
fi

parent=$(git rev-parse -q --verify "refs/heads/$branch" || true)
commit=$(git commit-tree "$tree" ${parent:+-p "$parent"} -m "workflow snapshot $(date +%Y-%m-%d)")
git update-ref "refs/heads/$branch" "$commit"
git push -u origin "$branch"
echo "== snapshot pushed: $branch ($(git rev-parse --short "$commit"))"
