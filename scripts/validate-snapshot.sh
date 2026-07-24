#!/bin/sh
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)/ExileRoute/Resources"
jq -e '.schemaVersion == 1 and (.commit | length == 40)' "$root/snapshot-manifest.json" >/dev/null
jq empty "$root/Data/areas.json"
jq empty "$root/Data/quests.json"
jq -e 'length > 100' "$root/Data/gems.json" >/dev/null
jq -e 'length == 7' "$root/Data/characters.json" >/dev/null
jq empty "$root/Data/vaal-gem-lookup.json"
jq empty "$root/Data/awakened-gem-lookup.json"
for act in 1 2 3 4 5 6 7 8 9 10; do
  test -s "$root/Routes/act-$act.txt"
  grep -q "#section Act $act" "$root/Routes/act-$act.txt"
done
echo "Snapshot is valid"
