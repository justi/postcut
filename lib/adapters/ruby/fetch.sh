#!/usr/bin/env bash
# Ruby adapter — HTTP path. Three router-named functions, plus the
# orchestrator fetch_ruby_delta which emits the per-gem block.
#
# Block format emitted by fetch_ruby_delta:
#   <name>: <pre_cutoff_latest> (last seen) → <current_latest> (current, <YYYY-MM-DD>)
#     <ver>: <bullet1>; <bullet2>; <bullet3>      [from /releases or CHANGELOG]
#     <ver>: GHSA-XXX [severity] CVE-XXXX-NNNN: summary
#
# Silent (no header) if nothing was released after cutoff.

# ruby_http_metadata <pkg>
# Stdout: best-effort source URI (github / homepage), or empty.
ruby_http_metadata() {
  local pkg="$1"
  [ -z "$pkg" ] && return 0

  local raw
  raw=""
  raw=$(curl -fsSL --max-time 10 "https://rubygems.org/api/v1/gems/${pkg}.json" 2>/dev/null) || raw=""
  [ -z "$raw" ] && return 0

  printf '%s' "$raw" | jq -r '
    .source_code_uri // .metadata.source_code_uri // .homepage_uri // ""
  ' 2>/dev/null
}

# ruby_http_notes <pkg> <versions_csv>
# Tries GitHub Releases API first, falls back to raw CHANGELOG.md fetch.
# Empty if no GitHub repo discoverable.
ruby_http_notes() {
  local pkg="$1"
  local versions_csv="$2"
  [ -z "$pkg" ] && return 0
  [ -z "$versions_csv" ] && return 0

  local repo_uri
  repo_uri=""
  repo_uri=$(ruby_http_metadata "$pkg") || repo_uri=""
  [ -z "$repo_uri" ] && return 0

  local gh_repo
  gh_repo=$(parse_github_repo_from_url "$repo_uri")
  [ -z "$gh_repo" ] && return 0

  local notes
  notes=""
  notes=$(fetch_github_release_notes "$gh_repo" "$versions_csv") || notes=""
  if [ -n "$notes" ]; then
    printf '%s\n' "$notes"
    return 0
  fi

  fetch_changelog_md "$gh_repo" "$versions_csv"
}

# ruby_http_advisories <pkg> <versions_csv>
# Thin wrapper around fetch_github_advisories with ecosystem=rubygems.
ruby_http_advisories() {
  fetch_github_advisories "rubygems" "$@"
}

fetch_ruby_delta() {
  local name="$1"
  local cutoff="$2"

  # 1. Versions list — always HTTP (registry has no local mirror of dates).
  local versions_api="https://rubygems.org/api/v1/versions/${name}.json"
  local versions_raw
  versions_raw=""
  versions_raw=$(curl -fsSL --max-time 10 "$versions_api" 2>/dev/null) || return 0
  [ -z "$versions_raw" ] && return 0

  # Output TSV: pre_cutoff_latest \t current_latest \t current_date \t post_cutoff_versions_csv
  local tsv
  tsv=""
  tsv=$(printf '%s' "$versions_raw" | jq -r \
    --arg cutoff "$cutoff" '
      def vkey: split(".") | map(tonumber? // 0);
      [ .[]
        | select(.prerelease == false)
        | select((.platform // "ruby") == "ruby")
      ]
      | unique_by(.number)
      | sort_by(.number | vkey)
      | last as $highest
      | select($highest != null and $highest.created_at >= ($cutoff + "T00:00:00"))
      | (map(select(.created_at < ($cutoff + "T00:00:00"))) | last) as $pre
      | ($pre.number // "0") as $pre_num
      | (map(select(.created_at >= ($cutoff + "T00:00:00")))
         | map(select((.number | vkey) > ($pre_num | vkey)))) as $post
      | select(($post | length) > 0)
      | [
          ($pre.number // ""),
          $highest.number,
          ($highest.created_at[0:10]),
          ($post | map(.number) | join(","))
        ]
      | @tsv
    ' 2>/dev/null) || tsv=""

  [ -z "$tsv" ] && return 0

  local pre_v cur_v cur_date post_versions
  IFS=$'\t' read -r pre_v cur_v cur_date post_versions <<< "$tsv"

  # 2. Header
  local pre_label="${pre_v:-(introduced)}"
  printf '%s: %s (last seen) → %s (current, %s)\n' "$name" "$pre_label" "$cur_v" "$cur_date"

  # 3. Notes — local CHANGELOG.md preferred when toolchain present, HTTP fallback.
  dispatch notes ruby "$name" "$post_versions"

  # 4. Advisories — bundler-audit preferred, GitHub Advisories fallback.
  dispatch advisories ruby "$name" "$post_versions"
}
