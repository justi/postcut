#!/usr/bin/env bash
# Ruby local-toolchain adapter functions. Empty output on any failure;
# the router falls back to the HTTP path when local returns empty.
#
# Activation gate: router checks `command -v gem` before invoking these.
# Additional tools (e.g. bundler-audit) are checked per function and
# gracefully skipped if absent.

# ruby_local_metadata <pkg>
# Stdout: best-effort source URI (github / homepage), or empty.
# Reads from the locally-installed gem's gemspec — no HTTP.
ruby_local_metadata() {
  local pkg="$1"
  [ -z "$pkg" ] && return 0

  # Try metadata block first (has source_code_uri for most modern gems).
  local meta=""
  meta=$(gem specification "$pkg" metadata 2>/dev/null) || meta=""

  local uri=""
  if [ -n "$meta" ]; then
    uri=$(printf '%s' "$meta" \
      | awk '/^source_code_uri:/ { sub(/^source_code_uri:[[:space:]]*/, ""); print; exit }')
  fi

  # Fall back to homepage field if metadata had no source_code_uri.
  # Format: "--- https://example.com"
  if [ -z "$uri" ]; then
    local hp=""
    hp=$(gem specification "$pkg" homepage 2>/dev/null) || hp=""
    if [ -n "$hp" ]; then
      uri=$(printf '%s' "$hp" \
        | awk '/^---[[:space:]]/ { sub(/^---[[:space:]]+/, ""); print; exit }')
    fi
  fi

  [ -z "$uri" ] && return 0
  printf '%s\n' "$uri"
}

# ruby_local_advisories <pkg> <versions_csv>
# Stdout: "  X.Y.Z: GHSA-XXX [severity] CVE-XXXX-NNNN: summary"
# Pulls advisories from the local ruby-advisory-db via bundler-audit.
# Empty if bundler-audit is not installed or has no result for this gem
# whose patched-version intersects with our post-cutoff list.
ruby_local_advisories() {
  local pkg="$1"
  local versions_csv="$2"
  [ -z "$pkg" ] && return 0
  [ -z "$versions_csv" ] && return 0
  command -v bundler-audit >/dev/null 2>&1 || return 0

  local raw
  raw=""
  raw=$(bundler-audit check --no-update --format=json 2>/dev/null) || raw=""
  [ -z "$raw" ] && return 0

  printf '%s' "$raw" | jq -r \
    --arg vs "$versions_csv" \
    --arg pkg "$pkg" '
      ($vs | split(",")) as $versions
      | (.results // [])
      | map(select(.gem.name == $pkg))
      | .[]
      | . as $r
      # Extract concrete patched versions from constraint strings like
      # ">= 7.2.1.1", "~> 7.0.8, >= 7.0.8.5", "~> 6.1.7.9". Take the LAST
      # semver token in each (the most-specific lower bound), then exact-
      # match against post-cutoff versions to avoid substring false
      # positives where ">= 7.0.8.1" matched "7.0.8".
      | [
          ($r.advisory.patched_versions // [])[]
          | [scan("[0-9]+(?:\\.[0-9]+)+")]
          | last
        ]
      | map(select(. != null))
      | map(select(. as $pv | $versions | any(. == $pv)))
      | first as $hit
      | if $hit == null then empty
        else
          # GHSA / CVE prefix is conditional — bundler-audit currently
          # stores bare ids ("h47h-mwp9-c6q6" / "2024-47889"), but defend
          # against future format changes that prepend GHSA-/CVE-.
          ($r.advisory.ghsa // "no-GHSA"
           | if startswith("GHSA-") then . else "GHSA-\(.)" end) as $ghsa
          | ($r.advisory.cve // "no-CVE"
             | if (. == "no-CVE" or startswith("CVE-")) then . else "CVE-\(.)" end) as $cve
          | "  \($hit): \($ghsa) [\($r.advisory.criticality // "unknown")] \($cve): " +
            ($r.advisory.title // "" | gsub("\\s+"; " ") | .[0:140])
        end
    ' 2>/dev/null | sort -u
}

# Rails meta-gem decomposition. List frozen at Rails 7.x — Rails 8.x had
# not added new sub-gems by 2026-05.
RUBY_RAILS_SUBGEMS="activesupport activemodel activerecord actionview actionpack activejob actionmailer actioncable actionmailbox actiontext activestorage railties"

# ruby_local_notes <pkg> <versions_csv> [_gh_repo_unused]
# Stdout: same shape as fetch_github_release_notes ("  ver: bullet1; ...").
# For pkg=='rails', stitches sub-gem CHANGELOGs and prefixes each line with
# "[sub-gem]" so the meta-gem expands to per-component notes.
#
# Third arg is accepted (and ignored) so the dispatcher can pass the same
# argument list used by ruby_http_notes — local reads CHANGELOG from the
# installed gem directory and doesn't need a GitHub repo hint.
#
# Gating: returns empty if the highest installed version is below the
# highest version in versions_csv. The local CHANGELOG only carries history
# up to the installed version; without this gate we'd silently drop newer
# post-cutoff versions instead of falling through to HTTP.
ruby_local_notes() {
  local pkg="$1"
  local versions_csv="$2"
  [ -z "$pkg" ] && return 0
  [ -z "$versions_csv" ] && return 0

  if [ "$pkg" = "rails" ]; then
    local sub_pkg
    for sub_pkg in $RUBY_RAILS_SUBGEMS; do
      _ruby_local_notes_one "$sub_pkg" "$versions_csv" "[${sub_pkg}] "
    done
    return 0
  fi

  _ruby_local_notes_one "$pkg" "$versions_csv" ""
}

_ruby_local_notes_one() {
  local pkg="$1"
  local versions_csv="$2"
  local prefix="$3"

  local gemdir
  gemdir=$(gem env gemdir 2>/dev/null) || return 0
  [ -z "$gemdir" ] && return 0

  # `[0-9]*` after the dash — anchors on the version digit so we don't
  # match sibling gems like `rails-html-sanitizer-*` for pkg=='rails'.
  local pkg_dir
  pkg_dir=$(ls -d "${gemdir}/gems/${pkg}-"[0-9]*/ 2>/dev/null | sort -V | tail -1)
  pkg_dir="${pkg_dir%/}"
  [ -z "$pkg_dir" ] && return 0
  [ -d "$pkg_dir" ] || return 0

  local installed_v
  installed_v="${pkg_dir##*/${pkg}-}"
  local max_csv_v
  max_csv_v=$(printf '%s\n' "${versions_csv//,/$'\n'}" | sort -V | tail -1)
  local highest
  highest=$(printf '%s\n%s\n' "$installed_v" "$max_csv_v" | sort -V | tail -1)
  [ "$highest" = "$installed_v" ] || return 0

  local f changelog=""
  for f in CHANGELOG.md CHANGES.md History.md History.markdown NEWS.md; do
    if [ -f "${pkg_dir}/${f}" ]; then
      changelog="${pkg_dir}/${f}"
      break
    fi
  done
  [ -z "$changelog" ] && return 0

  local content
  content=$(cat "$changelog" 2>/dev/null) || return 0
  [ -z "$content" ] && return 0

  _parse_changelog_content "$content" "$versions_csv" "$prefix"
}

# ruby_http_notes <pkg> <versions_csv> [gh_repo_hint]
# HTTP fallback for notes. If gh_repo_hint is provided (e.g., already
# resolved by the caller), uses it directly — otherwise resolves the repo
# via ruby_http_metadata. Tries GitHub Releases first; falls back to raw
# CHANGELOG.md.
ruby_http_notes() {
  local pkg="$1"
  local versions_csv="$2"
  local gh_repo="${3:-}"
  [ -z "$pkg" ] && return 0
  [ -z "$versions_csv" ] && return 0

  if [ -z "$gh_repo" ]; then
    local meta_uri
    meta_uri=$(ruby_http_metadata "$pkg") || meta_uri=""
    gh_repo=$(parse_github_repo_from_url "$meta_uri")
  fi
  [ -z "$gh_repo" ] && return 0

  local notes
  notes=$(fetch_github_release_notes "$gh_repo" "$versions_csv") || notes=""
  if [ -n "$notes" ]; then
    printf '%s\n' "$notes"
    return 0
  fi
  fetch_changelog_md "$gh_repo" "$versions_csv"
}

# ruby_http_metadata <pkg>
# HTTP fallback for metadata. Calls rubygems gems-meta endpoint and
# extracts the source URI in the same precedence the local path uses.
ruby_http_metadata() {
  local pkg="$1"
  [ -z "$pkg" ] && return 0

  local raw=""
  raw=$(curl -fsSL --max-time 10 "https://rubygems.org/api/v1/gems/${pkg}.json" 2>/dev/null) || raw=""
  [ -z "$raw" ] && return 0

  printf '%s' "$raw" | jq -r '
    .source_code_uri // .metadata.source_code_uri // .homepage_uri // ""
  ' 2>/dev/null
}

# ruby_http_advisories <pkg> <versions_csv>
# Thin wrapper so the router can fall back to GitHub Advisories when the
# local advisory DB has no fresh entries for the package.
ruby_http_advisories() {
  fetch_github_advisories "rubygems" "$@"
}
