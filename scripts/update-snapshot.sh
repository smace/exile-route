#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
snapshot_root="$repo_root/ExileRoute/Resources"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

commit="${1:-$(curl -fsSL 'https://api.github.com/repos/HeartofPhos/exile-leveling/commits/main' | jq -r '.sha')}"
test -n "$commit"
test "$commit" != "null"

mkdir -p "$staging/Routes" "$staging/Data"
for act in {1..10}; do
  curl -fsSL "https://raw.githubusercontent.com/HeartofPhos/exile-leveling/$commit/common/data/routes/act-$act.txt" \
    -o "$staging/Routes/act-$act.txt"
done

for file in areas quests; do
  curl -fsSL "https://raw.githubusercontent.com/HeartofPhos/exile-leveling/$commit/common/data/json/$file.json" \
    -o "$staging/Data/$file.json"
  jq empty "$staging/Data/$file.json"
done

for act in {1..10}; do
  grep -q "#section Act $act" "$staging/Routes/act-$act.txt"
done

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --arg repository "HeartofPhos/exile-leveling" \
  --arg commit "$commit" \
  --arg generatedAt "$generated_at" \
  '{schemaVersion: 1, repository: $repository, commit: $commit, generatedAt: $generatedAt}' \
  > "$staging/snapshot-manifest.json"

mkdir -p "$snapshot_root/Routes" "$snapshot_root/Data"
cp "$staging"/Routes/* "$snapshot_root/Routes/"
cp "$staging"/Data/* "$snapshot_root/Data/"
cp "$staging/snapshot-manifest.json" "$snapshot_root/snapshot-manifest.json"
echo "Installed Exile Leveling snapshot $commit"

