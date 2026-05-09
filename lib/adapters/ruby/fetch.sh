#!/usr/bin/env bash
# Emit a multi-line delta block for a gem if anything was released after cutoff.
#
# Block format:
#   <name>: <pre_cutoff_latest> (last seen) → <current_latest> (current, <YYYY-MM-DD>)[ | project: <pin>]
#     <ver>: <bullet1>; <bullet2>; <bullet3>
#     [<sub-gem>] <ver>: <bullets>                (Rails meta-gem only)
#     <ver>: <GHSA-...> [<severity>] <CVE-...>: <summary>
#
# A first-release-post-cutoff gem uses "(introduced)" in place of the
# pre-cutoff version. Silent if nothing post-cutoff.
#
# When `project_pin` is provided (typically the version from
# Gemfile.lock) AND it differs from `current_latest`, a trailing
# ` | project: <pin>` segment is appended so an LLM consumer can tell
# what's actually installed apart from what's available — see issue #13.

fetch_ruby_delta() {
  local name="$1"
  local cutoff="$2"
  local project_pin="${3:-}"

  # Multi-platform gems get a platform suffix in Gemfile.lock
  # (e.g. "1.18.7-aarch64-linux-gnu"). Strip it so the comparison
  # against the registry's `current_latest` doesn't false-positive
  # and the rendered pin stays readable. Bundler always uses dots
  # (not dashes) for prerelease tags, so dash-prefixed arch tokens
  # are unambiguous.
  if [ -n "$project_pin" ]; then
    project_pin=$(printf '%s' "$project_pin" | \
      sed -E 's/-(arm64|aarch64|x86_64|x64|x86|i686|powerpc64|sparc|riscv64|java|universal)(-.*)?$//')
  fi

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
      | join("|")
    ')

  [ -z "$tsv" ] && return 0

  # Fields delimited with `|` (not tab/space): when a gem was first
  # released post-cutoff `$pre.number` is null and produces an empty
  # leading field. With IFS=$'\t' bash treats leading whitespace as
  # significant only inside fields and strips a leading tab — every
  # subsequent field would shift down one position, e.g. cur_v ending
  # up with the date. `|` is not IFS whitespace, so leading-empty is
  # preserved verbatim.
  local pre_v cur_v cur_date post_versions
  IFS='|' read -r pre_v cur_v cur_date post_versions <<< "$tsv"

  # 2. Header line — include project pin only when it differs from
  # current_latest, so docs stay compact for fully-up-to-date gems.
  local pre_label="${pre_v:-(introduced)}"
  if [ -n "$project_pin" ] && [ "$project_pin" != "$cur_v" ]; then
    printf '%s: %s (last seen) → %s (current, %s) | project: %s\n' \
      "$name" "$pre_label" "$cur_v" "$cur_date" "$project_pin"
  else
    printf '%s: %s (last seen) → %s (current, %s)\n' \
      "$name" "$pre_label" "$cur_v" "$cur_date"
  fi

  # Metadata: source URI (local via gem specification, HTTP fallback).
  local repo_uri=""
  repo_uri=$(dispatch metadata ruby "$name") || repo_uri=""
  local gh_repo=""
  if [ -n "$repo_uri" ]; then
    gh_repo=$(parse_github_repo_from_url "$repo_uri")
  fi

  # Notes: local reads CHANGELOG from the gem dir (with Rails sub-gem
  # stitching for the meta-gem); HTTP fallback uses the already-resolved
  # gh_repo, dropping back to GitHub Releases → raw CHANGELOG.md.
  dispatch notes ruby "$name" "$post_versions" "$gh_repo"

  # Advisories: local bundler-audit, fall back to GitHub Advisories API.
  dispatch advisories ruby "$name" "$post_versions"
}
