#!/usr/bin/env bash
# For a gem + installed version + cutoff, fetch versions from rubygems.org and emit
# a single delta line if the highest non-prerelease version was released after cutoff
# AND differs from installed. Silent otherwise.
#
# Output: "<name>: <installed> → <latest> (<YYYY-MM-DD>)"

fetch_ruby_delta() {
  local name="$1"
  local installed="$2"
  local cutoff="$3"
  local api="https://rubygems.org/api/v1/versions/${name}.json"

  local raw
  raw=$(curl -fsSL --max-time 10 "$api" 2>/dev/null) || return 0

  printf '%s' "$raw" | jq -r \
    --arg cutoff "$cutoff" \
    --arg installed "$installed" \
    --arg name "$name" '
      [ .[] | select(.prerelease == false) ]
      | sort_by([.number | split(".") | map(tonumber? // 0)])
      | last
      | select(. != null)
      | select(.created_at > ($cutoff + "T00:00:00"))
      | select(.number != $installed)
      | "\($name): \($installed) → \(.number) (\(.created_at[0:10]))"
    '
}
