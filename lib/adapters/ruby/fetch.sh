#!/usr/bin/env bash
# Emit a multi-line delta block for a gem if anything was released after cutoff.
#
# Block format:
#   <name>: <pre_cutoff_latest> (last seen) → <current_latest> (current, <YYYY-MM-DD>)
#     <ver>: <bullet1>; <bullet2>; <bullet3>      [if GitHub release notes available]
#     <ver>: <CVE-XXXX-NNNN> ... [security]
#
# Silent if nothing post-cutoff.

fetch_ruby_delta() {
  local name="$1"
  local cutoff="$2"

  # 1. Versions: compute pre_cutoff_latest, current_latest, and post-cutoff version list.
  local versions_api="https://rubygems.org/api/v1/versions/${name}.json"
  local versions_raw
  versions_raw=$(curl -fsSL --max-time 10 "$versions_api" 2>/dev/null) || return 0

  # Output TSV: pre_cutoff_latest \t current_latest \t current_date \t post_cutoff_versions_csv
  local tsv
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
    ')

  [ -z "$tsv" ] && return 0

  local pre_v cur_v cur_date post_versions
  IFS=$'\t' read -r pre_v cur_v cur_date post_versions <<< "$tsv"

  # 2. Header line
  local pre_label="${pre_v:-(introduced)}"
  printf '%s: %s (last seen) → %s (current, %s)\n' "$name" "$pre_label" "$cur_v" "$cur_date"

  # 3. Metadata (source URI for the gem's repo) — local via `gem
  # specification` if Ruby toolchain is present, HTTP fallback otherwise.
  local repo_uri=""
  repo_uri=$(dispatch metadata ruby "$name") || repo_uri=""

  if [ -n "$repo_uri" ]; then
    local gh_repo
    gh_repo=$(parse_github_repo_from_url "$repo_uri")

    if [ -n "$gh_repo" ]; then
      local notes
      notes=""
      notes=$(fetch_github_release_notes "$gh_repo" "$post_versions") || notes=""
      if [ -n "$notes" ]; then
        printf '%s\n' "$notes"
      else
        fetch_changelog_md "$gh_repo" "$post_versions"
      fi
    fi
  fi

  # Advisories: prefer local (bundler-audit + ruby-advisory-db) when the
  # toolchain is present; fall back to GitHub Advisories API otherwise.
  # Notes/metadata stay HTTP-only for now — local CHANGELOGs in Rails
  # monorepo sub-gems regress output (CVE listings live in sibling
  # sub-gems' files). Revisit when we have per-monorepo strategy.
  dispatch advisories ruby "$name" "$post_versions"
}
